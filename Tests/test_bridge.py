import importlib.util, pathlib, unittest, subprocess, os, signal, time
from unittest.mock import patch
ROOT=pathlib.Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('bridge',ROOT/'Helpers/bridge.py')
b=importlib.util.module_from_spec(spec);spec.loader.exec_module(b)

class ParserTests(unittest.TestCase):
    def test_codex_multi_bucket_over_legacy(self):
        metrics,plan=b.parse_codex({'rateLimits':{'primary':{'usedPercent':99}},'rateLimitsByLimitId':{'codex':{'planType':'pro','primary':{'usedPercent':39,'windowDurationMins':10080,'resetsAt':2000000000},'secondary':None}}})
        self.assertEqual(len(metrics),1);self.assertEqual(metrics[0]['value'],61);self.assertEqual(plan,'pro')
        self.assertEqual(metrics[0]['resetAt'],2000000000)
    def test_missing_is_not_zero(self):
        self.assertEqual(b.parse_codex({'rateLimits':{}})[0],[])
        self.assertEqual(b.parse_qoder({'session':{'total_credits':0}}),[None,None,None])
        self.assertIsNone(b.metric('x','x',None))
        self.assertEqual(b.metric('x','x',0)['value'],0)
    def test_kimi_legacy_and_current(self):
        old={'kind':'ok','summary':{'window':{'duration':1,'unit':'week'},'used':12,'limit':100,'reset_at':'2026-09-24T00:00:00Z'},'limits':[]}
        new={'kind':'ok','quota':{'usages':{'limit7d':{'usedRatio':.12}},'extraUsage':{'balanceCents':1234,'currency':'USD'}}}
        self.assertEqual(b.parse_kimi(old)[0]['value'],88)
        self.assertEqual(b.parse_kimi(new)[0]['value'],88)
        self.assertEqual(b.parse_kimi(new)[1]['value'],12.34)
        with self.assertRaises(b.QueryError):b.parse_kimi({'kind':'error','status':401})
    def test_invalid_numeric_data_is_not_shown(self):
        for v in [None,'unknown',True,float('nan'),float('inf')]: self.assertIsNone(b.number(v))
        with self.assertRaises(b.QueryError): b.metric('q','Quota',105)
    def test_qoder_no_double_count_session(self):
        data={'userQuota':{'remaining':5099,'used':901,'total':6000},'session':{'total_credits':100},'expiresAt':1790524800000}
        m=b.parse_qoder(data)[0]
        self.assertEqual(m['value'],5099);self.assertEqual(m['used'],901)
        self.assertEqual(m['resetAt'],1790524800)
    def test_agy_groups_and_relative_reset(self):
        screen='''GEMINI MODELS
Weekly Limit Remaining
[###] 97.77%
Refreshes in 148h 51m
Five Hour Limit Remaining
[###] 100.00%
Quota available
CLAUDE AND GPT MODELS
Weekly Limit Remaining
[###] 100.00%
Quota available
Five Hour Limit Remaining
[###] 100.00%
Quota available'''
        m=b.parse_agy(screen,1000)
        self.assertEqual(len(m),4);self.assertEqual(m[0]['value'],97.77)
        self.assertEqual(m[0]['resetAt'],1000+148*3600+51*60)
        self.assertIsNone(m[1]['resetAt'])
        self.assertEqual(b.parse_agy('new unsupported layout'),[])
    def test_no_empty_snapshot_and_identity_not_plaintext(self):
        with self.assertRaises(b.QueryError): b.snapshot('x','secret','api',[])
        s=b.snapshot('x','secret','api',[b.metric('x','x',1)])
        self.assertNotIn('secret',str(s));self.assertEqual(s['account'],b.fingerprint('secret'))
    def test_http_errors_are_redacted(self):
        import urllib.error
        class Opener:
            def __init__(self,status):self.status=status
            def open(self,*a,**kw):raise urllib.error.HTTPError('https://example.com/secret',self.status,'token=private',{},None)
        for status,code in [(401,'auth'),(403,'auth'),(429,'rateLimited'),(500,'network')]:
            with patch.object(b.urllib.request,'build_opener',return_value=Opener(status)):
                with self.assertRaises(b.QueryError) as e:b.get('https://example.com','secret')
                self.assertEqual(e.exception.code,code);self.assertNotIn('private',e.exception.message)
    def test_owned_process_is_terminated(self):
        with b.child(['/bin/sleep','30'],stdout=subprocess.DEVNULL) as p:
            pid=p.pid;self.assertIsNone(p.poll())
        self.assertIsNotNone(p.poll());self.assertEqual(b.CHILDREN,[])

if __name__=='__main__':unittest.main()

class LocalUsageTests(unittest.TestCase):
    def test_streaming_dedup_and_model_filter(self):
        import tempfile,json,datetime
        now=time.time();stamp=datetime.datetime.fromtimestamp(now-60,datetime.timezone.utc).isoformat()
        def record(ident,out,model='deepseek-flash'):
            return {'type':'assistant','timestamp':stamp,'message':{'id':ident,'model':model,'usage':{'input_tokens':100,'output_tokens':out,'cache_read_input_tokens':10}}}
        with tempfile.TemporaryDirectory() as d:
            root=pathlib.Path(d)
            (root/'a.jsonl').write_text('\n'.join(json.dumps(r) for r in [record('one',1),record('one',9),record('two',4),record('other',999,'claude-sonnet')]))
            (root/'b.jsonl').write_text(json.dumps(record('one',9)))
            result=b.local_deepseek_usage(root,now)
            self.assertEqual(result['messageCount'],2)
            self.assertEqual(result['days'][0]['output'],13)
            self.assertEqual(result['days'][0]['input'],200)
            self.assertIsNone(result['days'][0]['cacheWrite'])
            self.assertFalse(result['incomplete'])

class WorkspaceIsolationTests(unittest.TestCase):
    def test_cli_and_version_probe_cannot_discover_home_repository(self):
        import tempfile
        with tempfile.TemporaryDirectory() as d:
            home = pathlib.Path(d)
            subprocess.run(['/usr/bin/git', 'init', '-q', str(home)], check=True)
            with patch.object(b, 'HOME', home):
                work = b.query_workspace()
                # Reproduce the original bug without enumerating any personal files.
                original = subprocess.run(['/usr/bin/git', 'rev-parse', '--show-toplevel'], cwd=work, capture_output=True)
                self.assertEqual(original.returncode, 0)
                for explicit_cwd in (False, True):
                    options = {'cwd': str(work)} if explicit_cwd else {}
                    inherited = dict(os.environ, GIT_DIR=str(home/'.git'), GIT_WORK_TREE=str(home), TERM='xterm')
                    with b.child(['/usr/bin/git', 'rev-parse', '--show-toplevel'], env=inherited,
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, **options) as process:
                        out, _ = process.communicate(timeout=3)
                        self.assertNotEqual(process.returncode, 0)
                        self.assertEqual(out, b'')
                with b.child(['/usr/bin/python3', '-c', 'import os; print(os.getcwd()); print(os.environ["TERM"])'],
                             env=dict(os.environ, TERM='xterm'), stdout=subprocess.PIPE) as process:
                    out, _ = process.communicate(timeout=3)
                    self.assertEqual(out.decode().splitlines(), [str(work.resolve()), 'xterm'])

#!/usr/bin/env python3
"""Read-only provider bridge. JSON stdin/stdout; never executes model prompts."""
import contextlib, datetime, hashlib, json, math, os, pathlib, re, select, selectors
import signal, socket, struct, subprocess, sys, tempfile, time, urllib.error, urllib.request, urllib.parse

ROOT = pathlib.Path(__file__).resolve().parent
HOME = pathlib.Path.home()
sys.path.insert(0, str(ROOT / 'vendor'))
CHILDREN = []

class QueryError(Exception):
    def __init__(self, code, message): self.code, self.message = code, message

def cleanup(*_):
    for p in list(CHILDREN):
        try: os.killpg(p.pid, signal.SIGTERM)
        except ProcessLookupError: pass
    for p in list(CHILDREN):
        try: p.wait(timeout=1)
        except subprocess.TimeoutExpired:
            try: os.killpg(p.pid, signal.SIGKILL); p.wait(timeout=1)
            except (ProcessLookupError, subprocess.TimeoutExpired): pass
    CHILDREN.clear()

def terminate(*_):
    cleanup()
    raise QueryError('cancelled', '查询已取消')

def query_workspace():
    work = HOME/'Library/Application Support/VibeStatistics/QueryWorkspace'
    work.mkdir(parents=True, exist_ok=True)
    return work

@contextlib.contextmanager
def child(args, **kw):
    # Metadata-only CLIs must not discover an ancestor repository (e.g. ~/.git)
    # and scan personal folders while collecting startup Git context.
    work = query_workspace()
    kw.setdefault('cwd', str(work))
    env = dict(kw.get('env', os.environ))
    for key in list(env):
        if key.startswith('GIT_'): del env[key]
    env['GIT_CEILING_DIRECTORIES'] = str(work.parent)
    kw['env'] = env
    p = subprocess.Popen(args, start_new_session=True, **kw); CHILDREN.append(p)
    try: yield p
    finally:
        try: os.killpg(p.pid, signal.SIGTERM)
        except ProcessLookupError: pass
        try: p.wait(timeout=2)
        except subprocess.TimeoutExpired:
            try: os.killpg(p.pid, signal.SIGKILL)
            except ProcessLookupError: pass
            p.wait()

        if p in CHILDREN: CHILDREN.remove(p)

def fingerprint(value): return hashlib.sha256(str(value).encode()).hexdigest()[:20]
def number(value):
    if value is None or isinstance(value, bool): return None
    try:
        x = float(value)
        return x if math.isfinite(x) else None
    except (ValueError, TypeError): return None

def epoch(value):
    if isinstance(value, (float,int)): return value / 1000 if value > 1e11 else value
    if not value: return None
    try: return datetime.datetime.fromisoformat(value.replace('Z','+00:00')).timestamp()
    except (ValueError,TypeError): return None

def metric(key,title,value,unit='%',kind='quota',used=None,total=None,reset=None,note=None):
    v=number(value)
    if v is None: return None
    if unit=='%' and not 0 <= v <= 100: raise QueryError('format','服务返回的百分比超出范围')
    return dict(id=key,title=title,value=v,unit=unit,kind=kind,used=number(used),total=number(total),resetAt=epoch(reset),note=note)

def snapshot(provider, account, source, metrics, plan=None):
    metrics=[m for m in metrics if m is not None]
    if not metrics: raise QueryError('unavailable','服务未返回可用额度，请检查登录或 CLI 版本')
    return dict(provider=provider,account=fingerprint(account),source=source,metrics=metrics,plan=plan,collectedAt=time.time(),status='ok')

class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise QueryError('network', '额度查询不允许重定向')

def get(url, key=None, local=False, raw_authorization=False):
    handlers = [NoRedirect()]
    if local: handlers.append(urllib.request.ProxyHandler({}))
    opener = urllib.request.build_opener(*handlers)
    req=urllib.request.Request(url,headers={'Authorization':key if raw_authorization else 'Bearer '+key} if key else {})
    try:
        with opener.open(req,timeout=18) as r: return json.load(r)
    except urllib.error.HTTPError as e:
        if e.code in (401,403): raise QueryError('auth','登录已过期或权限不足，请重新授权')
        if e.code==429: raise QueryError('rateLimited','查询受到限流，稍后自动重试')
        raise QueryError('network','服务暂不可用（HTTP %s）'%e.code)
    except (urllib.error.URLError,TimeoutError): raise QueryError('network','无法连接服务，请检查网络或本地 CLI')

def resolve(path, fallback):
    p=os.path.expanduser(path or fallback)
    if not os.path.isfile(p) or not os.access(p,os.X_OK): raise QueryError('missingCLI','未找到可执行 CLI，请在设置中选择路径')
    return p

class RPC:
    def __init__(self,p):
        self.p=p;self.buf=b'';self.next_id=0
    def send(self,obj): self.p.stdin.write((json.dumps(obj)+'\n').encode());self.p.stdin.flush()
    def call(self,method,params=None):
        self.next_id+=1;ident=self.next_id
        self.send(dict(id=ident,method=method,params=params or {}));deadline=time.monotonic()+22
        while time.monotonic()<deadline:
            if b'\n' not in self.buf:
                if not select.select([self.p.stdout],[],[],.3)[0]: continue
                data=os.read(self.p.stdout.fileno(),65536)
                if not data: raise QueryError('process','CLI 提前退出，请检查版本和登录')
                self.buf+=data
            while b'\n' in self.buf:
                line,self.buf=self.buf.split(b'\n',1)
                try: obj=json.loads(line)
                except ValueError: continue
                if obj.get('id')==ident:
                    if 'error' in obj: raise QueryError('auth','Codex 查询失败，请检查登录与 CLI 版本')
                    return obj.get('result',{})
        raise QueryError('timeout','CLI 查询超时')

def parse_codex(data):
    buckets=data.get('rateLimitsByLimitId')
    if not buckets: buckets={'codex': data.get('rateLimits') or {}}
    metrics=[];plan=None
    for key,b in buckets.items():
        plan=b.get('planType') or plan
        for window in ('primary','secondary'):
            w=b.get(window) or {};used=number(w.get('usedPercent'))
            if used is None: continue
            mins=w.get('windowDurationMins');label={300:'5 小时',10080:'每周'}.get(mins,('%s 分钟'%mins) if mins else window)
            metrics.append(metric(key+'.'+window,(b.get('limitName') or 'Codex')+' · '+label,100-used,used=used,total=100,reset=w.get('resetsAt')))
        credits=b.get('credits') or {}
        if credits.get('balance') is not None:
            metrics.append(metric(key+'.credits','附加 Credits',credits['balance'],'Credits','balance'))
    return metrics,plan

def codex(cfg):
    path=resolve(cfg.get('path'),'~/.local/bin/codex')
    with child([path,'app-server','--stdio'],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,cwd=cfg['cwd']) as p:
        rpc=RPC(p);rpc.call('initialize',{'clientInfo':{'name':'vibe_statistics','version':'0.1.0'},'capabilities':{'experimentalApi':True}})
        rpc.send({'method':'initialized'})
        account=rpc.call('account/read',{'refreshToken':False}).get('account') or {}
        data=rpc.call('account/rateLimits/read');metrics,plan=parse_codex(data)
        identity=data.get('accountId') or account.get('email')
        if not identity: raise QueryError('auth','Codex 未返回账户身份，请登录 ChatGPT 账户')
        return snapshot('codex',identity,'官方 · Codex app-server',metrics,plan)

def parse_kimi(data):
    if data.get('kind')=='error': raise QueryError('auth' if data.get('status') in (401,403) else 'network','Kimi 额度查询失败，请检查登录或稍后刷新')
    metrics=[]
    if 'quota' in data:
        q=data.get('quota') or {}
        for key,v in (q.get('usages') or {}).items():
            used=number(v.get('usedRatio'))
            if used is not None: metrics.append(metric(key,{'limit5h':'5 小时','limit7d':'每周','monthTotal':'月度总额度','monthCode':'月度代码额度'}.get(key,key),100-used*100,used=used*100,total=100,reset=v.get('resetAt')))
        wallet=q.get('extraUsage')
        if wallet:
            balance=number(wallet.get('balanceCents'))
            metrics.append(metric('wallet','额外用量余额',balance/100 if balance is not None else None,wallet.get('currency') or 'CNY','balance'))
    else:
        entries=([data['summary']] if data.get('summary') else [])+(data.get('limits') or [])
        for v in entries:
            w=v.get('window') or {};key=str(w.get('duration'))+str(w.get('unit'));limit=number(v.get('limit'));used=number(v.get('used'))
            label={'1week':'每周','5hour':'5 小时'}.get(key,key)
            if limit is not None and limit>0 and used is not None: metrics.append(metric(key,label,100*(1-used/limit),used=used,total=limit,reset=v.get('reset_at')))
        wallet=data.get('extra_usage')
        if wallet:
            balance=number(wallet.get('balance_cents'))
            metrics.append(metric('wallet','额外用量余额',balance/100 if balance is not None else None,wallet.get('currency') or 'CNY','balance'))
    return metrics

def kimi_at(port):
    token=(HOME/'.kimi-code/server.token').read_text().strip();base='http://127.0.0.1:'+str(port)+'/api/v1/'
    # Require Kimi's envelope before sending authenticated requests to a discovered local port.
    health=get(base+'healthz',local=True)
    if health.get('data',{}).get('ok') is not True: raise QueryError('network','Kimi 本地服务身份检查失败')
    result=get(base+'oauth/usage',token,local=True)
    if result.get('code')!=0: raise QueryError('auth','Kimi 登录或额度查询失败')
    identity=get(base+'oauth/userinfo',token,local=True)
    info=identity.get('data',{});user=info.get('userInfo') or info.get('user_info') or info
    ident=user.get('userId') or user.get('user_id')
    if not ident: raise QueryError('auth','Kimi 未返回账户身份，请重新登录')
    return snapshot('kimi',ident,'官方 · Kimi 本地 Server',parse_kimi(result['data']),user.get('userLevelName'))

def kimi(cfg):
    path=resolve(cfg.get('path'),'~/.kimi-code/bin/kimi')
    for f in (HOME/'.kimi-code/server/instances').glob('*.json'):
        try:
            inst=json.loads(f.read_text())
            if inst.get('host') in ('127.0.0.1','localhost'): return kimi_at(int(inst['port']))
        except (QueryError,OSError,ValueError,KeyError): pass
    sock=socket.socket();sock.bind(('127.0.0.1',0));port=sock.getsockname()[1];sock.close()
    with child([path,'web','--no-open','--host','127.0.0.1','--port',str(port)],stdout=subprocess.DEVNULL,stderr=subprocess.DEVNULL,cwd=cfg['cwd']) as p:
        deadline=time.monotonic()+18
        while time.monotonic()<deadline:
            if p.poll() is not None: raise QueryError('process','Kimi Server 未能启动')
            try:
                get(f'http://127.0.0.1:{port}/api/v1/healthz',local=True);break
            except QueryError: time.sleep(.4)
        return kimi_at(port)

def parse_qoder(data):
    metrics=[]
    for key,title in [('userQuota','套餐 Credits'),('addOnQuota','附加 Credits'),('orgResourcePackage','组织 Credits')]:
        q=data.get(key) or {};total=q.get('total',q.get('cap'))
        metrics.append(metric(key,title,q.get('remaining'),'Credits','quota',used=q.get('used'),total=total,reset=data.get('expiresAt') if key=='userQuota' else None,note='套餐到期时间' if key=='userQuota' else None))
    return metrics

def qoder(cfg):
    path=resolve(cfg.get('path'),'~/.qoder-cn/entry/qodercn')
    # The SDK expects the CLI runtime, not Qoder's shell/IDE dispatcher.
    if pathlib.Path(path).name in ('qodercn','qoder-cn'):
        candidates=[HOME/'.local/bin/qoderclicn',HOME/'.qoder-cn/bin/qoderclicn/qoderclicn']
        path=next((str(x) for x in candidates if x.is_file() and os.access(x,os.X_OK)),path)
    node=resolve(cfg.get('node'),'/opt/homebrew/bin/node')
    with child([node,str(ROOT/'qoder.mjs')],stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.DEVNULL,cwd=cfg['cwd']) as p:
        try: out,_=p.communicate(json.dumps(dict(path=path,cwd=cfg['cwd'],secret=cfg.get('secret'))).encode(),timeout=35)
        except subprocess.TimeoutExpired: raise QueryError('timeout','Qoder CN 查询超时')
        try: data=json.loads(out)
        except ValueError: raise QueryError('format','Qoder CN 返回了无法识别的数据')
        if not data or data.get('error'): raise QueryError('auth','Qoder CN 查询失败，请检查登录或提供 PAT')
        if not data.get('userId'): raise QueryError('unavailable','Qoder CN 未返回账户额度')
        return snapshot('qoder',data['userId'],'官方 · Qoder CN SDK',parse_qoder(data),data.get('userType'))

def local_deepseek_usage(root=None, now=None):
    """Deduplicate streamed/copy messages by provider message ID; retain only usage fields."""
    root=root or HOME/'.claude/projects'; now=now or time.time();cutoff=now-30*86400
    messages={};incomplete=False
    for path in root.glob('**/*.jsonl'):
        try:
            with path.open() as file:
                for line in file:
                    try: record=json.loads(line)
                    except ValueError: incomplete=True;continue
                    if record.get('type')!='assistant':continue
                    msg=record.get('message') or {};model=msg.get('model','')
                    if not model.startswith('deepseek'):continue
                    stamp=epoch(record.get('timestamp'));ident=msg.get('id');usage=msg.get('usage')
                    if stamp is None or stamp>now or not usage:continue
                    if not ident:incomplete=True;continue
                    key=(model,ident)
                    fields={'input':'input_tokens','output':'output_tokens','cacheRead':'cache_read_input_tokens','cacheWrite':'cache_creation_input_tokens'}
                    values={k:number(usage.get(v)) for k,v in fields.items()}
                    if values['input'] is None or values['output'] is None:incomplete=True;continue
                    if any(v is not None and (v<0 or not v.is_integer()) for v in values.values()):incomplete=True;continue
                    if key not in messages:messages[key]={'timestamp':stamp,**values}
                    else:
                        # Streaming fragments repeat cumulative usage, including copies in resumed sessions.
                        for k,v in values.items():
                            if v is not None:messages[key][k]=max(messages[key].get(k) or 0,v)
        except (OSError,UnicodeError):incomplete=True
    days={};recent_days={};recent_count=0
    for record in messages.values():
        day=datetime.datetime.fromtimestamp(record['timestamp']).strftime('%Y-%m-%d')
        targets=[days]
        if record['timestamp']>=cutoff:
            targets.append(recent_days);recent_count+=1
        for target in targets:
            row=target.setdefault(day,dict(date=day,input=0,output=0,cacheRead=0,cacheWrite=0))
            for field in ('input','output','cacheRead','cacheWrite'):
                if record[field] is None:row[field]=None
                elif row[field] is not None:row[field]+=int(record[field])
    if not messages:return None
    return dict(allTimeDays=sorted(days.values(),key=lambda x:x['date']),days=sorted(recent_days.values(),key=lambda x:x['date']),messageCount=recent_count,incomplete=incomplete,scope='本机全部 DeepSeek 会话，不按 API Key 归因')

def deepseek(cfg):
    secret=cfg.get('secret')
    if not secret and not cfg.get('explicitSecret'):
        try:
            env=json.loads((HOME/'.claude/settings.json').read_text()).get('env',{})
            if urllib.parse.urlparse(env.get('ANTHROPIC_BASE_URL','')).hostname!='api.deepseek.com': raise QueryError('auth','Claude Code 未配置 DeepSeek 官方服务，请填入官方 API Key')
            secret=env.get('ANTHROPIC_AUTH_TOKEN') or env.get('ANTHROPIC_API_KEY')
        except (OSError,ValueError): pass
    if not secret: raise QueryError('auth','请在设置中添加 DeepSeek API Key')
    data=get('https://api.deepseek.com/user/balance',secret)
    metrics=[]
    for b in data.get('balance_infos',[]):
        currency=b.get('currency')
        if currency not in ('CNY','USD'): continue
        metrics.append(metric(currency+'.balance','可用余额',b.get('total_balance'),currency,'balance',note='账户余额；变化不等于 Claude Code 支出'))
        metrics.append(metric(currency+'.granted','赠送余额',b.get('granted_balance'),currency,'balance'))
        metrics.append(metric(currency+'.topped','充值余额',b.get('topped_up_balance'),currency,'balance'))
    result=snapshot('deepseek',secret,'官方 · DeepSeek API（按 Key 隔离）',metrics,'按量付费')
    result['localUsage']=local_deepseek_usage()
    return result

def parse_glm(data):
    if not isinstance(data, dict): raise QueryError('format', '智谱返回了无法识别的数据')
    if data.get('success') is False or data.get('code') not in (None, 0, 200, '0', '200'):
        raise QueryError('auth', '智谱未返回套餐额度，请检查个人 Coding Plan 与 API Key')
    payload = data.get('data', data)
    if not isinstance(payload, dict) or not isinstance(payload.get('limits'), list):
        raise QueryError('format', '智谱未返回可识别的配额列表')
    metrics = []
    seen = set()
    for item in payload['limits']:
        if not isinstance(item, dict): raise QueryError('format', '智谱配额格式异常')
        kind = item.get('type')
        if kind not in ('TOKENS_LIMIT', 'TIME_LIMIT'): continue
        # Do not infer five-hour/week windows from ordering or reset timestamps.
        window = item.get('unit')
        amount = item.get('number')
        identity = 'glm.%s.%s.%s' % (kind, window, amount)
        if identity in seen: raise QueryError('format', '智谱返回了无法区分的配额窗口')
        seen.add(identity)
        title = 'Coding Plan' if kind == 'TOKENS_LIMIT' else 'MCP 工具'
        # Preserve only an explicit service-provided window label. Numeric unit
        # enums alone are not enough evidence to promise a particular duration.
        window_name = item.get('windowName')
        title += ' · ' + (window_name if isinstance(window_name, str) and 0 < len(window_name) < 60 else '配额窗口未注明')
        reset = epoch(item.get('nextResetTime'))
        if reset is not None and (not math.isfinite(reset) or reset <= 0): reset = None
        used_percentage = number(item.get('percentage'))
        used = number(item.get('currentValue'))
        total = number(item.get('usage'))
        note = '服务账户共享额度，不代表单个 Agent 用量'
        if reset is None: note += '；未提供重置时间，不计算消耗'
        if kind == 'TIME_LIMIT' and used is not None and total is not None:
            if used < 0 or total < 0 or used > total: raise QueryError('format', '智谱次数额度超出范围')
            metrics.append(metric(identity, title + '剩余次数', total-used, '次', used=used, total=total, reset=reset, note=note))
        elif used_percentage is not None:
            if not 0 <= used_percentage <= 100: raise QueryError('format', '智谱已用百分比超出范围')
            metrics.append(metric(identity, title + '剩余额度', 100-used_percentage, used=used_percentage, total=100, reset=reset, note=note))
    return metrics

def glm(cfg):
    secret = cfg.get('secret')
    if not secret: raise QueryError('auth', '请在设置中添加智谱个人 GLM Coding Plan API Key')
    data = get('https://open.bigmodel.cn/api/monitor/usage/quota/limit', secret, raw_authorization=True)
    return snapshot('glm', secret, '官方 · 智谱 GLM Coding Plan（账户共享额度）', parse_glm(data), 'GLM Coding Plan · 国内个人版')


def parse_agy(text,now=None):
    now=now or time.time();metrics=[];group=None;window=None
    lines=text.splitlines()
    for i,line in enumerate(lines):
        if line.strip() in ('GEMINI MODELS','CLAUDE AND GPT MODELS'): group=line.strip();window=None
        if 'Weekly Limit Remaining' in line: window='weekly'
        if 'Five Hour Limit Remaining' in line: window='5h'
        m=re.search(r'(\d+(?:\.\d+)?)%',line)
        if group and window and m:
            reset=None;note=None
            following=lines[i+1] if i+1<len(lines) else ''
            duration=re.search(r'Refreshes in (?:(\d+)h\s*)?(?:(\d+)m)?',following)
            if duration:
                reset=now+int(duration.group(1) or 0)*3600+int(duration.group(2) or 0)*60;note='重置时间由 CLI 倒计时估算'
            title=('Gemini' if group=='GEMINI MODELS' else 'Claude / GPT')+' · '+('每周' if window=='weekly' else '5 小时')
            metrics.append(metric(group+'.'+window,title,m.group(1),reset=reset,note=note));window=None
    return metrics

def antigravity(cfg):
    import pty,fcntl,termios,pyte
    path=resolve(cfg.get('path'),'~/.local/bin/agy')
    master,slave=pty.openpty();fcntl.ioctl(slave,termios.TIOCSWINSZ,struct.pack('HHHH',100,160,0,0))
    screen=pyte.Screen(160,100);stream=pyte.Stream(screen);env=dict(os.environ,TERM='xterm-256color')
    try:
        with child([path],stdin=slave,stdout=slave,stderr=slave,cwd=cfg['cwd'],env=env) as p:
            os.close(slave);slave=None
            def read(duration):
                end=time.monotonic()+duration
                while time.monotonic()<end:
                    if select.select([master],[],[],.1)[0]:
                        try: data=os.read(master,65536)
                        except OSError: break
                        if not data: break
                        stream.feed(data.decode(errors='replace'))
                        if b'\x1b[6n' in data: os.write(master,b'\x1b[1;1R')
                return '\n'.join(screen.display)
            deadline=time.monotonic()+20;trusted=False;initial=''
            while time.monotonic()<deadline:
                initial=read(.4)
                if 'Do you trust the contents of this project?' in initial and not trusted:
                    # Only the app-owned, empty query workspace is trusted, never a user project.
                    os.write(master,b'\r');trusted=True;continue
                if '? for shortcuts' in initial and re.search(r'[\w.+-]+@[\w.-]+',initial): break
                if p.poll() is not None: raise QueryError('process','Antigravity CLI 提前退出')
            else: raise QueryError('auth','请先在 Antigravity CLI 中完成登录')
            os.write(master,b'/usage');read(.3);os.write(master,b'\r')
            deadline=time.monotonic()+18;text=''
            while time.monotonic()<deadline:
                text=read(.5)
                metrics=parse_agy(text)
                if len(metrics)>=4: break
            else: raise QueryError('format','Antigravity 额度面板未识别，请检查 CLI 版本')
            match=re.search(r'Account:\s*([^\s]+)',text)
            identity=match.group(1) if match else None
            if not identity: raise QueryError('auth','Antigravity 未返回账户身份')
            plan=re.search(r'\((Google AI [^)]+)\)',initial)
            os.write(master,b'\x1b');read(.4);os.write(master,b'/credits');read(.3);os.write(master,b'\r')
            credit_text='';notices=[]
            deadline=time.monotonic()+8
            while time.monotonic()<deadline:
                credit_text=read(.4)
                if 'Remaining AI Credits:' in credit_text: break
            credit_match=re.search(r'Remaining AI Credits:\s*([\d,]+(?:\.\d+)?)',credit_text)
            if credit_match: metrics.append(metric('ai.credits','AI Credits',credit_match.group(1).replace(',',''),'Credits','balance'))
            elif 'AI Credits not enabled' in credit_text: notices.append('AI Credits 未启用，未修改官方计费设置。')
            else: notices.append('AI Credits 暂不可用；模型额度已读取。')
            result=snapshot('antigravity',identity,'官方 CLI · Antigravity /usage · /credits',metrics,plan.group(1) if plan else None)
            result['notices']=notices
            version=re.search(r'Antigravity CLI ([0-9]+\.[0-9]+\.[0-9]+)',initial)
            result['cliVersion']=version.group(1) if version else None
            return result
    finally:
        os.close(master)
        if slave is not None: os.close(slave)

def main():
    signal.signal(signal.SIGTERM,terminate);signal.signal(signal.SIGINT,terminate)
    cfg=json.load(sys.stdin);provider=cfg.get('provider')
    # Stable empty directory used exclusively for metadata-only CLI processes.
    cfg['cwd']=str(query_workspace())
    try:
        result={'codex':codex,'kimi':kimi,'qoder':qoder,'deepseek':deepseek,'glm':glm,'antigravity':antigravity}[provider](cfg)
        if result.get('status')=='ok' and provider in ('codex','kimi','qoder'):
            fallback={'codex':'~/.local/bin/codex','kimi':'~/.kimi-code/bin/kimi','qoder':'~/.qoder-cn/entry/qodercn'}[provider]
            try:
                with child([resolve(cfg.get('path'),fallback),'--version'],stdout=subprocess.PIPE,stderr=subprocess.DEVNULL) as p:
                    out,_=p.communicate(timeout=3)
                    version=re.search(r'[0-9]+\.[0-9]+\.[0-9]+',out.decode(errors='replace'))
                    result['cliVersion']=version.group(0) if version else None
            except (QueryError,subprocess.TimeoutExpired): pass
    except QueryError as e: result=dict(provider=provider,status='error',errorCode=e.code,message=e.message)
    except Exception: result=dict(provider=provider,status='error',errorCode='format',message='查询未完成，请检查登录、CLI 路径或版本')
    finally: cleanup()
    print(json.dumps(result,ensure_ascii=False,allow_nan=False))

if __name__=='__main__': main()

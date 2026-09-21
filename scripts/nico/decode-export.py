#!/usr/bin/env python3
"""Decode the lossless LZW transport used by export-page.js; no Figma credentials needed."""
import base64
import json
import sys
from pathlib import Path

def decode(raw):
    if len(raw) % 2:
        raise ValueError('Truncated export')
    codes = [int.from_bytes(raw[i:i + 2], 'big') for i in range(0, len(raw), 2)]
    table = {i: bytes([i]) for i in range(256)}
    word = table[codes[0]]
    output = [word]
    next_code = 256
    for code in codes[1:]:
        entry = table.get(code, word + word[:1] if code == next_code else None)
        if entry is None:
            raise ValueError('Invalid export code')
        output.append(entry)
        if next_code < 65535:
            table[next_code] = word + entry[:1]
            next_code += 1
        word = entry
    return json.loads(b''.join(output))

if __name__ == '__main__':
    source, destination = map(Path, sys.argv[1:])
    destination.mkdir(parents=True, exist_ok=True)
    for file in source.glob('*.b64'):
        data = decode(base64.b64decode(file.read_text(), validate=False))
        (destination / ('components-' + file.stem + '.json')).write_text(json.dumps(data, ensure_ascii=False, separators=(',', ':')) + '\n')

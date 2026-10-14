"""Bounded diagnostics for the native C2 Tablet. No shell interpolation."""
import json
import socket
import subprocess
import time
from pathlib import Path
from urllib.parse import urlsplit

ROOT = Path('/var/mobile/Library/FieldConsole')

def command(args):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=9)
    print(result.stdout[:48000].decode(errors='replace'))
    print('Tool exit code:', result.returncode)

def main():
    request = json.loads((ROOT / 'diagnostic-request.json').read_text())
    kind = request.get('kind')
    host = request.get('host', '').strip()
    if kind in ('dns', 'ping') and (not host or len(host)>253 or host.startswith('-') or any(c.isspace() for c in host)):
        raise ValueError('Enter a single hostname or IP address without spaces.')
    print('C2 Tablet diagnostic:', kind)
    print('UTC:', time.strftime('%Y-%m-%d %H:%M:%S', time.gmtime()))
    if kind == 'dns':
        found=sorted({entry[4][0] for entry in socket.getaddrinfo(host, None)})
        print('Host:', host)
        print('\n'.join(found))
    elif kind == 'ping':
        command(['/var/jb/sbin/ping', '-n', '-c', '3', host])
    elif kind == 'http':
        url=request.get('url', '').strip()
        parsed=urlsplit(url)
        if parsed.scheme not in ('http','https') or not parsed.hostname or parsed.username or parsed.password:
            raise ValueError('Use an http or https address without embedded credentials.')
        command(['/var/jb/usr/bin/curl','--head','--silent','--show-error','--max-time','8','--connect-timeout','4','--proto','=http,https','--',url])
    else:
        commands={
            'interfaces':['/var/jb/sbin/ifconfig','-a'],
            'routes':['/var/jb/usr/sbin/netstat','-rn'],
            'sockets':['/var/jb/usr/sbin/netstat','-an'],
            'storage':['/var/jb/usr/bin/df','-h'],
            'packages':['/var/jb/usr/bin/dpkg-query','-W'],
            'system':['/var/jb/usr/bin/uname','-a'],
            'processes':['/bin/ps','-A'],
        }
        if kind not in commands:
            raise ValueError('Unknown diagnostic.')
        command(commands[kind])

if __name__ == '__main__':
    try:
        main()
    except Exception as error:
        print('Diagnostic failed:', type(error).__name__, str(error))
        raise SystemExit(1)

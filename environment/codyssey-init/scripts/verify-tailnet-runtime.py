#!/usr/bin/env python3
"""Real local control-plane test; never authenticates to an external tailnet."""
import argparse
import hashlib
import ipaddress
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time
import urllib.request
import uuid


def docker(*args, check=True, **kwargs):
    return subprocess.run(['docker', *args], check=check, capture_output=True, text=True, **kwargs)


def wait_for(action, description, seconds=90):
    deadline = time.monotonic() + seconds
    last = None
    while time.monotonic() < deadline:
        try:
            value = action()
            if value:
                return value
        except (subprocess.CalledProcessError, json.JSONDecodeError) as error:
            last = error
        time.sleep(1)
    raise RuntimeError(f'Timed out: {description}; last error: {last}')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--disposable', action='store_true', required=True)
    parser.add_argument('--image', default='codyssey-tailscale:1.88.3-ephemeral')
    args = parser.parse_args()
    assert not os.environ.get('DOCKER_HOST'), 'Use a local disposable Docker context'
    context = os.environ.get('DOCKER_CONTEXT') or docker('context', 'show').stdout.strip()
    endpoint = docker('context', 'inspect', context, '--format', '{{ (index .Endpoints "docker").Host }}').stdout.strip()
    assert endpoint.startswith('unix:///'), 'A local Unix Docker socket is required'
    os.environ['DOCKER_CONTEXT'] = context
    # Freeze the built image even if another verification rebuilds its tag.
    args.image = docker('image', 'inspect', args.image, '--format', '{{.Id}}').stdout.strip()
    architecture = docker('info', '--format', '{{.Architecture}}').stdout.strip()
    arch, expected = {
        'x86_64': ('amd64', '5012577e6fc5d4234aab7b4be0d6e271ea1a4ec38521a8aa472f80ea1fe81cba'),
        'aarch64': ('arm64', '98981ea52a96260f310433c73927935bf7628eedcc4c3f747059506154edba78'),
    }[architecture]
    lab = 'codyssey-tailnet-' + uuid.uuid4().hex[:12]
    control, alpha, bravo = [lab + '-' + name for name in ('control', 'alpha', 'bravo')]
    containers, volumes = [], []
    network_created = False
    with tempfile.TemporaryDirectory(prefix='codyssey-tailnet-lab-', dir=Path.home()) as temporary:
        work = Path(temporary)
        binary = work / 'headscale'
        urllib.request.urlretrieve(f'https://github.com/juanfont/headscale/releases/download/v0.26.1/headscale_0.26.1_linux_{arch}', binary)
        assert hashlib.sha256(binary.read_bytes()).hexdigest() == expected
        binary.chmod(0o755)
        (work / 'config.yaml').touch()
        try:
            # No external control plane, DERP map, or auth key can be reached.
            docker('network', 'create', '--internal', lab)
            network_created = True
            subnet = docker('network', 'inspect', lab, '--format', '{{range .IPAM.Config}}{{.Subnet}}{{end}}').stdout.strip()
            ip = str(ipaddress.ip_network(subnet)[2])
            (work / 'derp.yaml').write_text(f'''regions:
  900:
    regionid: 900
    regioncode: vm-lab
    regionname: Isolated VM lab
    nodes:
      - name: vm-lab
        regionid: 900
        hostname: "{ip}"
        ipv4: "{ip}"
        stunport: -1
        stunonly: true
''')
            control_volume = control + '-state'
            docker('volume', 'create', control_volume)
            volumes.append(control_volume)
            docker('create', '--name', control, '--network', lab, '--ip', ip,
                   '--mount', f'type=bind,src={work},dst=/lab,readonly',
                   '--mount', f'type=volume,src={control_volume},dst=/var/lib/headscale',
                   '--entrypoint', '/lab/headscale', args.image, '--config', '/lab/config.yaml', 'serve')
            containers.append(control)
            (work / 'config.yaml').write_text(f'''server_url: http://{ip}:8080
listen_addr: 0.0.0.0:8080
metrics_listen_addr: 127.0.0.1:9090
grpc_listen_addr: 127.0.0.1:50443
grpc_allow_insecure: false
noise:
  private_key_path: /var/lib/headscale/noise.key
prefixes:
  v4: 100.64.0.0/10
  v6: fd7a:115c:a1e0::/48
  allocation: sequential
derp:
  server:
    enabled: false
  urls: []
  paths: [/lab/derp.yaml]
  auto_update_enabled: false
disable_check_updates: true
ephemeral_node_inactivity_timeout: 30m
database:
  type: sqlite
  sqlite:
    path: /var/lib/headscale/db.sqlite
policy:
  mode: file
  path: ""
dns:
  magic_dns: true
  base_domain: tailnet.vm.invalid
  override_local_dns: false
  nameservers:
    global: []
    split: {{}}
  search_domains: []
unix_socket: /var/lib/headscale/headscale.sock
unix_socket_permission: "0700"
log:
  level: warn
''')
            docker('start', control)
            def hs(*command):
                return docker('exec', control, '/lab/headscale', '--config', '/lab/config.yaml', *command, '--output', 'json')
            def ready():
                if docker('inspect', control, '--format', '{{.State.Running}}').stdout.strip() != 'true':
                    raise RuntimeError('Local Headscale exited during startup')
                return hs('users', 'list').returncode == 0
            wait_for(ready, 'local Headscale readiness')
            user = json.loads(hs('users', 'create', 'vm-lab').stdout)
            user_id = str(user['id'])

            def start_node(container, hostname):
                docker('run', '-d', '--name', container, '--hostname', hostname, '--network', lab,
                       '--device', '/dev/net/tun:/dev/net/tun', '--cap-add', 'NET_ADMIN', '--cap-add', 'NET_RAW',
                       '--tmpfs', '/var/run/tailscale:mode=0700', '-e', 'TS_AUTHKEY=', args.image)
                containers.append(container)

            def status(container):
                return json.loads(docker('exec', container, 'tailscale', 'status', '--json').stdout)

            def running(container):
                value = status(container)
                return value if value.get('BackendState') == 'Running' else None

            def registered_nodes():
                value = json.loads(hs('nodes', 'list').stdout)
                return value if isinstance(value, list) else value.get('nodes', [])

            def login_node(container, hostname):
                # Headscale 0.26.1 classifies ephemerality from the key, unlike
                # hosted Tailscale's support for memory-state browser logins.
                key = json.loads(hs('preauthkeys', 'create', '--user', user_id,
                                    '--expiration', '1h', '--ephemeral').stdout)['key']
                docker('exec', '-i', container, 'sh', '-c', 'umask 077; cat > /var/run/tailscale/lab-auth.key', input=key)
                docker('exec', container, 'tailscale', 'up', '--reset', '--login-server', f'http://{ip}:8080',
                       '--auth-key', 'file:/var/run/tailscale/lab-auth.key', '--hostname', hostname,
                       '--accept-routes=true', '--accept-dns=true', '--shields-up=true', timeout=90)
                docker('exec', container, 'rm', '/var/run/tailscale/lab-auth.key')
                value = wait_for(lambda: running(container), 'local node login')
                argv = docker('exec', container, 'sh', '-c',
                    'for d in /proc/[0-9]*; do [ "$(cat "$d/comm" 2>/dev/null)" = tailscaled ] || continue; tr "\\000" "\\n" < "$d/cmdline"; done').stdout.splitlines()
                assert '--state=mem:' in argv, 'Daemon must use memory-only ephemeral state'
                docker('exec', container, 'sh', '-c',
                       'test ! -e /var/lib/tailscale/tailscaled.state && test ! -e /var/run/tailscale/tailscaled.state')
                record = next(node for node in registered_nodes() if str(node['id']) == str(value['Self']['ID']))
                auth = record.get('pre_auth_key') or record.get('preAuthKey') or {}
                assert auth.get('ephemeral') is True, 'Lab control plane must mark the node ephemeral'
                return value

            def removed(identity):
                return all(str(node['id']) != str(identity) for node in registered_nodes())

            for container, hostname in ((alpha, 'alpha'), (bravo, 'bravo')):
                start_node(container, hostname)
                wait_for(lambda: status(container), 'Tailscale daemon readiness')
                login_node(container, hostname)

            before = running(alpha)
            print('Local lab nodes authenticated; checking MagicDNS and terminal tools.', flush=True)
            resolver_before = docker('exec', alpha, 'cat', '/var/lib/codyssey-init/resolv.conf.base').stdout
            peer_ip = running(bravo)['TailscaleIPs'][0]
            def resolves_peer():
                # Docker can resolve the same bare hostname to a bridge IP;
                # the shell must prefer the MagicDNS search domain instead.
                result = docker('exec', alpha, 'getent', 'hosts', 'bravo', check=False)
                return result.returncode == 0 and peer_ip in result.stdout
            wait_for(resolves_peer, 'short MagicDNS hostname')
            docker('exec', alpha, 'getent', 'hosts', 'bravo.tailnet.vm.invalid')
            docker('exec', alpha, 'bash', '-ic', 'mise --version; mise exec -- zellij --version; zellij --version')
            for recreate in (False, True):
                print('Checking ephemeral ' + ('recreation' if recreate else 'restart'), flush=True)
                old_identity = before['Self']['ID']
                if recreate:
                    docker('stop', '-t', '30', alpha)
                    docker('rm', alpha)
                    containers.remove(alpha)
                    start_node(alpha, 'alpha')
                else:
                    docker('restart', '-t', '30', alpha)
                wait_for(lambda: removed(old_identity), 'old ephemeral node removed after shutdown')
                wait_for(lambda: status(alpha).get('BackendState') == 'NeedsLogin', 'fresh login required after restart')
                after = login_node(alpha, 'alpha')
                assert after['Self']['ID'] != old_identity, 'Restart must not restore the previous identity'
                assert docker('exec', alpha, 'cat', '/var/lib/codyssey-init/resolv.conf.base').stdout == resolver_before
                wait_for(resolves_peer, 'MagicDNS after ephemeral restart/recreation')
                before = after
            docker('exec', alpha, 'tailscale', 'down')
            def restored():
                return docker('exec', alpha, 'cmp', '-s', '/etc/resolv.conf', '/var/lib/codyssey-init/resolv.conf.base', check=False).returncode == 0
            wait_for(restored, 'base resolver restoration after disconnect')
            print('PASS: ephemeral authentication, old-node removal, fresh identities after restart/recreation, short/FQDN MagicDNS, resolver restoration, mise and zellij.')
        except Exception:
            for container in containers:
                result = docker('logs', '--tail', '30', container, check=False)
                print(result.stdout, result.stderr)
                if container != control:
                    for command in (['tailscale', 'status', '--json'], ['cat', '/etc/resolv.conf'],
                                    ['dig', '+time=2', '+tries=1', '@100.100.100.100', 'bravo.tailnet.vm.invalid']):
                        result = docker('exec', container, *command, check=False)
                        print(container, command, result.stdout, result.stderr)
            raise
        finally:
            failures = []
            for container in reversed(containers):
                if docker('rm', '-f', container, check=False).returncode:
                    failures.append(container)
            for volume in volumes:
                if docker('volume', 'rm', volume, check=False).returncode:
                    failures.append(volume)
            if network_created and docker('network', 'rm', lab, check=False).returncode:
                failures.append(lab)
            if failures:
                raise RuntimeError('Lab cleanup failed: ' + ', '.join(failures))
    print('PASS: local tailnet lab cleanup completed.')


if __name__ == '__main__':
    main()

#!/usr/bin/env bash
set -Eeuo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
python3 - "$repo_root" <<'PY'
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from threading import Thread
import hashlib
import os
import subprocess
import sys
import tempfile
import time

repo = Path(sys.argv[1])
payload = bytes(range(256)) * 512
digest = hashlib.sha256(payload).hexdigest()
new_payload = b'z' * len(payload)
new_digest = hashlib.sha256(new_payload).hexdigest()


def run_case(mode, seed=b'', function='download_sdk', limits=None):
    requests = []
    metadata = {}

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requested_range = self.headers.get('Range')
            offset = int(requested_range.removeprefix('bytes=').removesuffix('-')) if requested_range else 0
            if mode in {'refresh-same', 'refresh-changed'} and not self.path.endswith('.tar.zst'):
                body = metadata['signature' if self.path.endswith('.asc') else 'manifest']
                self.send_response(200)
                self.send_header('Content-Length', str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            requests.append(offset)
            count = len(requests)
            if mode == 'refresh-budget':
                if not self.path.endswith('/sdk.tar.zst'):
                    time.sleep(3)
                self.send_response(503)
                self.end_headers()
                return
            if mode in {'unavailable', 'budget'}:
                self.send_response(503)
                self.end_headers()
                return
            if mode == 'range-416' and count == 1:
                self.send_response(416)
                self.send_header('Content-Range', f'bytes */{len(payload)}')
                self.end_headers()
                return
            ignore_range = mode == 'ignore-range' and count == 2
            if ignore_range:
                offset = 0
            if mode in {'drop', 'slow'} and count > 1 and offset == 0:
                self.send_response(400)
                self.end_headers()
                return
            body = (new_payload if mode == 'refresh-changed' and count > 1 else payload)[offset:]
            if mode == 'corrupt':
                body = b'corrupt SDK archive'
            if mode == 'changed' and offset:
                body = b'x' * len(body)
            self.send_response(206 if requested_range and not ignore_range else 200)
            self.send_header('Content-Length', str(len(body)))
            if requested_range and not ignore_range:
                self.send_header('Content-Range', f'bytes {offset}-{len(payload)-1}/{len(payload)}')
            self.send_header('Connection', 'close')
            self.end_headers()
            drop = (mode == 'drop' and count <= 2) or (mode in {'ignore-range', 'changed', 'slow', 'refresh-same', 'refresh-changed'} and count == 1)
            try:
                self.wfile.write(body[:4096] if drop else body)
                self.wfile.flush()
                if mode == 'slow' and count == 1:
                    time.sleep(1.5)
            except (BrokenPipeError, ConnectionResetError):
                pass
            self.close_connection = True

        def log_message(self, *args):
            pass

    server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)
    thread = Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        with tempfile.TemporaryDirectory(prefix='sdk-resume-test.') as temporary:
            root = Path(temporary)
            cache = root / 'cache'
            cache.mkdir()
            archive_name = 'openwrt-sdk-fixture.tar.zst'
            cache_name = f'{digest}-{archive_name}' if mode in {'refresh-same', 'refresh-changed'} else 'sdk.tar.zst'
            archive = cache / cache_name
            partial = cache / (cache_name + '.part')
            if seed:
                partial.write_bytes(seed)
            env = dict(os.environ, RUNNER_TEMP=str(root), SDK_CACHE_DIR=str(cache),
                       EXPECTED_SDK_SHA256=digest, TEST_SDK_URL=f'http://127.0.0.1:{server.server_port}/sdk.tar.zst',
                       TEST_SDK_CACHE_NAME=cache_name,
                       SDK_DOWNLOAD_TIMEOUT='15', SDK_DOWNLOAD_REQUEST_TIMEOUT='5', SDK_DOWNLOAD_RETRY_COUNT='4',
                       SDK_METADATA_REFRESH='false', OPENWRT_DOWNLOADS_BASE_URL=f'http://127.0.0.1:{server.server_port}')
            env.update(limits or {})
            if mode in {'refresh-same', 'refresh-changed'}:
                key_home = root / 'gnupg'
                key_home.mkdir(mode=0o700)
                gpg = ['gpg', '--homedir', str(key_home), '--batch', '--pinentry-mode', 'loopback', '--passphrase', '']
                subprocess.run(gpg + ['--quick-generate-key', 'SDK Resume Test <sdk@example.invalid>', 'ed25519', 'sign', '0'], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                public_key = root / 'key.asc'
                public_key.write_bytes(subprocess.check_output(gpg + ['--armor', '--export']))
                keys = subprocess.check_output(gpg + ['--with-colons', '--list-keys'], text=True, stderr=subprocess.DEVNULL)
                fingerprint = next(line.split(':')[9] for line in keys.splitlines() if line.startswith('fpr:'))
                selected_digest = new_digest if mode == 'refresh-changed' else digest
                metadata['manifest'] = f'{selected_digest} *{archive_name}\n'.encode()
                metadata['signature'] = subprocess.check_output(gpg + ['--armor', '--detach-sign', '--output', '-'], input=metadata['manifest'])
                env.update(OPENWRT_SIGNING_KEY=str(public_key), OPENWRT_SIGNING_KEY_FINGERPRINT=fingerprint,
                           SDK_METADATA_REFRESH='true', SDK_DOWNLOAD_RETRY_COUNT='1')
            script = 'source scripts/SDK-script.sh; SDK_ARCHIVE="$SDK_CACHE_DIR/$TEST_SDK_CACHE_NAME"; RESOLVED_SDK_URL="$TEST_SDK_URL"; '
            if function == 'prepare_sdk_metadata':
                script += 'SDK_DOWNLOAD_DEADLINE=$((SECONDS + SDK_DOWNLOAD_TIMEOUT)); '
            script += function + ' "$TEST_SDK_URL"'
            started = time.monotonic()
            try:
                result = subprocess.run(['bash', '-c', script], cwd=repo, env=env, text=True,
                                        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=18)
            except subprocess.TimeoutExpired as error:
                raise AssertionError(f'{mode}: download exceeded the test budget') from error
            elapsed = time.monotonic() - started
            if mode == 'refresh-changed':
                archive = cache / f'{new_digest}-{archive_name}'
            return result, requests, archive.read_bytes() if archive.exists() else None, partial.read_bytes() if partial.exists() else None, elapsed
    finally:
        server.shutdown()
        server.server_close()
        thread.join()


def interrupted_transfers_resume():
    result, offsets, archive, partial, _ = run_case('drop')
    assert result.returncode == 0, result.stderr
    assert offsets == [0, 4096, 8192], offsets
    assert archive == payload and partial is None


def timed_out_transfer_resumes():
    result, offsets, archive, _, _ = run_case('slow', limits={'SDK_DOWNLOAD_REQUEST_TIMEOUT': '1'})
    assert result.returncode == 0, result.stderr
    assert offsets == [0, 4096], offsets
    assert archive == payload


def ignored_range_restarts_cleanly():
    result, offsets, archive, _, _ = run_case('ignore-range')
    assert result.returncode == 0, result.stderr
    assert offsets == [0, 4096, 0], offsets
    assert archive == payload


def rejected_range_restarts_cleanly():
    result, offsets, archive, _, _ = run_case('range-416', seed=payload[:4096])
    assert result.returncode == 0, result.stderr
    assert offsets == [4096, 0], offsets
    assert archive == payload


def completed_checkpoint_is_verified_without_network():
    result, offsets, archive, partial, _ = run_case('unavailable', seed=payload)
    assert result.returncode == 0, result.stderr
    assert offsets == [] and archive == payload and partial is None


def transport_failure_preserves_checkpoint():
    result, _, archive, partial, _ = run_case('unavailable', seed=payload[:4096], limits={'SDK_DOWNLOAD_RETRY_COUNT': '1'})
    assert result.returncode != 0
    assert archive is None and partial == payload[:4096]


def changed_bytes_are_never_published():
    result, offsets, archive, partial, _ = run_case('changed')
    assert offsets == [0, 4096], offsets
    assert result.returncode != 0 and archive is None and partial is None


def corrupt_archive_is_removed():
    result, _, archive, partial, _ = run_case('corrupt')
    assert result.returncode != 0 and archive is None and partial is None


def download_deadline_bounds_metadata_refreshes():
    result, _, archive, _, elapsed = run_case('budget', function='download_sdk_with_metadata_retry',
        limits={'SDK_DOWNLOAD_TIMEOUT': '2', 'SDK_DOWNLOAD_REQUEST_TIMEOUT': '1',
                'SDK_METADATA_REFRESH': 'true', 'OPENWRT_DOWNLOADS_BASE_URL': 'http://127.0.0.1:1'})
    assert result.returncode != 0 and archive is None
    assert elapsed < 5, elapsed
    assert 'Resolve OpenWrt main SDK' not in result.stderr, result.stderr


def metadata_refresh_cannot_extend_download_deadline():
    result, _, archive, _, elapsed = run_case('refresh-budget', function='download_sdk_with_metadata_retry',
        limits={'SDK_DOWNLOAD_TIMEOUT': '2', 'SDK_DOWNLOAD_REQUEST_TIMEOUT': '1',
                'SDK_DOWNLOAD_RETRY_COUNT': '1', 'SDK_METADATA_REFRESH': 'true'})
    assert result.returncode != 0 and archive is None
    assert elapsed < 5, elapsed


def metadata_backoff_respects_remaining_budget():
    result, _, _, _, elapsed = run_case('unavailable', function='prepare_sdk_metadata',
        limits={'SDK_DOWNLOAD_TIMEOUT': '1', 'SDK_METADATA_REFRESH': 'true'})
    assert result.returncode != 0
    assert elapsed < 1.8, elapsed


def unchanged_signed_metadata_keeps_progress():
    result, offsets, archive, partial, _ = run_case('refresh-same', function='download_sdk_with_metadata_retry')
    assert result.returncode == 0, result.stderr
    assert offsets == [0, 4096], offsets
    assert archive == payload and partial is None


def changed_signed_metadata_discards_progress():
    result, offsets, archive, partial, _ = run_case('refresh-changed', function='download_sdk_with_metadata_retry')
    assert result.returncode == 0, result.stderr
    assert offsets == [0, 0], offsets
    assert archive == new_payload and partial is None


failed = 0
for case in (interrupted_transfers_resume, timed_out_transfer_resumes, ignored_range_restarts_cleanly,
             rejected_range_restarts_cleanly, completed_checkpoint_is_verified_without_network,
             transport_failure_preserves_checkpoint, changed_bytes_are_never_published,
             corrupt_archive_is_removed, download_deadline_bounds_metadata_refreshes,
             metadata_refresh_cannot_extend_download_deadline, metadata_backoff_respects_remaining_budget,
             unchanged_signed_metadata_keeps_progress, changed_signed_metadata_discards_progress):
    try:
        case()
        print('PASS', case.__name__, flush=True)
    except Exception as error:
        failed += 1
        print('FAIL', case.__name__, str(error), file=sys.stderr, flush=True)
sys.exit(bool(failed))
PY

#!/usr/bin/env python3
"""Read-only proof for the CI simulator's synthetic cache; never copies the payload."""
import argparse
import hashlib
import json
from pathlib import Path


def evidence(container, request_log, checkpoint):
    store = container / 'Library' / 'Application Support' / 'chief'
    cache = store / 'snapshot-cache.json'
    raw = cache.read_bytes()
    envelope = json.loads(raw)
    if envelope.get('version') != 1 or envelope.get('snapshot', {}).get('api') != 2:
        raise ValueError('persisted cache is not the expected API 2 snapshot envelope')
    etag = envelope.get('etag')
    if not isinstance(etag, str) or not etag:
        raise ValueError('persisted cache is missing the app response ETag')
    records = request_log.read_text().splitlines()[checkpoint:]
    if not any(record.get('method') == 'GET'
               and record.get('path', '').split('?')[0] == '/v1/snapshot'
               and record.get('auth') == 'ok' and record.get('status') == 200
               and record.get('content_type') != 'application/x-kit-probe'
               and record.get('note') == f'etag {etag}' for record in map(json.loads, records)):
        raise ValueError('no fresh authenticated app snapshot 200 with the persisted ETag')
    if any(p != cache for p in store.glob('*.json')):
        raise ValueError('another JSON file is present in the capture store')
    return dict(container=container.name, cache_sha256=hashlib.sha256(raw).hexdigest(),
                api=2, waiting_files=0, matching_app_snapshot_200=True, action_checkpoint=checkpoint)


def main():
    p = argparse.ArgumentParser()
    p.add_argument('phase', choices=('cacheonline', 'cacheoffline'))
    p.add_argument('container', type=Path)
    p.add_argument('log', type=Path)
    p.add_argument('checkpoint', type=int)
    p.add_argument('prior', type=Path)
    args = p.parse_args()
    try:
        result = evidence(args.container.resolve(strict=True), args.log, args.checkpoint)
        if args.phase == 'cacheonline':
            args.prior.write_text(json.dumps(result))
        elif result != json.loads(args.prior.read_text()):
            raise ValueError('container or persisted snapshot changed across offline relaunch')
    except (OSError, ValueError) as exc:
        p.exit(1, f'{args.phase}: {exc}\n')
    print(args.phase, json.dumps(result, sort_keys=True))


if __name__ == '__main__':
    main()

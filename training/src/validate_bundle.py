from __future__ import annotations
import argparse, hashlib, json
from pathlib import Path

EXPECTED = {
    'cracks': {'D00', 'D10'},
    'pavement': {'D20', 'D40'},
    'surface': {'D50', 'D60', 'D90'},
}

def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open('rb') as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b''):
            digest.update(chunk)
    return digest.hexdigest()

def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--manifest', type=Path, required=True)
    parser.add_argument('--models-dir', type=Path, required=True)
    args = parser.parse_args()
    manifest = json.loads(args.manifest.read_text())
    assert manifest['schemaVersion'] == 1
    names = set()
    for agent in manifest['agents']:
        name = agent['name']
        assert name in EXPECTED, f'Unknown agent: {name}'
        assert set(agent['classes']) == EXPECTED[name], f'Class contract mismatch for {name}'
        model = args.models_dir / agent['file']
        assert model.is_file(), f'Missing model: {model}'
        actual = sha256(model)
        if agent['sha256'] != 'REPLACE_AFTER_EXPORT':
            assert actual == agent['sha256'], f'Checksum mismatch for {name}'
        names.add(name)
        print(f'{name}: {model.name} sha256={actual}')
    assert names == set(EXPECTED), 'All three agents are required'
    print('Bundle contract valid')

if __name__ == '__main__':
    main()

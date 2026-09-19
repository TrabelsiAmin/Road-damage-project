from __future__ import annotations
import argparse
from pathlib import Path
import yaml


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument('--config', type=Path, required=True)
    args = parser.parse_args()
    config = yaml.safe_load(args.config.read_text())
    root = Path(config['path'])
    class_count = len(config['names'])
    seen_images = set()
    total = 0
    for split in ('train', 'val', 'test'):
        image_dir = root / config[split].replace('images/', 'images/')
        label_dir = root / config[split].replace('images/', 'labels/')
        images = {p.stem for p in image_dir.glob('*') if p.suffix.lower() in {'.jpg', '.jpeg', '.png', '.webp'}}
        labels = {p.stem for p in label_dir.glob('*.txt')}
        if not images:
            raise SystemExit(f'{split}: no images found in {image_dir}')
        missing = images - labels
        if missing:
            raise SystemExit(f'{split}: missing labels for {sorted(missing)[:5]}')
        overlap = seen_images & images
        if overlap:
            raise SystemExit(f'image identity leakage across splits: {sorted(overlap)[:5]}')
        seen_images |= images
        for label in label_dir.glob('*.txt'):
            for line_no, line in enumerate(label.read_text().splitlines(), 1):
                fields = line.split()
                if len(fields) != 5:
                    raise SystemExit(f'{label}:{line_no}: expected five YOLO fields')
                cls, *coords = fields
                if not 0 <= int(cls) < class_count:
                    raise SystemExit(f'{label}:{line_no}: class ID out of range')
                if any(not 0 <= float(value) <= 1 for value in coords):
                    raise SystemExit(f'{label}:{line_no}: normalized coordinate out of range')
                total += 1
        print(f'{split}: {len(images)} images validated')
    print(f'valid dataset: {total} annotations, {len(seen_images)} unique images')

if __name__ == '__main__':
    main()

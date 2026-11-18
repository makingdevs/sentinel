"""Small hand-labelled sanity check, not a representative accuracy benchmark."""
import argparse
import json
from pathlib import Path


def iou(a, b):
    left, top = max(a[0], b[0]), max(a[1], b[1])
    right, bottom = min(a[2], b[2]), min(a[3], b[3])
    intersection = max(0, right-left) * max(0, bottom-top)
    union = (a[2]-a[0])*(a[3]-a[1]) + (b[2]-b[0])*(b[3]-b[1]) - intersection
    return intersection/union if union else 0


def evaluate(results, annotations):
    metrics = {}
    for annotation in annotations:
        record = next(item for item in results['results'] if item['file'] == annotation['file'])
        cls = annotation['class_id']
        gt = annotation['boxes'][:]
        predictions = []
        for item in record['objects']:
            if item['class_idx'] != cls:
                continue
            box = item['bbox']
            coords = [box['cx']-box['w']/2, box['cy']-box['h']/2, box['cx']+box['w']/2, box['cy']+box['h']/2]
            if annotation.get('ignore_edge_cars') and (coords[0] <= 1 or coords[2] >= 639):
                continue
            roi = annotation.get('roi')
            if roi and not (roi[0] <= box['cx'] <= roi[2] and roi[1] <= box['cy'] <= roi[3]):
                continue
            predictions.append((item['prob'], coords))
        tp = fp = 0
        for _, box in sorted(predictions, reverse=True):
            overlaps = [iou(box, truth) for truth in gt]
            if overlaps and max(overlaps) >= .5:
                gt.pop(overlaps.index(max(overlaps)))
                tp += 1
            else:
                fp += 1
        fn = len(gt)
        metrics[annotation['file']] = {'class_id': cls, 'tp': tp, 'fp': fp, 'fn': fn,
                                    'precision': tp/(tp+fp) if tp+fp else None,
                                    'recall': tp/(tp+fn) if tp+fn else None}
    return metrics


if __name__ == '__main__':
    parser = argparse.ArgumentParser()
    parser.add_argument('results')
    args = parser.parse_args()
    annotations = json.loads((Path(__file__).parent/'sanity_annotations.json').read_text())
    print(json.dumps(evaluate(json.loads(Path(args.results).read_text()), annotations), indent=2))

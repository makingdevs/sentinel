import importlib.util
from pathlib import Path
spec = importlib.util.spec_from_file_location('evaluate', Path(__file__).parents[1]/'evaluate.py')
evaluate = importlib.util.module_from_spec(spec)
spec.loader.exec_module(evaluate)


def test_iou_and_one_to_one_matching():
    assert evaluate.iou([0, 0, 10, 10], [0, 0, 10, 10]) == 1
    assert evaluate.iou([0, 0, 10, 10], [20, 20, 30, 30]) == 0
    prediction = {'class_idx': 0, 'prob': .9, 'bbox': {'cx': 5, 'cy': 5, 'w': 10, 'h': 10}}
    results = {'results': [{'file': 'frame', 'objects': [prediction, prediction]}]}
    labels = [{'file': 'frame', 'class_id': 0, 'boxes': [[0, 0, 10, 10]]}]
    score = evaluate.evaluate(results, labels)['frame']
    assert (score['tp'], score['fp'], score['fn']) == (1, 1, 0)

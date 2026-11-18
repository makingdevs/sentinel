"""Download/export identical YOLO11n weights; keep generated artifacts local."""
import hashlib
import json
import os
import urllib.request
from pathlib import Path

root = Path(__file__).resolve().parents[1]
(root / 'tmp' / 'ultralytics').mkdir(parents=True, exist_ok=True)
os.environ.setdefault('YOLO_CONFIG_DIR', str(root / 'tmp' / 'ultralytics'))
from ultralytics import YOLO

models = root / 'models'
models.mkdir(exist_ok=True)
os.chdir(models)
expected = '0ebbc80d4a7680d14987a577cd21342b65ecfd94632bd9a8da63ae6417644ee1'
weights = models / 'yolo11n.pt'
if not weights.exists():
    temporary = models / 'yolo11n.pt.part'
    urllib.request.urlretrieve('https://github.com/ultralytics/assets/releases/download/v8.3.0/yolo11n.pt', temporary)
    if hashlib.sha256(temporary.read_bytes()).hexdigest() != expected:
        raise ValueError('downloaded model checksum mismatch')
    temporary.replace(weights)
if hashlib.sha256(weights.read_bytes()).hexdigest() != expected:
    raise ValueError('local model checksum mismatch')
model = YOLO(str(weights))
model.export(format='onnx', imgsz=640, opset=17, dynamic=False, simplify=False, nms=False, device='cpu')
(models / 'coco_classes.json').write_text(json.dumps(list(model.names.values())))
manifest = {'model': 'yolo11n', 'size': 640, 'opset': 17, 'files': {}}
for name in ('yolo11n.pt', 'yolo11n.onnx', 'coco_classes.json'):
    manifest['files'][name] = hashlib.sha256((models / name).read_bytes()).hexdigest()
(models / 'manifest.json').write_text(json.dumps(manifest, indent=2) + '\n')
print(json.dumps(manifest, indent=2))

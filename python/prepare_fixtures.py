import json
import os
from pathlib import Path
import cv2

root = Path(__file__).resolve().parents[1]
source = Path(os.environ['DETECTION_WORKSHOP_DIRECTORY']) if 'DETECTION_WORKSHOP_DIRECTORY' in os.environ else next((Path.home() / 'Downloads').glob('Taller*/Sesion4Urbana'))
out = root / 'tmp' / 'detection-fixtures'
out.mkdir(parents=True, exist_ok=True)
images = [cv2.imread(str(source / 'imgs' / 'Calle.JPG'))]
cap = cv2.VideoCapture(str(source / 'Lateral.mp4'))
for index in (30, 90, 150, 210):
    cap.set(cv2.CAP_PROP_POS_FRAMES, index)
    ok, image = cap.read()
    if ok:
        images.append(image)
cap.release()
for i, image in enumerate(images):
    h, w = image.shape[:2]
    image = cv2.resize(image, (640, 2 * round(h * 640 / w / 2)))
    h, w = image.shape[:2]
    path = out / f'{i:03}.rgb'
    path.write_bytes(cv2.cvtColor(image, cv2.COLOR_BGR2RGB).tobytes())
    Path(str(path) + '.json').write_text(json.dumps({'width': w, 'height': h}))
print(out)

# Supplementary workshop scenes and official Ultralytics person fixture.
for index, path in [(10, source/'imgs'/'Calle2.JPG'), (11, source/'imgs'/'Calle3.JPG'), (12, source/'imgs'/'cruce.JPG'), (13, out/'people.jpg')]:
    if not path.exists():
        continue
    image = cv2.imread(str(path))
    h, w = image.shape[:2]
    image = cv2.resize(image, (640, 2 * round(h * 640 / w / 2)))
    h, w = image.shape[:2]
    dest = out / f'{index:03}.rgb'
    dest.write_bytes(cv2.cvtColor(image, cv2.COLOR_BGR2RGB).tobytes())
    Path(str(dest) + '.json').write_text(json.dumps({'width': w, 'height': h}))

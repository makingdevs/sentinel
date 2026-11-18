"""Create bounded 75s H264/H265 fixtures without changing workshop files."""
from pathlib import Path
import subprocess
import os
root = Path(__file__).resolve().parents[1]
source = Path(os.environ['DETECTION_WORKSHOP_DIRECTORY']) if 'DETECTION_WORKSHOP_DIRECTORY' in os.environ else next((Path.home() / 'Downloads').glob('Taller*/Sesion4Urbana'))
out = root / 'tmp' / 'detection-fixtures'
out.mkdir(parents=True, exist_ok=True)
for codec, encoder in [('h264', 'libx264'), ('h265', 'libx265')]:
    dest = out / f'workshop.{codec}'
    if dest.exists():
        continue
    args = ['ffmpeg', '-hide_banner', '-loglevel', 'error', '-y', '-stream_loop', '-1', '-i', str(source / 'Superior.mp4'), '-t', '75', '-an', '-vf', 'scale=640:-2,fps=25', '-c:v', encoder, '-preset', 'ultrafast', '-g', '50', '-bf', '0']
    if codec == 'h265':
        args += ['-x265-params', 'log-level=error:pools=2:frame-threads=2']
    args += ['-f', 'hevc' if codec == 'h265' else 'h264', str(dest)]
    subprocess.run(args, check=True)
    print(dest.name, dest.stat().st_size)

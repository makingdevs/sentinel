"""Aggregate repeated local pipeline measurements; preserves every individual case."""
import csv
import json
from pathlib import Path
from statistics import median
import argparse

p = argparse.ArgumentParser()
p.add_argument('--input', default='tmp/detection-benchmark')
p.add_argument('--output', default='docs/detection-results.md')
a = p.parse_args()
root = Path(__file__).resolve().parents[1]
source = root / a.input
records = [json.loads(path.read_text()) for path in sorted(source.glob('*/result.json'))]
(source/'summary.json').write_text(json.dumps(records, indent=2))
keys = ['engine','streams','repetition','seconds','inference_p50_ms','inference_p95_ms','inference_fps_total','output_fps_per_stream','box_age_p95_ms','process_tree_peak_rss_mb','process_tree_mean_cpu_percent','pipeline_lag_p95_ms','hls_ready','exits']
with (source/'summary.csv').open('w', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=keys, extrasaction='ignore')
    writer.writeheader()
    writer.writerows(records)
lines = ['# Resultados locales de detección', '', 'Equipo: Apple M1 Pro, macOS arm64; CPU, YOLO11n, entrada H264 a 640px/25FPS. Cada caso usa 10s de calentamiento y 60s de medición. Valores agregados: mediana de las repeticiones; RSS es el máximo observado. Python limita PyTorch a dos threads; Ortex usa su configuración automática. No son mediciones con igual presupuesto de threads. El archivo de prueba también se decodifica a640px: cámaras RTSP con resolución principal mayor añaden costo de decodificación que esta matriz no representa.', '', '| Motor | Streams | Repeticiones | Video FPS/stream | Inferencias/s/stream | Inferencia p95 ms | Edad cajas p95 ms | Entrada con cajas % | RSS pico MB | CPU % | HLS listos |', '|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|']
for count in (1,4,8):
    for engine in ('off','python','elixir'):
        rows = [r for r in records if r['streams']==count and r['engine']==engine]
        if not rows:
            continue
        med = lambda key: round(median(r[key] for r in rows if r.get(key) is not None),1) if any(r.get(key) is not None for r in rows) else '—'
        infer_fps = round(median(r['inference_fps_total']/count for r in rows),2)
        coverage = round(median(100*r['boxed_frames']/max(1,r.get('input_frames',r['seconds']*25*count)) for r in rows),1)
        lines.append(f"| {engine} | {count} | {len(rows)} | {med('output_fps_per_stream')} | {infer_fps} | {med('inference_p95_ms')} | {med('box_age_p95_ms')} | {coverage} | {max(r['process_tree_peak_rss_mb'] for r in rows)} | {med('process_tree_mean_cpu_percent')} | {min(r['hls_ready'] for r in rows)}/{count} |")
lines += ['', 'La inferencia y el video tienen ritmos diferentes. La cobertura se mide antes del dibujado sobre input_frames, no sobre frames emitidos ni como exactitud del modelo. Se conservan como máximo 500ms de cajas, por lo que bajo saturación puede haber video sin anotaciones. `pending_replacements` cuantifica fotogramas pendientes reemplazados; no equivale a frames perdidos del video.', '', 'RSS suma el árbol de procesos e incluye memoria nativa. CPU puede superar100%. Los ficheros JSON/CSV individuales quedan en `tmp/detection-benchmark/`; no se deben inferir garantías de producción ni precisión general a partir de estos clips.', '', 'La latencia registrada termina en la salida del encoder: excluye segmentación, HTTP y navegador. No se midió latencia completa de captura a pantalla. La comprobación de exactitud de tres imágenes está separada en `tmp/detection-accuracy.json`; es una muestra de plausibilidad con anotación manual, no un conjunto representativo.', '', f'Casos completados: {len(records)}/27. Errores de pipelines reportados: {sum(r["exits"] for r in records)}.', '']
(root/a.output).write_text('\n'.join(lines))
print(f'{len(records)} cases -> {a.output}')

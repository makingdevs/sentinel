"""Serial, isolated benchmark cases. Includes BEAM and descendant process RSS/CPU."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import time
import psutil

root = Path(__file__).resolve().parents[1]
p = argparse.ArgumentParser()
p.add_argument('--seconds', type=int, default=60)
p.add_argument('--repetitions', type=int, default=3)
p.add_argument('--counts', default='1,4,8')
p.add_argument('--engines', default='off,python,elixir')
p.add_argument('--output', default='tmp/detection-benchmark')
a = p.parse_args()
out = root / a.output
out.mkdir(parents=True, exist_ok=True)
for repeat in range(1, a.repetitions + 1):
    for count in map(int, a.counts.split(',')):
        for engine in a.engines.split(','):
            case = out / f'{repeat}-{count}-{engine}'
            case.mkdir(exist_ok=True)
            if (case / 'result.json').exists():
                existing = json.loads((case / 'result.json').read_text())
                if 'process_tree_peak_rss_mb' in existing and existing['exits'] == 0 and existing['hls_ready'] == count:
                    continue
            with (case / 'run.log').open('w') as log:
                proc = subprocess.Popen(['mix', 'run', '--no-start', 'scripts/detection/benchmark_case.exs', engine, str(count), str(a.seconds), str(repeat), str(case)], cwd=root, stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
                samples = []
                known = {}
                start = time.monotonic()
                try:
                    while proc.poll() is None:
                        rss = cpu = 0
                        try:
                            parent = psutil.Process(proc.pid)
                            for item in [parent] + parent.children(recursive=True):
                                try:
                                    if item.pid not in known:
                                        known[item.pid] = item
                                        item.cpu_percent()
                                    rss += item.memory_info().rss
                                    cpu += known[item.pid].cpu_percent()
                                except (psutil.NoSuchProcess, psutil.AccessDenied):
                                    pass
                        except psutil.NoSuchProcess:
                            pass
                        samples.append({'elapsed_s': round(time.monotonic()-start, 2), 'rss_bytes': rss, 'cpu_percent': cpu})
                        if time.monotonic()-start > a.seconds + 180:
                            raise TimeoutError('benchmark case exceeded bound')
                        time.sleep(1)
                finally:
                    if proc.poll() is None:
                        os.killpg(proc.pid, 15)
                        proc.wait(timeout=15)
                (case / 'resources.json').write_text(json.dumps(samples))
                if proc.returncode:
                    print(f'FAILED {case.name}: exit={proc.returncode}; see run.log', flush=True)
                    raise SystemExit(1)
            result = json.loads((case / 'result.json').read_text())
            result['process_tree_peak_rss_mb'] = round(max((s['rss_bytes'] for s in samples), default=0)/1024**2, 1)
            measured = [s['cpu_percent'] for s in samples if s['elapsed_s'] >= 10]
            result['process_tree_mean_cpu_percent'] = round(sum(measured)/len(measured), 1) if measured else 0
            (case / 'result.json').write_text(json.dumps(result, indent=2))
            print(f"{case.name}: HLS={result['hls_ready']}/{count} infer p95={result['inference_p95_ms']}ms RSS={result['process_tree_peak_rss_mb']}MB", flush=True)
results = [json.loads(path.read_text()) for path in sorted(out.glob('*/result.json'))]
(out / 'summary.json').write_text(json.dumps(results, indent=2))

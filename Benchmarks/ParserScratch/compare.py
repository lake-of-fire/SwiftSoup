#!/usr/bin/env python3
"""Balanced, fresh-process timings. Compile libraries and this client before running.
No significance claim is made here: retain raw blocks for paired analysis.
"""
import argparse
import hashlib
import json
import math
import os
from pathlib import Path
import platform
import subprocess
import time

parser = argparse.ArgumentParser()
parser.add_argument('--client', required=True, type=Path)
parser.add_argument('--base-library', required=True, type=Path)
parser.add_argument('--candidate-library', required=True, type=Path)
parser.add_argument('--out', required=True, type=Path)
parser.add_argument('--blocks', type=int, default=10)
parser.add_argument('--target-ms', type=float, default=700)
parser.add_argument('--aa-blocks', type=int, default=6)
args = parser.parse_args()
if not 2 <= args.blocks <= 40 or not 2 <= args.aa_blocks <= 40 or not 100 <= args.target_ms <= 5000:
    parser.error('Invalid block count or target time')
args.out.mkdir(parents=True, exist_ok=False)
client = args.client.resolve()
libraries = {'base': args.base_library.resolve(), 'candidate': args.candidate_library.resolve()}
for path in [client, *libraries.values()]:
    if not path.is_file():
        parser.error(f'Missing file: {path}')

def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()

def environment(variant):
    env = os.environ.copy()
    variable = 'DYLD_LIBRARY_PATH' if platform.system() == 'Darwin' else 'LD_LIBRARY_PATH'
    env[variable] = str(libraries[variant].parent)
    return env

def invoke(variant, workload, iterations, warmups=3, observations=None):
    command = [str(client), '--workload', workload, '--iterations', str(iterations), '--warmup', str(warmups)]
    if observations is not None:
        command += ['--observations', '--output', str(observations)]
    completed = subprocess.run(command, env=environment(variant), check=True, capture_output=True, text=True, timeout=120)
    if observations is not None:
        return command
    result = json.loads(completed.stdout)
    result['command'] = command
    if result['iterations'] != iterations or result['workload'] != workload:
        raise RuntimeError('Unexpected benchmark output')
    return result

workloads = ['highlight', 'snippets', 'document', 'growth']
metadata = {'platform': platform.platform(), 'machine': platform.machine(),
            'swift': subprocess.check_output(['swift', '--version'], text=True),
            'client_sha256': sha(client), 'libraries': {v: {'path': str(p), 'sha256': sha(p)} for v, p in libraries.items()},
            'started_utc': time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()),
            'blocks': args.blocks, 'aa_blocks': args.aa_blocks, 'target_ms': args.target_ms,
            'workloads': workloads, 'affinity': None}
# Linux pinning is process-local and inherited by the children. macOS uses normal scheduling.
if hasattr(os, 'sched_getaffinity'):
    cpu = min(os.sched_getaffinity(0))
    os.sched_setaffinity(0, {cpu})
    metadata['affinity'] = [cpu]
observations = {}
for workload in workloads:
    results = []
    for variant in libraries:
        output = args.out / f'{variant}-{workload}.json'
        command = invoke(variant, workload, 1, observations=output)
        results.append(output.read_bytes())
        observations[f'{variant}/{workload}'] = {'sha256': sha(output), 'command': command}
    if results[0] != results[1]:
        raise RuntimeError(f'Complete observable output differs: {workload}')
metadata['observations'] = observations
calibration = {}
iterations_by_workload = {}
for workload in workloads:
    probes = [invoke(v, workload, 10) for v in libraries]
    calibration[workload] = probes
    fastest_ms = min(r['elapsed_ms'] / r['iterations'] for r in probes)
    if fastest_ms <= 0:
        raise RuntimeError('Nonpositive timer result')
    iterations_by_workload[workload] = max(2, min(100_000, math.ceil(args.target_ms / fastest_ms)))
metadata['calibration'] = calibration
metadata['iterations'] = iterations_by_workload
(args.out / 'metadata.json').write_text(json.dumps(metadata, indent=2))
with (args.out / 'raw.jsonl').open('w') as output:
    for study, block_count in [('ab', args.blocks), ('aa', args.aa_blocks)]:
        for block in range(block_count):
            names = workloads if block % 2 == 0 else list(reversed(workloads))
            for workload in names:
                order = ['base', 'candidate', 'candidate', 'base'] if block % 2 == 0 else ['candidate', 'base', 'base', 'candidate']
                expected = None
                for position, label in enumerate(order):
                    actual = 'base' if study == 'aa' else label
                    result = invoke(actual, workload, iterations_by_workload[workload])
                    signature = (result['checksum'], result['output_bytes'])
                    if expected is not None and signature != expected:
                        raise RuntimeError(f'Output checksum changed within block {block}: {workload}')
                    expected = signature
                    result.update(study=study, block=block, position=position, variant=label,
                                  actual_variant=actual, timestamp_utc=time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime()))
                    output.write(json.dumps(result, sort_keys=True) + '\n')
                    output.flush()
            print(f'{study}: completed balanced block {block + 1}/{block_count}', flush=True)
(args.out / 'completed.json').write_text(json.dumps({'success': True, 'records': 4 * len(workloads) * (args.blocks + args.aa_blocks)}))

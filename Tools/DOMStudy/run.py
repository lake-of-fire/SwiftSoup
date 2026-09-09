#!/usr/bin/env python3
"""Pinned, non-test release A/B study; synthetic public-API workloads, not iPhone."""
from pathlib import Path
import hashlib, json, math, os, platform, statistics, subprocess, sys
BASE = '8f2b788db171815dd3c69830f9c29dfacc964340'
PARENT = '2d4ef39b87221272a1f563b145c93a83afb003d0'
ROOT = Path(__file__).resolve().parent
OUT = Path(os.environ.get('STUDY_OUTPUT', ROOT / 'output')).resolve()
OUT.mkdir(parents=True, exist_ok=False)
def command(args, **kwargs):
    return subprocess.check_output(args, **kwargs)
def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()
def change(path, before, after):
    text = path.read_text()
    if text.count(before) != 1: raise RuntimeError(f'Expected one occurrence in {path}: {before}')
    path.write_text(text.replace(before, after))
variants = ['baseline', 'previous-stack', 'document-root', 'iterative-owner', 'teardown-leaves']
metadata = {'platform': platform.platform(), 'machine': platform.machine(), 'swift': command(['swiftc','--version'],text=True), 'baseline':BASE, 'previous':PARENT, 'commands':[], 'variants':{}}
for variant in variants:
    directory = OUT / variant
    sources = directory / 'Sources'
    sources.mkdir(parents=True)
    revision = PARENT if variant == 'previous-stack' else BASE
    paths = command(['git','ls-tree','--name-only',revision+':Sources'],text=True).splitlines()
    for name in paths:
        if name.endswith('.swift'):
            (sources / name).write_bytes(command(['git','show',revision+':Sources/'+name]))
    if variant == 'teardown-leaves':
        change(sources/'Node.swift','if isKnownUniquelyReferenced(&node) && !node.childNodes.isEmpty {','if !node.childNodes.isEmpty && isKnownUniquelyReferenced(&node) {')
    if variant == 'iterative-owner':
        change(sources/'Node.swift','        return parentNode?.ownerDocument()','''        var ancestor = parentNode
        while let node = ancestor {
            let nodeType = type(of: node)
            if nodeType == Element.self || nodeType == FormElement.self {
                ancestor = node.parentNode
            } else {
                return node.ownerDocument()
            }
        }
        return nil''')
    if variant == 'document-root':
        text = (sources/'Document.swift').read_text()
        start = text.index('internal func registerDirtySourceRoot(')
        prefix, tail = text[:start], text[start:]
        before = '        var ancestor = node.parentNode'
        if tail.count(before) != 1: raise RuntimeError('Registry insertion point changed')
        tail = tail.replace(before, '''        if sourceRangeDirty,
           dirtySourceRoots[ObjectIdentifier(self)]?.value === self,
           isAncestor(of: node) { return }
''' + before, 1)
        (sources/'Document.swift').write_text(prefix+tail)
    lib = directory / ('libSwiftSoup.dylib' if sys.platform == 'darwin' else 'libSwiftSoup.so')
    build = ['swiftc','-swift-version','6','-O','-whole-module-optimization','-emit-library','-emit-module','-module-name','SwiftSoup',*map(str,sorted(sources.glob('*.swift'))),'-emit-module-path',str(directory/'SwiftSoup.swiftmodule'),'-o',str(lib)]
    cli = ['swiftc','-O','-I',str(directory),'-L',str(directory),'-lSwiftSoup',str(ROOT/'main.swift'),'-Xlinker','-rpath','-Xlinker',str(directory),'-o',str(directory/'study')]
    with (directory/'build.log').open('w') as log:
        for cmd in [build,cli]:
            metadata['commands'].append(cmd)
            subprocess.run(cmd,stdout=log,stderr=subprocess.STDOUT,check=True)
    metadata['variants'][variant] = {'revision':revision,'source_sha256':{p.name:digest(p) for p in sorted(sources.glob('*.swift'))},'library_sha256':digest(lib),'binary_sha256':digest(directory/'study')}
    print('BUILT',variant,flush=True)
(OUT/'metadata.json').write_text(json.dumps(metadata,indent=2))
workloads = ['parse','parse-plain','parse-injected','select','cleanup','injection','copy']
def run(variant, workload, iterations=1, observe=False):
    cmd = [str(OUT/variant/'study'),'--workload',workload,'--iterations',str(iterations),'--count','96']
    if observe: cmd.append('--observe')
    return json.loads(command(cmd,text=True))
for workload in workloads:
    expected = run('baseline',workload,observe=True)
    (OUT/(workload+'-output.json')).write_text(json.dumps(expected,ensure_ascii=False))
    for variant in variants[1:]:
        if run(variant,workload,observe=True) != expected: raise RuntimeError(f'Output mismatch: {variant} {workload}')
print('ALL COMPLETE OUTPUTS MATCH',flush=True)
records = []
with (OUT/'timings.jsonl').open('w') as raw:
    for workload in workloads:
        estimates = [run(v,workload,3)['elapsed_ms']/3 for v in variants]
        iterations = max(1,min(100000,math.ceil(200/min(estimates))))
        for variant in variants[1:]+['AA']:
            for block in range(6):
                for position,label in enumerate(['baseline',variant,variant,'baseline'] if block%2==0 else [variant,'baseline','baseline',variant]):
                    actual = 'baseline' if label=='AA' else label
                    result = run(actual,workload,iterations)
                    result.update(comparison=variant,block=block,position=position,variant=label,actual_variant=actual)
                    raw.write(json.dumps(result)+'\n');raw.flush();records.append(result)
            grouped = [r for r in records if r['comparison']==variant and r['workload']==workload]
            times = {v:[r['elapsed_ms']/r['iterations'] for r in grouped if r['variant']==v] for v in ['baseline',variant]}
            if len({r['checksum'] for r in grouped}) != 1: raise RuntimeError('Checksum mismatch')
            ratios = []
            for block in range(6):
                b = [r for r in grouped if r['block']==block]
                ratios.append(statistics.mean(math.log(r['elapsed_ms']/r['iterations']) for r in b if r['variant']==variant)-statistics.mean(math.log(r['elapsed_ms']/r['iterations']) for r in b if r['variant']=='baseline'))
            m = statistics.mean(ratios);margin = 2.5705818366147395*statistics.stdev(ratios)/math.sqrt(6)
            summary = {'workload':workload,'candidate':variant,'baseline_ms':statistics.geometric_mean(times['baseline']),'candidate_ms':statistics.geometric_mean(times[variant]),'less_time_percent':100*(1-math.exp(m)),'ci95_low':100*(1-math.exp(m+margin)),'ci95_high':100*(1-math.exp(m-margin)),'blocks':6,'runs_per_variant':12}
            with (OUT/'summary.jsonl').open('a') as summary_file: summary_file.write(json.dumps(summary)+'\n')
            print('RESULT',json.dumps(summary),flush=True)
print('COMPLETE',len(records),'fresh process measurements',flush=True)

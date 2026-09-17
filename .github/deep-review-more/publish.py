from pathlib import Path
import json, os, subprocess
root=Path.cwd()
meta=json.loads((root/'.github/deep-review-more/manifest.json').read_text())
base=meta['base_remote']
output=Path(os.environ['RUNNER_TEMP'])/'deep-review-more-evidence'
output.mkdir()
def git(*args,cwd=root):
    return subprocess.check_output(['git',*args],cwd=cwd,text=True).strip()
def call(*args,cwd=root):
    subprocess.run(args,cwd=cwd,check=True)
assert git('rev-parse',base+'^{tree}')==meta['base_tree']
git('config','user.name','Alex Ehlke')
git('config','user.email','alex.ehlke@gmail.com')
receipts=[]
for spec in meta['repairs']:
    branch=spec['branch']
    assert not git('ls-remote','--heads','origin','refs/heads/'+branch), 'Ref already exists: '+branch
    work=Path(os.environ['RUNNER_TEMP'])/spec['slug']
    git('worktree','add','--detach',str(work),base)
    test_file=spec['test_file']
    (work/test_file).write_bytes((root/test_file).read_bytes())
    git('add',test_file,cwd=work)
    assert git('write-tree',cwd=work)==spec['test_tree']
    git('commit','-m','test: reproduce '+spec['slug'],cwd=work)
    test_commit=git('rev-parse','HEAD',cwd=work)
    patch=root/'.github/deep-review-more'/ (spec['slug']+'-fix.patch')
    git('apply','--check',str(patch),cwd=work)
    git('apply',str(patch),cwd=work)
    git('diff','--check',cwd=work)
    git('add',*spec['files'],cwd=work)
    assert git('write-tree',cwd=work)==spec['fixed_tree']
    git('commit','-m','fix: '+spec['title'],cwd=work)
    head=git('rev-parse','HEAD',cwd=work)
    receipts.append({**spec,'test_commit':test_commit,'head':head})
combined=Path(os.environ['RUNNER_TEMP'])/'review-combined'
git('worktree','add','--detach',str(combined),base)
for item in receipts:
    git('cherry-pick',item['test_commit'],item['head'],cwd=combined)
assert git('rev-parse','HEAD^{tree}',cwd=combined)==meta['combined_tree']
with (output/'toolchain.txt').open('w') as f:
    subprocess.run(['swift','--version'],stdout=f,check=True)
with (output/'release.log').open('w') as f:
    subprocess.run(['swift','test','-j','4','-c','release'],cwd=combined,stdout=f,stderr=subprocess.STDOUT,check=True)
assert not git('diff','HEAD',cwd=combined)
call('git','archive','--format=tar.gz','-o',str(output/'combined-source.tar.gz'),'HEAD',cwd=combined)
for item in receipts:
    assert not git('ls-remote','--heads','origin','refs/heads/'+item['branch'])
git('push','--atomic','origin',*[item['head']+':refs/heads/'+item['branch'] for item in receipts])
for item in receipts:
    assert git('ls-remote','--heads','origin','refs/heads/'+item['branch']).split()[0]==item['head']
(output/'publication.json').write_text(json.dumps({'base':base,'combined_tree':meta['combined_tree'],'repairs':receipts},indent=2)+'\n')
print((output/'publication.json').read_text())

#!/usr/bin/env bash
set -euo pipefail
: "${EVIDENCE:?Set external evidence directory}"
mkdir -p "$EVIDENCE"
git config --global --add safe.directory "$GITHUB_WORKSPACE"
git config user.name 'Integration verification'
git config user.email 'verification@example.invalid'
git checkout --detach 555f8678a59baf18aed6abd2ba92b62f1d138bb6
test "$(git rev-parse HEAD^{tree})" = 442d6a057ea719c779dc34fd236fab03aed7d48b
# These are ephemeral local merges, never pushed and never applied to a user ref.
git merge --no-commit --no-ff --no-edit e7e245b02bc69c958ed469c3846f78a6c9fe9f98 053e315b82c204bf93398f70cb6834206c8fc8fc 31de9e42c160f6478cc6b2718094626843f68920 2>&1 | tee "$EVIDENCE/merge.log"
git diff --cached --check
git diff --exit-code
tree=$(git write-tree)
printf '%s\n' "$tree" > "$EVIDENCE/integration-tree.txt"
git ls-tree -r "$tree" > "$EVIDENCE/source.tree"
git diff --cached --binary > "$EVIDENCE/combined.patch"
git archive "$tree" | gzip > "$EVIDENCE/source.tar.gz"
swift --version | tee "$EVIDENCE/toolchain.txt"
swift test -j 4 -c release 2>&1 | tee "$EVIDENCE/release.log"
ASAN_OPTIONS=detect_leaks=0 swift test -j 4 --sanitize address 2>&1 | tee "$EVIDENCE/asan.log"
git diff --exit-code
test "$(git write-tree)" = "$tree"
test -z "$(git ls-files --others --exclude-standard)"
printf 'Verified unchanged integration tree %s\n' "$tree" | tee "$EVIDENCE/final.txt"

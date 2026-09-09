#!/bin/bash
set -euo pipefail
kind=$1
destination=$2
repo=$(git rev-parse --show-toplevel)
payload="$repo/Study/CollectionReads"
base=97e071d6d42794ebbca7716a22605176325c6445
case "$kind" in
 aggregate) tree=0bf4200c5b7c6b79512d701eb7ce77f34dd483b5; testfile=ElementsOutputAggregationTest.swift; stem=aggregate_output; runtime=Elements.swift ;;
 endpoints) tree=f73058258d742bbe3ad578fba8476b34cffc14e2; testfile=SiblingEndpointReadTest.swift; stem=sibling_endpoints; runtime=Element.swift ;;
 *) exit 2 ;;
esac
git config --global --add safe.directory "$destination"
git worktree add --detach "$destination" "$base"
git -C "$destination" apply "$payload/$kind.patch"
mkdir -p "$destination/Tools"
cp "$payload/$testfile" "$destination/Tests/SwiftSoupTests/$testfile"
cp "$payload/benchmark_$stem.swift" "$destination/Tools/benchmark_$stem.swift"
if [ "$kind" = aggregate ]; then
 cp "$payload/compare_aggregate_output.py" "$destination/Tools/compare_$stem.py"
else
 sed "s/^CASES = .*/CASES = ['single','first-8','first-256','first-2048','last-256','last-2048','first-mixed','fallback','parse-endpoints','parse-control']/" "$payload/compare_aggregate_output.py" > "$destination/Tools/compare_$stem.py"
fi
git -C "$destination" add -- "Sources/$runtime" "Tests/SwiftSoupTests/$testfile" "Tools/benchmark_$stem.swift" "Tools/compare_$stem.py"
test "$(git -C "$destination" write-tree)" = "$tree"
git -C "$destination" diff --exit-code
git -C "$destination" diff --cached --check
test -z "$(git -C "$destination" ls-files --others --exclude-standard)"

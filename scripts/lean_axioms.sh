#!/usr/bin/env bash
# Checks that every theorem listed in lean/Axioms.lean depends only on the
# standard axioms (propext, Classical.choice, Quot.sound). Run after
# `lake build` in lean/.
set -euo pipefail
cd "$(dirname "$0")/../lean"
out=$(lake env lean Axioms.lean 2>&1)
want=$(grep -c '^#print axioms' Axioms.lean)
ok=$(grep -cE "depends on axioms: \[propext, Classical.choice, Quot.sound\]$|does not depend on any axioms" <<<"$out" || true)
echo "$out"
if [ "$ok" -ne "$want" ]; then
  echo "FAIL: $ok of $want theorems use only the standard axioms" >&2
  exit 1
fi
echo "OK: $want theorems use only the standard axioms"

#!/bin/bash
# Usage: ./render.sh <outdir> "time weather landmark [view]" ...  , renders test frames without touching the desktop.
out=$1; shift
for spec in "$@"; do
  read -r t w l v <<< "$spec"
  v=${v:-lakeside}
  .build/debug/DhakaSky --snapshot "$out/$v-$t-$w-$l.png" --time "$t" --weather "$w" --landmark "$l" --view "$v" 2>&1 | tail -2
done

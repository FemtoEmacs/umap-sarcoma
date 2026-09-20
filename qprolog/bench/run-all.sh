#!/bin/sh
# run-all.sh [FACTOR] -- time every benchmark program on qprolog; one CSV line per program
# (same format as run-lispy.sh: program,iterations,time,gc,load,warmup,ok).
# Iteration counts: upstream SWI-Prolog counts (swi/programs.pl) times FACTOR.
cd "$(dirname "$0")/.." || exit 2
factor=${1:-1.0}
echo "program,iterations,time,gc,load,warmup,ok"
grep '^program(' bench/programs.pl | sed 's/program(\([a-z_0-9]*\), *\([0-9]*\)).*/\1 \2/' | while read name base; do
  n=$(awk -v b="$base" -v f="$factor" 'BEGIN { n = int(b * f + 0.5); if (n < 1) n = 1; print n }')
  ./bench/run-qprolog.sh "$name" "$n" 2>/dev/null | grep -v '^;'
done

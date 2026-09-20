#!/bin/sh
# vs-swi.sh [FACTOR [REPEATS]] -- run SWI-Prolog and qprolog on the same 15 benchmarks, same
# machine, same method (N x \+ \+ top minus N x \+ \+ dummy), and print the comparison table.
#   ./bench/vs-swi.sh            factor 1.0 (about 1 s per program in SWI), 1 repeat
#   ./bench/vs-swi.sh 0.2 3      fewer iterations, median of 3 repeats
# Needs swipl and sbcl on PATH.  Writes results/swi.N.csv and results/qp.N.csv.
cd "$(dirname "$0")/.." || exit 2
factor=${1:-1.0}; reps=${2:-1}
mkdir -p results
rm -f results/swi.*.csv results/qp.*.csv
i=1
while [ $i -le $reps ]; do
  echo "== run $i/$reps: SWI-Prolog" >&2
  swipl -q -g "run($factor,csv)" -t halt bench/swi/swi-bench.pl 2>/dev/null >results/swi.$i.csv
  echo "== run $i/$reps: qprolog" >&2
  ./bench/run-all.sh "$factor" >results/qp.$i.csv
  i=$((i+1))
done
./bench/compare.sh "$factor" results/swi.*.csv results/qp.*.csv

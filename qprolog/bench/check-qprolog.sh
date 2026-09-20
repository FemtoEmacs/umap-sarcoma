#!/bin/sh
# check-qprolog.sh [NAME...] -- differential test of qprolog against SWI-Prolog's outputs
# (bench/out/check-NAME.swi, produced by bench/check-lispy.sh's SWI half).  Exit status =
# number of programs that differ.
cd "$(dirname "$0")/.." || exit 2
B=${BENCH:-bench}
mkdir -p bench/out
names="$*"
[ -z "$names" ] && names=$(ls bench/check/*.queries | sed 's,.*/,,; s,\.queries$,,')
bad=0
for n in $names; do
  sbcl --noinform --dynamic-space-size 4GB --control-stack-size 512MB --non-interactive \
       --load bench/check-qprolog.lisp \
       --eval "(qp::run-check \"bench/programs/$n.lisp\" \"bench/check/$n.queries\")" \
       </dev/null >bench/out/check-$n.qp 2>bench/out/check-$n.qp.err
  q=$(grep -c '^?- ' bench/out/check-$n.qp)
  if diff -u bench/out/check-$n.swi bench/out/check-$n.qp >bench/out/check-$n.diff; then
    echo "$n: $q queries, identical"
  else
    d=$(grep -c '^@@' bench/out/check-$n.diff)
    echo "$n: $q queries, DIFFERENCES ($d hunks) -- see bench/out/check-$n.diff"
    bad=$((bad+1))
  fi
done
exit $bad

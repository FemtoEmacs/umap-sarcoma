#!/bin/sh
# run-qprolog.sh NAME N   -- one benchmark, one CSV line
cd "$(dirname "$0")/.." || exit 2
exec sbcl --noinform --dynamic-space-size 4GB --control-stack-size 512MB --non-interactive \
     --load bench/run-qprolog.lisp --eval "(qp::run-benchmark \"$1\" $2)" </dev/null

#!/bin/sh
# ./tr.x IN.pl [OUT.lisp]  -- translate a Prolog program to qprolog (Lispy) syntax.
here=$(cd "$(dirname "$0")" && pwd)
exec sbcl --noinform --non-interactive --load "$here/tr.lisp" --end-toplevel-options "$@"

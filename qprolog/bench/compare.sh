#!/bin/sh
# compare.sh FACTOR results1.csv [results2.csv ...]
#
# Joins SWI-Prolog results (run.pl's `program,time,gc` CSV) with lispy-Prolog
# results (run-lispy.sh's `program,iterations,time,gc,load,warmup,ok` CSV) --
# any mix of files, told apart by their header line -- takes the MEDIAN over
# repeated runs, and prints one row per program: time per `top` call in both
# systems and their ratio.  FACTOR is the run(Factor) the SWI runs used
# (iterations = max(1, round(count*Factor)), counts from swi/programs.pl); the
# lispy CSV carries its own iteration counts, so the factors need not match:
# rows are compared per call.  A program whose `top` failed or raised an
# error in the lispy engine is listed as n/a.
cd "$(dirname "$0")/.." || exit 2
factor=$1; shift
files=""; for f in "$@"; do case $f in /*) files="$files $f";; *) files="$files $OLDPWD/$f";; esac; done
awk -v F="$factor" '
function med(key,   n, i, j, t, a) {
  n = cnt[key]; if (n == 0) return ""
  for (i = 1; i <= n; i++) a[i] = vals[key, i]
  for (i = 2; i <= n; i++) { t = a[i]; for (j = i - 1; j >= 1 && a[j] > t; j--) a[j+1] = a[j]; a[j+1] = t }
  return (n % 2) ? a[(n+1)/2] : (a[n/2] + a[n/2+1]) / 2
}
FILENAME ~ /programs\.pl$/ {
  if ($0 ~ /^program\(/) { s = $0; sub(/^program\(/, "", s); split(s, p, /[,)]/); gsub(/ /, "", p[2]); base[p[1]] = p[2]; order[++np] = p[1] }
  next
}
/^program,/ { grp = (split($0, hdr, ",") == 3) ? "swi" : "lispy"; next }
NF == 0 { next }
{
  split($0, f, ","); k = f[1]
  if (grp == "lispy") {
    if (f[3] == "ERROR" || f[7] != "yes") { bad[k] = (f[3] == "ERROR") ? "engine error" : "top fails"; next }
    liter[k] = f[2]; cnt["L" k]++; vals["L" k, cnt["L" k]] = f[3]; cnt["W" k]++; vals["W" k, cnt["W" k]] = f[5] + f[6]
  } else { cnt["S" k]++; vals["S" k, cnt["S" k]] = f[2] }
}
END {
  printf "%-16s %12s %14s %8s %9s %11s\n", "program", "SWI ms/call", "engine ms/call", "ratio", "engine s", "load+warm s"
  printf "%-16s %12s %13s %8s %9s %11s\n", "-------", "-----------", "-------------", "-----", "-------", "-----------"
  ng = 0; lg = 0
  for (i = 1; i <= np; i++) {
    k = order[i]; sn = int(base[k] * F + 0.5); if (sn < 1) sn = 1
    st = med("S" k); if (st == "") continue
    sm = st / sn * 1000
    if (cnt["L" k] > 0) {
      lt = med("L" k); lm = lt / liter[k] * 1000
      printf "%-16s %12.4f %13.4f %7.1fx %9.2f %11.2f\n", k, sm, lm, lm / sm, lt, med("W" k)
      lg += log(lm / sm); ng++
    } else printf "%-16s %12.4f %13s   %s\n", k, sm, "n/a", (k in bad) ? bad[k] : "not run"
  }
  if (ng > 0) printf "%-16s %12s %13s %7.1fx   (geometric mean over %d programs)\n", "geo-mean", "", "", exp(lg / ng), ng
}' bench/programs.pl $files

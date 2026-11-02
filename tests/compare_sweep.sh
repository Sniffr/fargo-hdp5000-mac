#!/bin/zsh
# Re-run every reference job in a sweep directory through the native filter and
# compare byte-for-byte.  usage: compare_sweep.sh <sweepdir> <page.ras> [<duplex.ras>]
DIR=$1; RAS=$2; DUP=${3:-$2}
BIN=~/hdp/lifter/build/rastertohdp5000
export PPD=~/hdp/original/payload/usr/share/cups/model/HDP5000.ppd
export HDP5000_DATADIR=${HDP5000_DATADIR:-~/hdp/original/payload/usr/share/cups/../fargo-data}
pass=0; fail=0
for log in $DIR/*.log; do
  name=${log:t:r}
  opts=$(sed -n "s/^DEBUG: arg 5: '\(.*\)'$/\1/p" $log)
  in=$RAS; [[ $name == duplex ]] && in=$DUP
  $BIN 1 user title 1 "$opts" $in > /tmp/hdp_cmp_$$.prn 2>/dev/null
  if cmp -s /tmp/hdp_cmp_$$.prn $DIR/$name.prn; then pass=$((pass+1)); else fail=$((fail+1)); echo "DIFF: $name ($opts)"; fi
done
rm -f /tmp/hdp_cmp_$$.prn
echo "$pass identical, $fail different"

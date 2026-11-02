#!/bin/sh
# print disassembly of named functions from the annotated listing, compactly
for f in "$@"; do
  awk -v f="$f" '$0 ~ "^[0-9a-f]+ <"f">:" {p=1} p && /^$/ {p=0; print ""} p' ~/hdp/analysis/filter_annot.asm \
   | sed -E 's/^ +//; s/:[[:space:]]+/: /; s/\t/ /g; s/ <___dso_handle\+0x[0-9a-f]+>//; s/ +## imm = .*//'
done

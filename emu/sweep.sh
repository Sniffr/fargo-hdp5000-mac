#!/bin/zsh
# usage: sweep.sh <outdir> <input.ppm[,page2.ppm]>
# Runs the original filter once per option set (ColorMatching=None) and keeps .prn + log.
cd ~/hdp/emu
OUT=$1; IN=$2; mkdir -p $OUT
run() { name=$1; shift; ../.venv/bin/python run_original.py ${PAGES:-$IN} $OUT/$name.prn ColorMatching=None "$@" > $OUT/$name.log 2>&1; }
run default &
run ribbon_YMC Ribbon=YMC &
run ribbon_YMCKK Ribbon=YMCKK &
run ribbon_YMCKH Ribbon=YMCKH &
run ribbon_Premium Ribbon=PremiumResin &
run film_holo Film=Holo &
PAGES=$IN,$IN run duplex PrintBothSides=True &
run split SplitRibbon=True &
wait
run disable DisablePrinting=True &
run dyesub_m20 DyeSubIntensity=-20 &
run dyesub_p4 DyeSubIntensity=4 &
run resinfront_m10 ResinHeatFront=-10 &
run xferheat_160 TransferHeat=160 &
run xferdwell_30 TransferDwell=30 &
run hoff_m50 HOffset=-50 &
run voff_m50 VOffset=-50 &
wait
run hoff_p20 HOffset=20 &
run voff_p20 VOffset=20 &
run kfull kpanelareafront=fullcard &
run konly KPanelOnlyFront=True &
run cr79 PageSize=CR79 &
run dither_photo ResinDither=photo &
run coerc_low Coercivity=Low &
run overlayheat_5 OverlayHeat=5 &
wait

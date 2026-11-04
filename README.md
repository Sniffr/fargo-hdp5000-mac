# Fargo HDP5000 driver for Apple-silicon Macs

A native (arm64 + x86_64) CUPS driver for the HID Fargo HDP5000, rebuilt from
HID's 2012 Mac driver, which only ran on 32-bit Intel Macs (OS X 10.4/10.5).

**Install:** download [Fargo-HDP5000-2.0.0.pkg](https://github.com/Sniffr/fargo-hdp5000-mac/releases/latest/download/Fargo-HDP5000-2.0.0.pkg)
from the [latest release](https://github.com/Sniffr/fargo-hdp5000-mac/releases/latest)
(also in the repo at `driver/Fargo-HDP5000-2.0.0.pkg`).

## How it was made

HID's filter (`rastertofargoHDP5000`, i386) was **statically recompiled** into C
(`lifter/lift.py` → `lifter/gen/`), then linked with a small native runtime
(`lifter/rt.c`) that stands in for the old libc/libcups/libstdc++ calls. So the
colour management, thermal-head compensation, ribbon handling, mag-stripe
encoding and the printer protocol are all HID's own logic, running natively.

Verification: the original binary runs in an x86 emulator (`emu/run_original.py`).
The new driver's output was compared **byte-for-byte** with it on 59 jobs:
every ribbon type, both films, duplex, split ribbon, K-panel modes, offsets,
intensities, transfer heat/dwell, lamination, magnetic encoding, ICC on/off,
noise and photo/text images. All 59 matched exactly. It has also been tested
on a real HDP5000, where it prints correctly.

## Installing

1. Double-click `driver/Fargo-HDP5000-2.0.0.pkg` (needs an admin password).
2. Connect the printer by USB (or Ethernet) and switch it on.
3. **System Settings → Printers & Scanners → Add Printer**. Pick the HDP5000
   and, under *Use*, choose **Select Software… → Fargo HDP5000 (native, Apple silicon + Intel)**.

   Command line alternative (find the device URI with `lpinfo -v`):

   ```bash
   lpadmin -p HDP5000 -E -v "usb://…" -m "Fargo HDP5000.ppd.gz"
   ```

## Using it

* Card size is CR80, portrait (159 × 248 pt). Landscape designs rotate automatically.
* Options appear in the print dialog (Ribbon, Film, Print Both Sides, K-panel area, heat/intensity, offsets, lamination, …).
* For crisp black text and barcodes on a YMCK ribbon, set **Front K-Panel Area → Full Card**
  *and* **Color Matching → None**. With colour matching on, HID's filter never sends the
  black resin panel and prints black as a Y+M+C mix.
* Design cards at the full page size (159 × 248 pt, or 248 × 159 landscape), not the exact
  card size: the extra ~1 mm per edge is bleed. A design at exact card size prints unscaled
  in one corner and leaves a white strip along an edge.
* For designing and printing ID cards, use **HDP5000 ID Studio** (below), which handles
  all of this for you.
* Maintenance (sends HID's own command and test files raw):

  ```bash
  /Library/Printers/Fargo/HDP5000/hdp5000-util HDP5000 clean
  ```

  The other commands are `ribbon-cal`, `film-cal`, `lam-cal`, `test-ymck`,
  `test-ymc`, `test-ymckk`, `test-ymckh` and `test-k`.
* Troubleshooting: run `cupsctl --debug-logging`, print, then look at
  `/var/log/cups/error_log` (the filter logs every setting it uses).

## HDP5000 ID Studio (card designer)

A Mac app for designing and printing ID cards on the HDP5000, edge to edge.
Download [HDP5000-ID-Studio-1.0.zip](https://github.com/Sniffr/fargo-hdp5000-mac/releases/latest/download/HDP5000-ID-Studio-1.0.zip),
unzip it and drag **HDP5000 ID Studio** into Applications. It needs the driver above.
The app is not signed by Apple: the first time, right-click it and choose **Open**
(or **System Settings → Privacy & Security → Open Anyway**).

* **Design cards:** front and back, text, logo, photo, Code 128 barcode, QR code and
  shapes, starting from an employee ID template.
* **Print a ready-made design:** *File → Print a Ready-Made Design…* takes a PNG, JPG,
  HEIC or PDF (pick two files for front and back). Choose **Fill to edge**, **Fit on card**
  (nothing cut off) or **Stretch**, then fine-tune size and position.
* **Batches:** load a CSV and type `{{Column}}` in any text, barcode or QR; a photo box can
  take each person's photo file from a column. Print all rows or a selection.
* **No white edges:** everything is printed to the full bleed page. If a strip of white still
  shows on one edge, use *Printer → Print Alignment Card*: the card has a frame 2 mm in from
  every edge, and the arrows (or *Fine-tune by measuring*) move the print. On the unit this
  was tested on, one horizontal step is ~0.2 mm and one vertical step ~0.085 mm.
* Pure-black text and barcodes go to the black resin panel so they scan reliably.

Build from source: `app/build_app.sh` (Swift command line tools are enough; no Xcode needed).

## Rebuilding

```bash
cd lifter && ../.venv/bin/python lift.py ../original/payload/usr/lib/cups/filter/rastertofargoHDP5000 gen
make -j ARCH="-arch arm64 -arch x86_64"
```

Then re-run `tests/compare_sweep.sh` to confirm the output still matches, and re-run
the `pkgbuild` step (see NOTES.md).

## Licensing note

This is an unofficial community project with no link to or endorsement from
HID Global. The package contains HID's code (recompiled from HID's freely
downloadable 2012 Mac driver) and HID's colour profiles, which remain HID's
property. It is shared so owners of the HDP5000 can keep using their printers
on current Macs. Use it at your own risk. If you represent HID and want
something removed, please open an issue.

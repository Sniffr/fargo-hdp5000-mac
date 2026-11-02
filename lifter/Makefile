# Native (arm64) build of the recompiled HID HDP5000 CUPS filter.
CC      ?= clang
ARCH    ?= -arch arm64
CFLAGS  ?= -O1 -fno-strict-aliasing -fwrapv -w $(ARCH)
GEN     := $(wildcard gen/lifted_*.c) gen/image_data.c
OBJ     := $(patsubst gen/%.c,build/%.o,$(GEN)) build/rt.o

build/rastertohdp5000: $(OBJ)
	$(CC) $(ARCH) -o $@ $(OBJ) -lcups

build/%.o: gen/%.c rt.h gen/lifted.h | build
	$(CC) $(CFLAGS) -Igen -I. -c $< -o $@

build/rt.o: rt.c rt.h | build
	$(CC) -O2 -Wall -Wno-deprecated-declarations $(ARCH) -c $< -o $@

build:
	mkdir -p build

clean:
	rm -rf build

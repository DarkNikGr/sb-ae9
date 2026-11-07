# sb-ae9 build wrapper: one make drives both module builds so that flags the
# caller appends to the command line (DKMS's -j, and the LLVM=1 it appends on
# clang-built kernels) reach every sub-make instead of only the last one.
KDIR ?= /lib/modules/$(shell uname -r)/build

# Forward the toolchain choice verbatim; empty means "let Kbuild pick gcc".
ifneq ($(LLVM),)
llvm := LLVM=$(LLVM)
endif

.PHONY: all clean hda-core ca0132

all: hda-core ca0132

hda-core ca0132:
	$(MAKE) -C $@ KDIR=$(KDIR) $(llvm)

clean:
	$(MAKE) -C hda-core KDIR=$(KDIR) $(llvm) clean
	$(MAKE) -C ca0132 KDIR=$(KDIR) $(llvm) clean

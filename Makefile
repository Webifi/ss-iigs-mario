# The build of the game disk image: run "make" (build.sh checks the tools,
# then runs it). The stages:
#
# 1. The width check of the 65816 sources (scripts/width_lint.py), and the
#    asset build (scripts/assets.py, Python): the art, the sound and the
#    data from the ROM files, as generated sources of both programs. It runs
#    only when its inputs change (build/assets.stamp).
# 2. The Second Sight program (Z180, GNU binutils): src/secondsight/*.s and
#    the generated sources, linked with src/secondsight/secondsight.ld.
# 3. The IIgs program and its data (65816, cc65): src/game.s and
#    build/game/host_data.s, linked with src/iigs.cfg.
# 4. The boot loader and the boot block (cc65): src/boot.cfg and
#    bootloader/boot0.cfg.
# 5. The disk step (scripts/disk.py, Python): the card load records, the boot
#    volume (mario-HASH.hdv and mario-HASH-scsi.hda in build/game-disk, HASH a
#    short hash of the game data) and its debug symbols.
#
# The memory maps are hand-written; fitters put the asset data into their
# free space:
# - The Second Sight link runs twice. The first link parks the asset sections
#   and gives the free space of secondsight.ld; the fitter
#   (scripts/secondsight_fit.py) places them for the final link.
# - A link of src/iigs.cfg alone gives its areas (build/game/areas/areas.lbl);
#   the asset build puts each blob of host data into a segment with room
#   (scripts/iigs_payload.py).

# Only the rules of this file: no built-in rules of make.
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

PYTHON ?= $(if $(wildcard .venv/bin/python),.venv/bin/python,python3)
Z80 ?= z80-elf-
CA65 ?= ca65
LD65 ?= ld65

# The build folders.
SECONDSIGHT := build/secondsight
GAME := build/game
BOOT := build/game-disk
DISK := $(BOOT)/debug.sym      # the last file of the disk step: the image names hold a hash
ASSETS := build/assets.stamp
LINT := build/lint.stamp

.PHONY: all assets disk secondsight iigs boot lint
.DELETE_ON_ERROR:

# Two passes: the width check and the asset build first, then the rest with
# the files that the asset build wrote (a new pass reads their times again).
all:
	+$(MAKE) --no-print-directory lint assets
	+$(MAKE) --no-print-directory disk

assets: $(ASSETS)
disk: $(DISK)
lint: $(LINT)

# ---- 1. The asset build ----

SECONDSIGHT_GEN := $(SECONDSIGHT)/gen
# The scripts that the asset build does not run: the width check, the fitter
# and the disk step.
OTHER_SCRIPTS := scripts/width_lint.py scripts/secondsight_fit.py scripts/disk.py scripts/boot_disk.py \
	scripts/debug_symbols.py
# The ROM files may have spaces in their names ("Super Mario Bros. (World).zip"):
# make takes a space as a separator unless a backslash comes before it.
ROM_FILES := $(shell ls roms/*.zip roms/*.nes 2>/dev/null | sed 's/ /\\ /g')
ASSET_INPUTS := $(filter-out $(OTHER_SCRIPTS),$(wildcard scripts/*.py)) $(ROM_FILES)

# 65816 immediates whose width differs from the register width
# (scripts/width_lint.py): the build stops on one.
$(LINT): scripts/width_lint.py $(wildcard src/*.s)
	@found="$$($(PYTHON) scripts/width_lint.py src)"; test "$$found" = "none found" || \
		{ echo "65816 immediate width mismatch:"; echo "$$found"; exit 1; }
	@mkdir -p $(@D)
	touch $@

# The places of src/iigs.cfg, from a link of the config alone. The probe has
# no code, so ld65 warns that the code segments do not exist; any other
# message is shown, and a failed link leaves no label file.
$(GAME)/areas/areas.lbl: src/iigs.cfg
	mkdir -p $(@D)
	rm -f $@
	: > $(@D)/areas.s
	$(CA65) -o $(@D)/areas.o $(@D)/areas.s
	cd $(@D) && $(LD65) -C $(CURDIR)/src/iigs.cfg -Ln areas.lbl -o areas.bin areas.o 2>&1 | grep -v "does not exist" || true
	test -s $@

# The asset build writes build/secondsight/gen (the generated sources and
# sources.mk) and build/game (host_data.s,
# host_data.bin, host_data.inc and the generated includes); a file that does
# not change keeps its time.
$(ASSETS): $(ASSET_INPUTS) $(GAME)/areas/areas.lbl
	$(PYTHON) scripts/assets.py
	touch $@

# ---- 2. The Second Sight program (Z180, GNU binutils) ----

SECONDSIGHT_MAP := src/secondsight/secondsight.ld
-include $(SECONDSIGHT_GEN)/sources.mk
SECONDSIGHT_OBJECTS := $(patsubst src/secondsight/%.s,$(SECONDSIGHT)/%.o,$(wildcard src/secondsight/*.s)) \
	$(patsubst %,$(SECONDSIGHT)/gen_%.o,$(GENERATED))
SECONDSIGHT_INPUTS := $(SECONDSIGHT_OBJECTS) $(SECONDSIGHT_MAP)
ASFLAGS := -march=z180 --fatal-warnings -I src/secondsight/include -I src
LDFLAGS := --no-check-sections --no-warn-rwx-segments --orphan-handling=error
LDPATHS := -L src/secondsight
FIT := $(PYTHON) scripts/secondsight_fit.py
FIT_TOOL := scripts/secondsight_fit.py scripts/elf32.py

secondsight: $(SECONDSIGHT)/secondsight.elf

$(SECONDSIGHT)/%.o: src/secondsight/%.s
	@mkdir -p $(@D)
	$(Z80)as $(ASFLAGS) --MD $(@:.o=.d) -o $@ $<

$(SECONDSIGHT)/gen_%.o: $(SECONDSIGHT_GEN)/%.s
	$(Z80)as $(ASFLAGS) --MD $(@:.o=.d) -o $@ $<

# The first link: the fitter parks the asset sections.
$(SECONDSIGHT)/fitting/placements.ld: $(SECONDSIGHT_OBJECTS) $(FIT_TOOL)
	mkdir -p $(@D)
	$(FIT) park $@ $(SECONDSIGHT_OBJECTS)

$(SECONDSIGHT)/fitting/secondsight.elf: $(SECONDSIGHT_INPUTS) $(SECONDSIGHT)/fitting/placements.ld
	$(Z80)ld $(LDFLAGS) -L $(SECONDSIGHT)/fitting $(LDPATHS) -T $(SECONDSIGHT_MAP) -o $@ $(SECONDSIGHT_OBJECTS)

# The final link: the fitter places the asset sections into the free space
# of the first link.
$(SECONDSIGHT)/placements.ld: $(SECONDSIGHT)/fitting/secondsight.elf $(FIT_TOOL)
	$(FIT) place $@ $< $(SECONDSIGHT_OBJECTS)

$(SECONDSIGHT)/secondsight.elf: $(SECONDSIGHT_INPUTS) $(SECONDSIGHT)/placements.ld
	$(Z80)ld $(LDFLAGS) -L $(SECONDSIGHT) $(LDPATHS) -T $(SECONDSIGHT_MAP) -Map $(SECONDSIGHT)/secondsight.map \
		-o $@ $(SECONDSIGHT_OBJECTS)

# A missing dependency file builds nothing: its object is then out of date.
$(SECONDSIGHT)/%.d: ;
-include $(SECONDSIGHT_OBJECTS:.o=.d)

# The Second Sight symbols for the IIgs sources: secondsight_NAME = value.
$(GAME)/secondsight_symbols.inc: $(SECONDSIGHT)/secondsight.elf
	mkdir -p $(@D)
	$(Z80)nm -g --defined-only $< | awk '$$3 ~ /^[A-Za-z_][A-Za-z0-9_]*$$/ { printf "secondsight_%s = $$%s\n", $$3, toupper($$1) }' > $@

# ---- 3. The IIgs program (65816, cc65) ----

CA65FLAGS := -g -I $(GAME) -I src

iigs: $(GAME)/host.lbl

# A missing dependency file (.d) builds its object again once; the object is
# then newer than its dependency file.
$(GAME)/host.o: src/game.s $(GAME)/host.d $(GAME)/secondsight_symbols.inc
	$(CA65) $(CA65FLAGS) --create-dep $(GAME)/host.d -o $@ $<
	touch $@

$(GAME)/host_data.o: $(GAME)/host_data.s $(GAME)/host_data.d $(GAME)/host_data.inc $(GAME)/host_data.bin \
		$(GAME)/secondsight_symbols.inc
	$(CA65) $(CA65FLAGS) --bin-include-dir $(GAME) --create-dep $(GAME)/host_data.d -o $@ $<
	touch $@

# ld65 writes the files of src/iigs.cfg into the build folder.
$(GAME)/host.lbl: $(GAME)/host.o $(GAME)/host_data.o src/iigs.cfg
	cd $(GAME) && $(LD65) -C $(CURDIR)/src/iigs.cfg -Ln host.lbl --dbgfile host.dbg -o host.bin host.o host_data.o

$(GAME)/host.d $(GAME)/host_data.d: ;
-include $(GAME)/host.d $(GAME)/host_data.d

# ---- 4. The boot loader and the boot block (65816, cc65) ----

boot: $(BOOT)/boot.bin $(BOOT)/boot0.bin

# The places of the IIgs program that the boot loader uses.
$(BOOT)/boot_settings.inc: $(GAME)/host.lbl
	mkdir -p $(@D)
	awk 'BEGIN { split("settings INPUT_SETTINGS input_save_driver INPUT_SAVE_DRIVER input_save_unit INPUT_SAVE_UNIT " \
		"input_save_block INPUT_SAVE_BLOCK input_save_sp_entry INPUT_SAVE_SP_ENTRY " \
		"input_save_sp_unit INPUT_SAVE_SP_UNIT game_handoff GAME_HANDOFF", m); \
		for (i = 1; i in m; i += 2) name["." m[i]] = m[i + 1] } \
		$$3 in name && !seen[$$3]++ { printf "%s = $$%s\n", name[$$3], $$2 }' $< > $@

$(BOOT)/boot.o: src/boot.s $(BOOT)/boot.d $(BOOT)/boot_settings.inc
	$(CA65) -g -I $(BOOT) -I bootloader -I src --create-dep $(BOOT)/boot.d -o $@ $<
	touch $@

$(BOOT)/boot.bin: $(BOOT)/boot.o src/boot.cfg
	$(LD65) -C src/boot.cfg -Ln $(BOOT)/boot.lbl --dbgfile $(BOOT)/boot.dbg -o $@ $<

$(BOOT)/boot.d: ;
-include $(BOOT)/boot.d

$(BOOT)/boot0.bin: bootloader/boot0.s bootloader/boot0.cfg
	mkdir -p $(@D)
	$(CA65) -o $(BOOT)/boot0.o $<
	$(LD65) -C bootloader/boot0.cfg -o $@ $(BOOT)/boot0.o

# ---- 5. The disk step ----

$(DISK): $(GAME)/host.lbl $(SECONDSIGHT)/secondsight.elf $(BOOT)/boot.bin $(BOOT)/boot0.bin \
		scripts/disk.py scripts/boot_disk.py scripts/debug_symbols.py scripts/startup_pack.py \
		scripts/elf32.py scripts/roms.py scripts/iigs_payload.py bootloader/prodos_volume.py
	$(PYTHON) scripts/disk.py

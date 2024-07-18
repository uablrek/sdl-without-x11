# Build libgbm from "src/gbm" in Mesa.
#
#   make -f $PWD/libgbm.makefile -C $__mesa_dir/src/gbm

O ?= /tmp/libgbm
SRC := main/gbm_abi_check.c main/gbm.c main/backend.c backends/dri/gbm_dri.c
OBJ := $(SRC:%.c=$(O)/%.o)

$(O)/%.o : %.c
	$(CC) -c $(CFLAGS) $< -o $@

.PHONY: all
all: dirs $(OBJ)
	@echo $(OBJ)


.PHONY: dirs
dirs:
	@mkdir -p $(O)/main $(O)/backends/dri

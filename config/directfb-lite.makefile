##
## Makefile for directfb-lite
##
## Targets;
##  help - This printout
##  all (default) - Build the lib's
##  install DESTDIR=
##  clean - Remove built files
##
## Beside the usual CC, CFLAGS and LDFLAGS some usable variables;
##  S - The directfb source dir.
##      Default $GOPATH/src/github.com/deniskropp/DirectFB
##  O - The output directory. Default /tmp/$USER/directfb-lite
##  TARGET - Target for cross-compile
##
## Examples;
##  make clean
##  make -j$(nproc)

# Use one Makefile
# https://www.google.se/search?q=recursive+make+harmful

CC := $(TARGET)cc
STRIP := $(TARGET)strip


PROG=directfb-lite
O ?= /tmp/$(USER)/$(PROG)
X ?= $(O)/bin/$(PROG)
LIB ?= $(O)/lib/lib$(PROG).a
DESTDIR ?= $(O)/sys

DIRS := $(O)/lib $(O)/obj
SRC := $(filter-out $(wildcard cmd/*test.c),$(wildcard cmd/*.c))
LIB_SRC := $(filter-out $(wildcard lib/*test.c),$(wildcard lib/*.c))
TEST_SRC := $(wildcard cmd/*test.c lib/*test.c)
OBJ := $(SRC:cmd/%.c=$(O)/obj/%.o)
LIB_OBJ := $(LIB_SRC:%.c=$(O)/%.o)
TEST_PROGS := $(TEST_SRC:%.c=$(O)/test/%)

$(O)/%.o : %.c
	$(CC) -c $(XCFLAGS) $(CFLAGS) -DVERSION=$(VERSION) -Wall -Werror -Ilib $< -o $@
$(O)/obj/%.o : cmd/%.c
	$(CC) -c $(XCFLAGS) $(CFLAGS) -DVERSION=$(VERSION) -Wall -Werror -Ilib $< -o $@

.PHONY: all static
all: $(X)
static: $(X)

# https://stackoverflow.com/questions/47905554/segmentation-fault-appears-when-i-use-shared-memory-only-from-statically-build-p
static: XLDFLAGS := -static -Wl,--whole-archive -lpthread -Wl,--no-whole-archive
static: XCFLAGS := -static

$(X): $(LIB) $(OBJ)
	$(CC) -o $(X) $(OBJ) $(XLDFLAGS) $(LDFLAGS) -pthread -L$(O)/lib  -l$(PROG)
	$(STRIP) $(X)

# https://stackoverflow.com/questions/4440500/depending-on-directories-in-make
$(OBJ): | $(DIRS)
$(LIB): $(LIB_OBJ)
	@rm -f $(LIB)
	ar rcs $(LIB) $(LIB_OBJ)
$(LIB_OBJ): | $(DIRS)

$(DIRS):
	@mkdir -p $(DIRS)

.PHONY: clean
clean:
	rm -f $(X) $(LIB) $(OBJ) $(LIB_OBJ)

.PHONY: help
help:
	@grep '^##' $(lastword $(MAKEFILE_LIST)) | cut -c3-

#
# Makefile for building the NIF
#
# Makefile targets:
#
# all    build and install the NIF
# clean  clean build products and intermediates
#
# Variables to override:
#
# MIX_APP_PATH  path to the build directory
#
# CC            The C compiler
# CROSSCOMPILE  crosscompiler prefix, if any
# CFLAGS        compiler flags for compiling all C files
# LDFLAGS       linker flags for linking all binaries
#

SRC = c_src/duckdb_nif.c
HEADERS = $(wildcard c_src/duckdb/src/*.h) $(wildcard c_src/duckdb/src/*.hpp) c_src/utf8.h c_src/duckdb/tools/sqlite3_api_wrapper/include/sqlite3.h

ERTS_INCLUDE_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~ts/erts-~ts/include/\", [code:root_dir(), erlang:system_info(version)]).")
ERL_INTERFACE_INCLUDE_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, include)]).")
ERL_INTERFACE_LIB_DIR ?= $(shell erl -noshell -s init stop -eval "io:format(\"~ts\", [code:lib_dir(erl_interface, lib)]).")

LDLIBS += -L $(ERL_INTERFACE_LIB_DIR) -lei

CFLAGS ?= -O2 -Wall -I $(ERL_INTERFACE_INCLUDE_DIR)
ifneq ($(DEBUG),)
	CFLAGS += -g
endif
CFLAGS += -I"$(ERTS_INCLUDE_DIR)"
CFLAGS += -Ic_src -Ic_src/duckdb/src -Ic_src/duckdb/sqlite3_api_wrapper/

KERNEL_NAME := $(shell uname -s)

PREFIX = $(MIX_APP_PATH)/priv
BUILD  = $(MIX_APP_PATH)/obj
LIB_NAME = $(PREFIX)/duckdb_nif.so
ARCHIVE_NAME = $(PREFIX)/duckdb_nif.a

OBJ = $(SRC:c_src/%.c=$(BUILD)/%.o)

ifeq ($(KERNEL_NAME), Linux)
	CFLAGS += -fPIC -fvisibility=hidden
	LDFLAGS += -fPIC -shared -lc_src/duckdb/build/release/src/libduckdb_static.a -lc_src/duckdb/build/release/tools/sqlite3_api_wrapper/libsqlite3_api_wrapper_static.a
endif
ifeq ($(KERNEL_NAME), Darwin)
	CFLAGS += -fPIC
	LDFLAGS += -shared -flat_namespace -undefined suppress -L c_src/duckdb/build/release/src/ -llibduckdb_static -L./c_src/duckdb/build/release/tools/sqlite3_api_wrapper/ -llibsqlite3_api_wrapper
endif
ifeq (MINGW, $(findstring MINGW,$(KERNEL_NAME)))
	CFLAGS += -fPIC
	LDFLAGS += -fPIC -shared
	LIB_NAME = $(PREFIX)/duckdb_nif.dll
endif
ifeq ($(KERNEL_NAME), $(filter $(KERNEL_NAME),OpenBSD FreeBSD NetBSD))
	CFLAGS += -fPIC
	LDFLAGS += -fPIC -shared
endif

# ########################
# COMPILE TIME DEFINITIONS
# ########################

# For more information about these features being enabled, check out
# --> https://sqlite.org/compile.html
CFLAGS += -DSQLITE_THREADSAFE=1
CFLAGS += -DSQLITE_USE_URI=1
CFLAGS += -DSQLITE_LIKE_DOESNT_MATCH_BLOBS=1
CFLAGS += -DSQLITE_DQS=0

# TODO: The following features should be completely configurable by the person
#       installing the nif. Just need to have certain environment variables
#       enabled to support them.
CFLAGS += -DALLOW_COVERING_INDEX_SCAN=1
CFLAGS += -DENABLE_FTS3_PARENTHESIS=1
CFLAGS += -DENABLE_SOUNDEX=1
CFLAGS += -DENABLE_STAT4=1
CFLAGS += -DENABLE_UPDATE_DELETE_LIMIT=1
CFLAGS += -DSQLITE_ENABLE_FTS3=1
CFLAGS += -DSQLITE_ENABLE_FTS4=1
CFLAGS += -DSQLITE_ENABLE_FTS5=1
CFLAGS += -DSQLITE_ENABLE_GEOPOLY=1
CFLAGS += -DSQLITE_ENABLE_JSON1=1
CFLAGS += -DSQLITE_ENABLE_MATH_FUNCTIONS=1
CFLAGS += -DSQLITE_ENABLE_RBU=1
CFLAGS += -DSQLITE_ENABLE_RTREE=1
CFLAGS += -DSQLITE_OMIT_DEPRECATED=1
ifneq ($(STATIC_ERLANG_NIF),)
	CFLAGS += -DSTATIC_ERLANG_NIF=1
endif

# TODO: We should allow the person building to be able to specify this
CFLAGS += -DNDEBUG=1

ifeq ($(STATIC_ERLANG_NIF),)
all: duckdb $(PREFIX) $(BUILD) $(LIB_NAME)
else
all: duckdb $(PREFIX) $(BUILD) $(ARCHIVE_NAME)
endif

$(BUILD)/%.o: c_src/%.c
	$(CC) -c $(ERL_CFLAGS) $(CFLAGS) -o $@ $< $(LDFLAGS) $(LDLIBS) 

$(LIB_NAME): $(OBJ)
	$(CC) -o $@ $(LDFLAGS) $(LDLIBS) $^

$(ARCHIVE_NAME): $(OBJ)
	$(AR) -rv $@ $^

$(PREFIX) $(BUILD):
	mkdir -p $@

duckdb:
	make -C c_src/duckdb/

clean:
	$(RM) $(LIB_NAME) $(ARCHIVE_NAME) $(OBJ)
	make -C c_src/duckdb/ clean

.PHONY: all clean

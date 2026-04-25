#!/usr/bin/env sh
set -e

SRC="libtess2-master/Source"
INC="libtess2-master/Include"
BIN="bin"
OUT="../$BIN/libtess2.a"

mkdir -p "$BIN"

echo "Building libtess2..."

git submodule update --init

./patch_libtess2.sh

cc -O2 -DTESS_USE_DOUBLE -I"$INC" -c \
    "$SRC/tess.c"        \
    "$SRC/mesh.c"        \
    "$SRC/sweep.c"       \
    "$SRC/geom.c"        \
    "$SRC/dict.c"        \
    "$SRC/priorityq.c"   \
    "$SRC/bucketalloc.c"

ar rcs "$OUT" tess.o mesh.o sweep.o geom.o dict.o priorityq.o bucketalloc.o

rm -f ./*.o
echo "Done. Output: $OUT"
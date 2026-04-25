#!/usr/bin/env sh
set -e

HEADER="libtess2-master/Include/tesselator.h"

if grep -q "TESS_USE_DOUBLE" "$HEADER"; then
    echo "Patch already applied, skipping."
    exit 0
fi

if ! grep -q "typedef float TESSreal;" "$HEADER"; then
    echo "Target string not found in $HEADER, skipping."
    exit 0
fi

# Use a temp file for portability (sed -i behaves differently on macOS vs Linux)
TMP=$(mktemp)
sed 's/typedef float TESSreal;/#ifdef TESS_USE_DOUBLE\n  typedef double TESSreal;\n#else\n  typedef float TESSreal;\n#endif/' "$HEADER" > "$TMP"
mv "$TMP" "$HEADER"

echo "Patched $HEADER successfully."
# Odin Bindings for libtess2

Odin bindings for [libtess2](https://github.com/memononen/libtess2/tree/master), a port of the GLU tessellator: a scanline tessellator useful for polygon boolean operations and offsetting.

## Setup

Clone this repository into your Odin project, then run the included build script from the `source/` directory:

```sh
cd source
./build_libtess2.sh      # macOS / Linux
build_libtess2.bat       # Windows (Developer Command Prompt)
```

This will pull in the libtess2 source, patch it to enable double precision, and compile it to `bin/`.

## Polygon Operations

The following operations are provided in `polygon.odin`:

| Function | Description |
|---|---|
| `offset_polygon` | Offsets all edges of a polygon by a uniform delta |
| `offset_polygon_edges` | Offsets each edge of a polygon by an individual delta |
| `union_polygons` | Boolean union |
| `difference_polygons` | Boolean difference |
| `intersect_polygons` | Boolean intersection |
| `xor_polygons` | Boolean symmetric difference |

## Notes & Limitations

- Offsets are currently mitered with no miter limit
- The polygon operations are naive, primitive implementations and do not leverage libtess2's full performance potential
- For best performance, use the bindings in `bindings.odin` directly and reuse the same tesselator across multiple operations

## Roadmap

- Constraints on miters and arc resolution
- Selectable join types: round, bevel, miter
- Collapsed edge detection
- Open polygon offsetting
- Open polygon booleans
- Boolean trees

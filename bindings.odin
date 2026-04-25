/*
    https://github.com/memononen/libtess2

    Compiled with TESS_USE_DOUBLE.

    The master branch of LibTess2 has a bug where TESS_USE_DOUBLE
    is not actually wired up. Before building, apply this fix in
    Include/tesselator.h
    
    replace:
        typedef float TESSreal;
    With:
        #ifdef TESS_USE_DOUBLE
            typedef double TESSreal;
        #else
            typedef float TESSreal;
        #endif

    Then build the static library from the libtess2 source directory:
        cc -O2 -DTESS_USE_DOUBLE -IInclude \
            Source/tess.c \
            Source/mesh.c \
            Source/sweep.c \
            Source/geom.c \
            Source/dict.c \
            Source/priorityq.c \
            Source/bucketalloc.c \
            -c
        ar rcs libtess2.a *.o
    
    Or just use the included build scripts: build_libtess2.bat | build_libtess2.sh
*/

package libtess2

when ODIN_OS == .Windows {
    foreign import lib "bin/libtess2.lib"
} else when ODIN_OS == .Darwin {
    foreign import lib "bin/libtess2.a"
} else {
    foreign import lib "bin/libtess2.a"
}

// UNDEF is the sentinel index value for missing or boundary indices.
UNDEF :: i32(~u32(0))

// Opaque tesselator handle.
Tesselator :: struct {}

// Winding rules
// See: http://www.glprogramming.com/red/chapter11.html
Winding_Rule :: enum i32 {
    Odd         = 0,
    Nonzero     = 1,
    Positive    = 2,
    Negative    = 3,
    Abs_Geq_Two = 4,
}

Element_Type :: enum i32 {
    Polygons           = 0,
    Connected_Polygons = 1,
    Boundary_Contours  = 2,
}

@(default_calling_convention = "c", link_prefix = "tess")
foreign lib {
    // Create a new tesselator using the default malloc allocator.
    NewTess :: proc(alloc: rawptr) -> ^Tesselator ---

    // Destroy a tesselator and free all associated memory.
    DeleteTess :: proc(tess: ^Tesselator) ---

    // Set a tesselator option.
    // option 0 = constrained Delaunay triangulation (value 1 to enable).
    SetOption :: proc(tess: ^Tesselator, option: i32, value: i32) ---

    // Add a contour to be tessellated.
    AddContour :: proc(tess: ^Tesselator, size: i32, pointer: rawptr, stride: i32, count: i32) ---

    // Tessellate all added contours.
    // If you pass 'nil' for normal, libtess2 will automatically compute it (recommended).
    // Returns 1 on success, 0 on failure.
    Tesselate :: proc(tess: ^Tesselator, winding_rule: Winding_Rule, element_type: Element_Type, poly_size: i32, vertex_size: i32, normal: ^f64) -> i32 ---

    GetVertexCount   :: proc(tess: ^Tesselator) -> i32 ---
    GetElementCount  :: proc(tess: ^Tesselator) -> i32 ---
    GetVertices      :: proc(tess: ^Tesselator) -> [^]f64 ---

    // Maps output vertices back to original input vertex indices.
    // Vertices generated at intersections are marked UNDEF.
    // Length = GetVertexCount().
    GetVertexIndices :: proc(tess: ^Tesselator) -> [^]i32 ---

    // Element index array. Layout depends on element_type. See Element_Type.
    GetElements      :: proc(tess: ^Tesselator) -> [^]i32 ---
}

// tesselate_triangles takes one or more contours and returns a flat list of triangles
tesselate_triangles :: proc(contours: [][]([2]f64), winding: Winding_Rule = .Odd, allocator := context.allocator) -> [][3][2]f64 {
    if len(contours) == 0 do return nil

    tess := NewTess(nil)
    if tess == nil do return nil
    defer DeleteTess(tess)

    for c in contours {
        if len(c) == 0 do continue
        AddContour(tess, 2, raw_data(c), size_of([2]f64), i32(len(c)))
    }

    if Tesselate(tess, winding, .Polygons, 3, 2, nil) == 0 do return nil

    vert_count := GetVertexCount(tess)
    elem_count := GetElementCount(tess)
    if elem_count == 0 do return nil

    verts    := ([^][2]f64)(GetVertices(tess))[:vert_count]
    elements := ([^][3]i32)(GetElements(tess))[:elem_count]

    result := make([][3][2]f64, elem_count, allocator)
    for tri, i in elements {
        for j in 0..<3 {
            idx := tri[j]
            if idx == UNDEF do continue
            result[i][j] = verts[idx]
        }
    }
    return result
}

// contours takes one or more contours, classifies regions by winding rule,
// and returns the boundary contours of the result.
tesselate_contours :: proc(input: [][]([2]f64), winding: Winding_Rule = .Positive, allocator := context.allocator) -> [][][2]f64 {
    if len(input) == 0 do return nil

    tess := NewTess(nil)
    if tess == nil do return nil
    defer DeleteTess(tess)

    for c in input {
        if len(c) == 0 do continue
        AddContour(tess, 2, raw_data(c), size_of([2]f64), i32(len(c)))
    }

    if Tesselate(tess, winding, .Boundary_Contours, 1, 2, nil) == 0 do return nil

    elem_count := GetElementCount(tess)
    if elem_count == 0 do return nil

    vert_count := GetVertexCount(tess)
    verts      := ([^][2]f64)(GetVertices(tess))[:vert_count]
    elems      := GetElements(tess)

    result := make([][][2]f64, elem_count, allocator)
    for i in 0..<int(elem_count) {
        base  := int(elems[i * 2])
        count := int(elems[i * 2 + 1])
        c := make([][2]f64, count, allocator)
        copy(c, verts[base : base + count])
        result[i] = c
    }
    return result
}

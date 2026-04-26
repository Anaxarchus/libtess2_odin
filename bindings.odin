package libtess2

import "core:fmt"

when ODIN_OS == .Windows {
    foreign import lib "bin/libtess2.lib"
} else {
    foreign import lib "bin/libtess2.a"
}

UNDEF :: i32(~u32(0))

Tesselator :: struct{}

TesselatorContext :: struct(vertex_size: int) {
    handle: ^Tesselator,
    normal: [3]f64,
}

Connected_Polygon :: struct(N: int) {
    verts:     [4][N]f64,
    neighbors: [4]i32,
}

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

Status :: enum i32 {
    Ok            = 0,
    Out_Of_Memory = 1,
    Invalid_Input = 2,
}

@(default_calling_convention = "c", link_prefix = "tess")
foreign lib {
    NewTess          :: proc(alloc: rawptr) -> ^Tesselator ---
    DeleteTess       :: proc(tess: ^Tesselator) ---
    SetOption        :: proc(tess: ^Tesselator, option: i32, value: i32) ---
    AddContour       :: proc(tess: ^Tesselator, size: i32, pointer: rawptr, stride: i32, count: i32) ---
    Tesselate        :: proc(tess: ^Tesselator, winding_rule: Winding_Rule, element_type: Element_Type, poly_size: i32, vertex_size: i32, normal: ^f64) -> i32 ---
    GetVertexCount   :: proc(tess: ^Tesselator) -> i32 ---
    GetElementCount  :: proc(tess: ^Tesselator) -> i32 ---
    GetVertices      :: proc(tess: ^Tesselator) -> [^]f64 ---
    GetVertexIndices :: proc(tess: ^Tesselator) -> [^]i32 ---
    GetElements      :: proc(tess: ^Tesselator) -> [^]i32 ---
    GetStatus        :: proc(tess: ^Tesselator) -> Status ---
}

make_boundary_contour_results :: proc(tess: TesselatorContext($N), allocator := context.allocator) -> [][][N]f64 {
    elem_count := GetElementCount(tess.handle)
    if elem_count == 0 do return nil

    vert_count := GetVertexCount(tess.handle)
    verts      := ([^][N]f64)(GetVertices(tess.handle))[:vert_count]
    elems      := GetElements(tess.handle)

    result := make([][][N]f64, elem_count, allocator)
    for i in 0..<int(elem_count) {
        base  := int(elems[i * 2])
        count := int(elems[i * 2 + 1])
        c     := make([][N]f64, count, allocator)
        copy(c, verts[base : base + count])
        result[i] = c
    }
    return result
}

// polygon_size must be passed as a compile-time constant so it can
// be used as an array size in the element cast.
make_polygon_results :: proc(tess: TesselatorContext($N), $polygon_size: int, allocator := context.allocator) -> [][polygon_size][N]f64 {
    vert_count := GetVertexCount(tess.handle)
    elem_count := GetElementCount(tess.handle)
    if elem_count == 0 do return nil

    verts    := ([^][N]f64)(GetVertices(tess.handle))[:vert_count]
    elements := ([^][polygon_size]i32)(GetElements(tess.handle))[:elem_count]

    result := make([][polygon_size][N]f64, elem_count, allocator)
    for poly, i in elements {
        for j in 0..<polygon_size {
            idx          := poly[j]
            result[i][j]  = verts[idx if idx != UNDEF else poly[0]]
        }
    }
    return result
}

make_connected_polygon_results :: proc(tess: TesselatorContext($N), $poly_size: int, allocator := context.allocator) -> []Connected_Polygon(N) {
    vert_count := GetVertexCount(tess.handle)
    elem_count := GetElementCount(tess.handle)
    if elem_count == 0 do return nil

    verts  := ([^][N]f64)(GetVertices(tess.handle))[:vert_count]
    elems  := GetElements(tess.handle)
    stride := poly_size * 2

    result := make([]Connected_Polygon(N), elem_count, allocator)
    for i in 0..<int(elem_count) {
        base := i * stride
        for j in 0..<poly_size {
            idx                    := elems[base + j]
            result[i].verts[j]     = verts[idx if idx != UNDEF else elems[base]]
            result[i].neighbors[j] = elems[base + poly_size + j]
        }
    }
    return result
}

begin :: #force_inline proc($vertex_size: int, use_delaunay: bool = false, normal: [3]f64 = {0, 0, 0}) -> (tess: TesselatorContext(vertex_size), ok: bool) {
    handle := NewTess(nil)
    if handle == nil do return {}, false
    SetOption(handle, 0, i32(use_delaunay))
    return {handle, normal}, true
}

add :: #force_inline proc(tess: TesselatorContext($N), contour: [][N]f64) -> bool {
    if tess.handle == nil {
        fmt.println("ERROR: Tesselator handle is nil")
        return false
    }
    AddContour(tess.handle, i32(N), raw_data(contour), size_of([N]f64), i32(len(contour)))
    status := GetStatus(tess.handle)
    if status != .Ok {
        fmt.println("ERROR: AddContour failed:", status)
        return false
    }
    return true
}

tesselate_polygons :: #force_inline proc(tess: ^TesselatorContext($N), winding: Winding_Rule, $polygon_size: int, allocator := context.allocator) -> [][polygon_size][N]f64 {
    if Tesselate(tess.handle, winding, .Polygons, i32(polygon_size), i32(N), &tess.normal[0]) == 0 {
        fmt.println("ERROR: Tesselate failed:", GetStatus(tess.handle))
        return nil
    }
    return make_polygon_results(tess^, polygon_size, allocator)
}

tesselate_connected_polygons :: #force_inline proc(tess: ^TesselatorContext($N), winding: Winding_Rule, $poly_size: int, allocator := context.allocator) -> []Connected_Polygon(N) {
    if Tesselate(tess.handle, winding, .Connected_Polygons, i32(poly_size), i32(N), &tess.normal[0]) == 0 {
        fmt.println("ERROR: Tesselate failed:", GetStatus(tess.handle))
        return nil
    }
    return make_connected_polygon_results(tess^, poly_size, allocator)
}

tesselate_boundary_contours :: #force_inline proc(tess: ^TesselatorContext($N), winding: Winding_Rule, allocator := context.allocator) -> [][][N]f64 {
    if Tesselate(tess.handle, winding, .Boundary_Contours, 1, i32(N), &tess.normal[0]) == 0 {
        fmt.println("ERROR: Tesselate failed:", GetStatus(tess.handle))
        return nil
    }
    return make_boundary_contour_results(tess^, allocator)
}

end :: #force_inline proc(tess: TesselatorContext($N)) {
    DeleteTess(tess.handle)
}

delete_contours :: proc(contours: [][][$N]f64, allocator := context.allocator) {
    for c in contours do delete(c, allocator)
    delete(contours, allocator)
}
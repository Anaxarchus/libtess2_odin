package libtess2

// based on the algorithm outlined in this paper: https://mcmains.me.berkeley.edu/pubs/DAC05OffsetPolygon.pdf

import "core:slice"
import "core:math/linalg"

@(private)
_line_intersect :: proc(a0, a1, b0, b1: [2]f64, eps := 1e-10) -> (hit: bool, point: [2]f64) {
    ad    := a1 - a0
    bd    := b1 - b0
    denom := ad.x*bd.y - ad.y*bd.x
    if abs(denom) < eps do return false, {}
    diff  := b0 - a0
    t     := (diff.x*bd.y - diff.y*bd.x) / denom
    return true, a0 + ad * t
}

@(private)
_make_offset_curve :: proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][2]f64 {
    C       := len(polygon)
    dC      := len(deltas) - 1
    centers := make([][2]f64, C, allocator)

    // pass 1: translate each edge midpoint along its normal * delta
    for i in 0..<C {
        j         := (i + 1) % C
        dir       := linalg.normalize0(polygon[j] - polygon[i])
        n         := linalg.orthogonal(dir)
        centers[i] = (polygon[i] + polygon[j]) * 0.5 - n * deltas[min(i, dC)]
    }

    // pass 2: intersect adjacent offset centers to find corner vertices
    for i in 0..<C {
        j  := (i + 1) % C
        k  := (i + 2) % C
        dI := linalg.normalize0(polygon[j] - polygon[i])
        dJ := linalg.normalize0(polygon[k] - polygon[j])
        hit, x := _line_intersect(centers[i], centers[i] + dI, centers[j], centers[j] + dJ)
        if hit do centers[j] = x
    }

    return centers
}

@(private)
_boolean :: proc(polygons: [][][2]f64, rule: Winding_Rule, allocator := context.allocator) -> [][][2]f64 {
    if len(polygons) == 0 do return {}
    raw    := tesselate_contours(polygons, rule, allocator)
    result := make([][][2]f64, len(raw), allocator)
    for i in 0..<len(raw) do result[i] = raw[i]
    delete(raw)
    return result
}

@(private)
_free_result :: proc(r: [][][2]f64) {
    for c in r do delete(c)
    delete(r)
}

// offset_polygon offsets all edges of a polygon by a uniform delta.
// Negative delta shrinks, positive delta expands.
// Returns cleaned contours via winding number classification.
offset_polygon :: #force_inline proc(polygon: [][2]f64, delta: f64, allocator := context.allocator) -> [][][2]f64 {
    return offset_polygon_edges(polygon, {delta}, allocator)
}

// offset_polygon_edges offsets each edge of a polygon by its own delta.
// If len(deltas) < len(polygon), the last delta is reused for remaining edges.
// Negative delta shrinks, positive delta expands.
// Returns cleaned contours via winding number classification.
offset_polygon_edges ::#force_inline proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][][2]f64 {
    if len(polygon) < 3 do return {}
    curve := _make_offset_curve(polygon, deltas)
    defer delete(curve)
    return _boolean({curve}, .Positive, allocator)
}

offset :: proc {offset_polygon, offset_polygon_edges}

// union_polygons returns the union of all input polygons.
// All polygons should be CCW wound.
union_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    return _boolean(polygons, .Nonzero, allocator)
}

// intersect_polygons returns the intersection of all input polygons.
// All polygons should be CCW wound.
// Returns only regions covered by two or more input polygons.
intersect_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    return _boolean(polygons, .Abs_Geq_Two, allocator)
}

// xor_polygons returns the symmetric difference of all input polygons.
// All polygons should be CCW wound.
// Returns regions covered by an odd number of input polygons.
xor_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    return _boolean(polygons, .Odd, allocator)
}

// difference_polygons subtracts all subsequent polygons from the first.
// polygons[0] is the subject (CCW). polygons[1:] are the cutters and will
// be reversed internally. Returns polygons[0] minus the union of polygons[1:].
difference_polygons :: proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    if len(polygons) == 0 do return {}
    if len(polygons) == 1 {
        result    := make([][][2]f64, 1, allocator)
        result[0]  = make([][2]f64, len(polygons[0]), allocator)
        copy(result[0], polygons[0])
        return result
    }

    // pass 1: get the intersection of all cutters with the subject
    intersection := _boolean(polygons, .Abs_Geq_Two)
    defer _free_result(intersection)

    // pass 2: reverse the intersection and use it to cut the subject
    for c in intersection do slice.reverse(c)

    input := make([][]([2]f64), 1 + len(intersection))
    defer delete(input)
    input[0] = polygons[0]
    for i in 0..<len(intersection) do input[i+1] = intersection[i]

    return _boolean(input, .Nonzero, allocator)
}

// triangulate_polygons triangulates a set of polygons into a flat list of
// resolved triangles as [3][2]f64.
triangulate_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][3][2]f64 {
    if len(polygons) == 0 do return {}
    return tesselate_triangles(polygons, .Odd, allocator)
}

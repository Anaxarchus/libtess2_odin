package libtess2

// based on the algorithm outlined in this paper: https://mcmains.me.berkeley.edu/pubs/DAC05OffsetPolygon.pdf

import "core:slice"
import "core:math/linalg"
import "core:fmt"


Join_Type :: enum {
    Miter,
    Bevel,
    Round,
}

@(private)
_signed_area :: proc(pts: [][2]f64) -> f64 {
    area: f64
    n := len(pts)
    for i in 0..<n {
        j := (i + 1) % n
        area += pts[i].x * pts[j].y
        area -= pts[j].x * pts[i].y
    }
    return area * 0.5
}


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
_make_raw_offset_curve :: proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][2]f64 {
    C  := len(polygon)
    dC := len(deltas) - 1

    // up to 3 points per vertex: end of incoming edge, original vertex, start of outgoing edge
    buf   := make([][2]f64, C * 3, allocator)
    count := 0

    for i in 0..<C {
        h := (i - 1 + C) % C
        j := (i + 1) % C

        // incoming edge: h -> i
        n_in  := linalg.orthogonal(linalg.normalize0(polygon[i] - polygon[h]))
        // outgoing edge: i -> j
        n_out := linalg.orthogonal(linalg.normalize0(polygon[j] - polygon[i]))

        delta_in  := deltas[min(h, dC)]
        delta_out := deltas[min(i, dC)]

        // end of incoming offset edge (arrives at vertex i)
        p_end   := polygon[i] - n_in  * delta_in
        // start of outgoing offset edge (leaves vertex i)
        p_start := polygon[i] - n_out * delta_out

        is_concave := _is_concave(polygon[i], polygon[h], polygon[j])
        inner      := deltas[min(i, dC)] < 0

        needs_v := (!is_concave && inner) || (is_concave && !inner)

        if needs_v {
            // march: end of incoming → original vertex → start of outgoing
            buf[count] = p_end;        count += 1
            buf[count] = polygon[i];   count += 1
            buf[count] = p_start;      count += 1
        } else {
            // miter: intersect the two offset edge lines
            hit, x := _line_intersect(
                polygon[h] - n_in  * delta_in,  p_end,
                p_start,                          polygon[j] - n_out * delta_out,
            )
            if hit {
                buf[count] = x; count += 1
            } else {
                buf[count] = p_end;   count += 1
                buf[count] = p_start; count += 1
            }
        }
    }

    return buf[:count]
}

@(private)
_boolean :: proc(polygons: [][][2]f64, rule: Winding_Rule, allocator := context.allocator) -> [][][2]f64 {
    if len(polygons) == 0 do return {}
    return tesselate_contours(polygons, rule, allocator)
}

@(private)
_free_result :: proc(r: [][][2]f64) {
    for c in r do delete(c)
    delete(r)
}

@(private)
_is_concave :: #force_inline proc(p, prev, next: [2]f64) -> bool {
    return linalg.cross(p - prev, next - p) < 0
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
offset_polygon_edges :: proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][][2]f64 {
    if len(polygon) < 3 do return {}

    cleaned := tesselate_contours({polygon}, .Positive, context.temp_allocator)
    if len(cleaned) == 0 do return {}

    raw := make([][]([2]f64), len(cleaned), context.temp_allocator)
    for i in 0..<len(cleaned) {
        raw[i] = _make_raw_offset_curve(cleaned[i], deltas, context.temp_allocator)
    }

    return _boolean(raw, .Positive, allocator)
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

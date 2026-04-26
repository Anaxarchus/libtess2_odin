package libtess2

// based on the algorithm outlined in this paper: https://mcmains.me.berkeley.edu/pubs/DAC05OffsetPolygon.pdf

import "core:slice"
import "core:math"
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
_is_concave :: #force_inline proc(p, prev, next: [2]f64) -> bool {
    return linalg.cross(p - prev, next - p) > 0
}

// returns true if the offset polygon has fully inverted
@(private)
_is_fully_inverted :: proc(polygon: [][2]f64, raw: [][2]f64) -> bool {
    return math.sign(_signed_area(polygon)) != math.sign(_signed_area(raw))
}

make_raw_offset_curve :: proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][2]f64 {
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

        // V through original vertex when:
        //   concave + inner offset: creates invalid loop with negative winding → tessellator discards
        //   convex  + outer offset: creates invalid loop with negative winding → tessellator discards
        needs_v := (is_concave && inner) || (!is_concave && !inner)

        if needs_v {
            // V: end of incoming → original vertex → start of outgoing
            buf[count] = p_end;      count += 1
            buf[count] = polygon[i]; count += 1
            buf[count] = p_start;    count += 1
        } else {
            // miter: intersect the two offset edge lines
            hit, x := _line_intersect(
                polygon[h] - n_in  * delta_in, p_end,
                p_start,                        polygon[j] - n_out * delta_out,
            )
            if hit {
                buf[count] = x; count += 1
            } else {
                buf[count] = p_end;   count += 1
                buf[count] = p_start; count += 1
            }
        }
    }

    if _is_fully_inverted(polygon, buf[:count]) do return {}

    return buf[:count]
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

    // step 1: clean the input polygon
    ctx, okay := begin(2, false)
        okay = add(ctx, polygon)
        cleaned := tesselate_boundary_contours(&ctx, .Positive, allocator)
        defer delete_contours(cleaned)
    end(ctx)

    // step 2: make the raw offset curve
    raw := make([][]([2]f64), len(cleaned))
    defer delete_contours(raw)
    for i in 0..<len(cleaned) {
        raw[i] = make_raw_offset_curve(cleaned[i], deltas)
    }

    ctx, okay = begin(2, false)
    for i in 0..<len(raw) {
        okay = add(ctx, raw[i])
    }
        result := tesselate_boundary_contours(&ctx, .Positive, allocator)
    end(ctx)

    return result
}

offset :: proc {offset_polygon, offset_polygon_edges}

// union_polygons returns the union of all input polygons.
// All polygons should be CCW wound.
union_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    ctx, ok := begin(2, false)
        for i in 0..<len(polygons) do add(ctx, polygons[i])
        result := tesselate_boundary_contours(&ctx, .Nonzero, allocator)
    end(ctx)
    return result
}

// intersect_polygons returns the intersection of all input polygons.
// All polygons should be CCW wound.
// Returns only regions covered by two or more input polygons.
intersect_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    ctx, ok := begin(2, false)
        for i in 0..<len(polygons) do add(ctx, polygons[i])
        result := tesselate_boundary_contours(&ctx, .Abs_Geq_Two, allocator)
    end(ctx)
    return result
}

// xor_polygons returns the symmetric difference of all input polygons.
// All polygons should be CCW wound.
// Returns regions covered by an odd number of input polygons.
xor_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {
    ctx, ok := begin(2, false)
        for i in 0..<len(polygons) do add(ctx, polygons[i])
        result := tesselate_boundary_contours(&ctx, .Odd, allocator)
    end(ctx)
    return result
}

// difference_polygons subtracts all subsequent polygons from the first.
// polygons[0] is the subject (CCW). polygons[1:] are the cutters and will
// be reversed internally. Returns polygons[0] minus the union of polygons[1:].
difference_polygons :: proc(polygons: [][][2]f64, allocator := context.allocator) -> [][][2]f64 {

    if len(polygons) < 2 do return {}

    // pass 1: get the intersection of all cutters with the subject
    ctx, ok := begin(2, false)
        for i in 0..<len(polygons) do add(ctx, polygons[i])
        intersection := tesselate_boundary_contours(&ctx, .Abs_Geq_Two)
        defer delete(intersection)
    end(ctx)

    // pass 2: reverse the intersection and use it to cut the subject
    for c in intersection do slice.reverse(c)
    ctx, ok = begin(2, false)
        add(ctx, polygons[0])
        for i in 0..<len(intersection) do add(ctx, intersection[i])
        result := tesselate_boundary_contours(&ctx, .Nonzero, allocator)
    end(ctx)

    return result
}

// triangulate_polygons triangulates a set of polygons into a flat list of
// resolved triangles as [3][2]f64.
triangulate_polygons :: #force_inline proc(polygons: [][][2]f64, allocator := context.allocator) -> [][3][2]f64 {
    if len(polygons) == 0 do return {}

    ctx, ok := begin(2, false)
        for i in 0..<len(polygons) do add(ctx, polygons[i])
        result := tesselate_polygons(&ctx, .Odd, 3, allocator)
    end(ctx)

    return result
}

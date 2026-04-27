package libtess2

// based on the algorithm outlined in this paper: https://mcmains.me.berkeley.edu/pubs/DAC05OffsetPolygon.pdf

import "core:slice"
import "core:math"
import "core:math/linalg"


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

@(private)
_arc_sample_count :: #force_inline proc(radius, total_angle, chord_deviation: f64) -> int {
    if radius < 1e-10 do return 0
    half_step := math.acos(clamp(1.0 - chord_deviation / radius, -1.0, 1.0))
    max_step  := 2.0 * half_step
    return max(int(math.ceil(math.abs(total_angle) / max_step)), 1)
}

make_raw_offset_curve :: proc(polygon: [][2]f64, deltas: []f64, join_type: Join_Type, arc_resolution, miter_limit: f64, allocator := context.allocator) -> [][2]f64 {
    C  := len(polygon)
    dC := len(deltas) - 1
    
    // we're going to use a pessimistic strategy for allocation, and naively allocate for worst case.
    buf: [][2]f64
    switch join_type {
    case .Miter, .Bevel:
        buf = make([][2]f64, C * 3, allocator)
    case .Round:
        // pessimistic: assume every vertex is a half-circle at the largest delta
        max_delta := deltas[0]
        for d in deltas do max_delta = max(max_delta, math.abs(d))
        max_arc_segs := _arc_sample_count(max_delta, math.PI, arc_resolution)
        buf = make([][2]f64, C * (max_arc_segs + 2), allocator)
    }
    defer delete(buf)

    // up to 3 points per vertex: end of incoming edge, original vertex, start of outgoing edge
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
            switch join_type {
            case .Miter:
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
            case .Bevel:

                dt: f64
                if abs(delta_in) < abs(delta_out) {
                    dt = delta_in
                } else {
                    dt = delta_out
                }

                angle_in  := math.atan2(n_in.y,  n_in.x)
                angle_out := math.atan2(n_out.y, n_out.x)
                origin: [2]f64 = polygon[i]
                radius: f64 = dt

                if abs(delta_in - delta_out) > 1e-9 {
                    edge_in  := linalg.normalize0(polygon[i] - polygon[h])
                    edge_out := linalg.normalize0(polygon[j] - polygon[i])
                    hit, x   := _line_intersect(p_end, p_end + edge_in, p_start, p_start + edge_out)
                    if hit do origin = x + n_in * radius + n_out * radius
                    p_end   = origin - [2]f64{math.cos(angle_in),  math.sin(angle_in)}  * radius
                    p_start = origin - [2]f64{math.cos(angle_out), math.sin(angle_out)} * radius
                }

                // --- commit points ---
                buf[count] = p_end; count += 1
                buf[count] = p_start; count += 1

            case .Round:

                dt: f64
                if abs(delta_in) < abs(delta_out) {
                    dt = delta_in
                } else {
                    dt = delta_out
                }

                angle_in  := math.atan2(n_in.y,  n_in.x)
                angle_out := math.atan2(n_out.y, n_out.x)
                origin: [2]f64 = polygon[i]
                radius: f64 = dt

                if abs(delta_in - delta_out) > 1e-9 {
                    edge_in  := linalg.normalize0(polygon[i] - polygon[h])
                    edge_out := linalg.normalize0(polygon[j] - polygon[i])
                    hit, x   := _line_intersect(p_end, p_end + edge_in, p_start, p_start + edge_out)
                    if hit do origin = x + n_in * radius + n_out * radius
                    p_end   = origin - [2]f64{math.cos(angle_in),  math.sin(angle_in)}  * radius
                    p_start = origin - [2]f64{math.cos(angle_out), math.sin(angle_out)} * radius
                }

                diff      := math.mod(angle_out - angle_in + math.TAU, math.TAU)
                if diff > math.PI do diff -= math.TAU

                steps := _arc_sample_count(abs(radius), math.abs(diff), arc_resolution)

                // --- commit points ---

                buf[count] = p_end; count += 1

                for k in 1..<steps {
                    a := angle_in + f64(k) * diff / f64(steps)
                    buf[count] = origin - [2]f64{math.cos(a), math.sin(a)} * radius
                    count += 1
                }

                buf[count] = p_start; count += 1
            }
        }
    }

    result := make([][2]f64, count)
    copy(result, buf[:count])

    return result
}

offset_polygon_edges :: proc(polygon: [][2]f64, deltas: []f64, join_type: Join_Type, arc_resolution: f64, miter_limit: f64, allocator := context.allocator) -> [][][2]f64 {
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
        raw[i] = make_raw_offset_curve(cleaned[i], deltas, join_type, arc_resolution, miter_limit, allocator)
    }

    // fix: large offsets cause the tesselator to sum incorrectly
    // switching from .Positive to .Negative when cw_area is greater than ccw_area seems to resolve this.
    cw_area: f64
    ccw_area: f64
    for i in 0..<len(raw) {
        sa := _signed_area(raw[i])
        if sa < 0 {
            cw_area += abs(sa)
        } else {
            ccw_area += sa
        }
    }

    ctx, okay = begin(2, false)
    for i in 0..<len(raw) {
        okay = add(ctx, raw[i])
    }
        wr: Winding_Rule = .Positive
        if cw_area > ccw_area do wr = .Negative
        result := tesselate_boundary_contours(&ctx, wr, allocator)
    end(ctx)

    return result
}

offset_polygon_miter :: #force_inline proc(polygon: [][2]f64, deltas: []f64, miter_limit: f64, allocator := context.allocator) -> [][][2]f64 {
    return offset_polygon_edges(polygon, deltas, .Miter, 0.0, miter_limit, allocator)
}

offset_polygon_round :: #force_inline proc(polygon: [][2]f64, deltas: []f64, arc_resolution: f64, allocator := context.allocator) -> [][][2]f64 {
    return offset_polygon_edges(polygon, deltas, .Round, arc_resolution, 0.0, allocator)
}

offset_polygon_bevel :: #force_inline proc(polygon: [][2]f64, deltas: []f64, allocator := context.allocator) -> [][][2]f64 {
    return offset_polygon_edges(polygon, deltas, .Bevel, 0.0, 0.0, allocator)
}

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

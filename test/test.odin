#+private
package test

import "core:math/linalg"
import "core:testing"
import "core:log"
import ".."

_make_shape_r :: #force_inline proc() -> [4][2]f64 {
    return {
        {0, 0},
        {100, 0},
        {100, 100},
        {0, 100},
    }
}

_make_shape_d :: #force_inline proc() -> [5][2]f64 {
    return {
        {0, 0},
        {100, 0},
        {100, 75},
        {75, 100},
        {0, 100},
    }
}

_make_shape_l :: #force_inline proc() -> [6][2]f64 {
    return {
        {0, 0},
        {100, 0},
        {100, 20},
        {40, 20},
        {40, 100},
        {0, 100},
    }
}

_eq_approx :: #force_inline proc(a,b: [$N]$T) -> bool {
    #unroll for i in 0..<N {
        if abs(a.x - b.x) > 1e-9 || abs(a.y - b.y) > 1e-9 do return false
    }
    return true
}

_zero_approx :: #force_inline proc(a,b: [$N]$T) -> bool {
    #unroll for i in 0..<N {
        if abs(a.x) > 1e-9 || abs(a.y) > 1e-9 do return false
    }
    return true
}

_is_ccw :: proc(pts: [][2]f64) -> bool {
    area: f64
    n := len(pts)
    for i in 0..<n {
        j := (i + 1) % n
        area += pts[i].x * pts[j].y
        area -= pts[j].x * pts[i].y
    }
    return area * 0.5 > 1e-9
}

@(test)
test_all :: proc(t: ^testing.T) {
    test_l_collapse(t)
}


// offset the L shape so that one of the legs collapses.
test_l_collapse :: proc(t: ^testing.T) {
    log.info("--- Begin L Collapse Test ---")

    shape := _make_shape_l()
    log.info("Original shape: ", shape)
    offset := libtess2.offset_polygon(shape[:], -10.0)
    //offset: [][][2]f64 = {libtess2.make_raw_offset_curve(shape[:], {-10.0})}

    // cleaned := libtess2.tesselate_contours({shape[:]}, .Positive, context.temp_allocator)
    // if len(cleaned) == 0 {
    //     libtess2.free_result(cleaned)
    // }

    // raw := make([][]([2]f64), len(cleaned), context.temp_allocator)
    // for i in 0..<len(cleaned) {
    //     raw[i] = libtess2._make_raw_offset_curve(cleaned[i], {-20.0}, context.temp_allocator)
    // }

    // log.info("Raw Offset Curve: ", raw)

    // offset := libtess2.boolean(raw, .Negative)
    log.info("Offset shape: ", offset)

    export_svg(shape[:], offset, "Test L Collapse")

    libtess2.delete_contours(offset)

    log.info("--- End L Collapse Test ---")
}

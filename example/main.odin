package main

import "core:math"
import rl "vendor:raylib"
import ".."

to_screen :: proc(p: [2]f64, origin: [2]f32, scale: f32) -> rl.Vector2 {
    return {origin.x + f32(p.x) * scale, origin.y + f32(p.y) * scale}
}

draw_polygon :: proc(pts: [][2]f64, origin: [2]f32, scale: f32, color: rl.Color) {
    for i in 0..<len(pts) {
        j := (i + 1) % len(pts)
        a := to_screen(pts[i], origin, scale)
        b := to_screen(pts[j], origin, scale)
        rl.DrawLineV(a, b, color)
    }
}

draw_result :: proc(result: [][][2]f64, origin: [2]f32, scale: f32, fill: rl.Color, edge: rl.Color) {
    tris := libtess2.triangulate_polygons(result)
    defer delete(tris)
    for tri in tris {
        a := to_screen(tri[0], origin, scale)
        b := to_screen(tri[1], origin, scale)
        c := to_screen(tri[2], origin, scale)
        rl.DrawTriangle(a, b, c, fill)
        rl.DrawTriangle(a, c, b, fill)
    }
    for c in result do draw_polygon(c, origin, scale, edge)
}

draw_cell :: proc(
    result:  [][][2]f64,
    ghost:   [][2]f64,
    ghost2:  [][2]f64,
    origin:  [2]f32,
    scale:   f32,
    fill:    rl.Color,
    edge:    rl.Color,
    label:   cstring,
) {
    if ghost  != nil do draw_polygon(ghost,  origin, scale, {255, 255, 255, 30})
    if ghost2 != nil do draw_polygon(ghost2, origin, scale, {255, 255, 255, 30})
    draw_result(result, origin, scale, fill, edge)
    rl.DrawText(label, i32(origin.x) - 90, i32(origin.y) + 170, 16, rl.WHITE)
}

free_result :: proc(r: [][][2]f64) {
    for c in r do delete(c)
    delete(r)
}

make_circle :: proc(cx, cy, r: f64, segments: int) -> [][2]f64 {
    pts := make([][2]f64, segments)
    for i in 0..<segments {
        angle  := f64(i) * 2.0 * math.PI / f64(segments)
        pts[i]  = {cx + math.cos(angle) * r, cy + math.sin(angle) * r}
    }
    return pts
}

make_star :: proc(cx, cy, r_outer, r_inner: f64, points: int) -> [][2]f64 {
    pts := make([][2]f64, points * 2)
    for i in 0..<points * 2 {
        angle  := f64(i) * math.PI / f64(points) - math.PI / 2.0
        r      := r_outer if i % 2 == 0 else r_inner
        pts[i]  = {cx + math.cos(angle) * r, cy + math.sin(angle) * r}
    }
    return pts
}

make_cross :: proc(cx, cy, size, thickness: f64) -> [12][2]f64 {
    h := thickness / 2
    s := size / 2
    return [12][2]f64{
        {cx - h, cy - s}, {cx + h, cy - s},
        {cx + h, cy - h}, {cx + s, cy - h},
        {cx + s, cy + h}, {cx + h, cy + h},
        {cx + h, cy + s}, {cx - h, cy + s},
        {cx - h, cy + h}, {cx - s, cy + h},
        {cx - s, cy - h}, {cx - h, cy - h},
    }
}

make_u_shape :: proc(cx, cy, size, wall: f64) -> [8][2]f64 {
    s := size / 2
    return [8][2]f64{
        {cx - s,      cy - s},
        {cx + s,      cy - s},
        {cx + s,      cy + s},
        {cx + s-wall, cy + s},
        {cx + s-wall, cy - s + wall},
        {cx - s+wall, cy - s + wall},
        {cx - s+wall, cy + s},
        {cx - s,      cy + s},
    }
}

make_thin_rect :: proc(cx, cy, w, h: f64) -> [4][2]f64 {
    return [4][2]f64{
        {cx - w/2, cy - h/2}, {cx + w/2, cy - h/2},
        {cx + w/2, cy + h/2}, {cx - w/2, cy + h/2},
    }
}

Cell :: struct {
    result: [][][2]f64,
    ghost:  [][2]f64,
    ghost2: [][2]f64,
    scale:  f32,
    fill:   rl.Color,
    edge:   rl.Color,
    label:  cstring,
}

main :: proc() {
    W, H :: 1200, 800
    rl.InitWindow(W, H, "libtess2 ops test")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    // ── shapes ───────────────────────────────────────────────
    square    := [][2]f64{{-60,-60},{60,-60},{60,60},{-60,60}}
    circle    := make_circle(30, 30, 50, 32)
    l_shape   := [][2]f64{{-60,-60},{60,-60},{60,0},{0,0},{0,60},{-60,60}}
    thin_l    := [][2]f64{{-60,-60},{60,-60},{60,-40},{-40,-40},{-40,60},{-60,60}}
    star      := make_star(0, 0, 60, 25, 5)
    cross     := make_cross(0, 0, 120, 30)
    u_shape   := make_u_shape(0, 0, 120, 20)
    thin_rect := make_thin_rect(0, 0, 120, 10)
    square_a  := [][2]f64{{-70,-40},{20,-40},{20,40},{-70,40}}
    square_b  := [][2]f64{{-20,-40},{70,-40},{70,40},{-20,40}}
    per_edge  := []f64{-8, -30, -8, -8, -20, -8}

    defer delete(circle)
    defer delete(star)

    // ── cells ────────────────────────────────────────────────
    cells := []Cell{
        {libtess2.union_polygons({square, circle}),            square,    circle, 1.8, {0,200,100,60},   rl.GREEN,   "Union"},
        {libtess2.intersect_polygons({square, circle}),        square,    circle, 1.8, {200,0,255,60},   rl.PURPLE,  "Intersection"},
        {libtess2.difference_polygons({square, circle}),       square,    circle, 1.8, {255,140,0,60},   rl.ORANGE,  "Difference (A-B)"},
        {libtess2.xor_polygons({square, circle}),              square,    circle, 1.8, {0,180,255,60},   rl.SKYBLUE, "XOR"},
        {libtess2.offset_polygon(l_shape,    -6.0),            l_shape,   nil,   1.8, {255,80,80,60},   rl.RED,     "L offset in -6"},
        {libtess2.offset_polygon_edges(l_shape, per_edge),     l_shape,   nil,   1.8, {255,220,0,60},   rl.YELLOW,  "L per-edge offset"},
        {libtess2.offset_polygon(l_shape,     6.0),            l_shape,   nil,   1.8, {80,255,80,60},   rl.GREEN,   "L offset out +6"},
        {libtess2.offset_polygon(thin_l,    -30.0),            thin_l,    nil,   1.8, {255,80,80,60},   rl.RED,     "L arm collapse -30"},
        {libtess2.offset_polygon(star,       -8.0),            star,      nil,   1.8, {200,100,255,60}, rl.PURPLE,  "Star offset -8"},
        {libtess2.offset_polygon(cross[:],      -8.0),            cross[:],     nil,   1.5, {255,140,0,60},   rl.ORANGE,  "Cross offset -8"},
        {libtess2.offset_polygon(u_shape[:],    -8.0),            u_shape[:],   nil,   1.5, {0,180,255,60},   rl.SKYBLUE, "U-shape offset -8"},
        {libtess2.offset_polygon(u_shape[:],   -25.0),            u_shape[:],   nil,   1.5, {255,80,80,60},   rl.RED,     "U channel collapse -25"},
        {libtess2.offset_polygon(thin_rect[:],  -4.0),            thin_rect[:], nil,   3.0, {0,200,100,60},   rl.GREEN,   "Thin rect -4 (near)"},
        {libtess2.offset_polygon(thin_rect[:],  -6.0),            thin_rect[:], nil,   3.0, {255,80,80,60},   rl.RED,     "Thin rect -6 (gone)"},
        {libtess2.union_polygons({square_a, square_b}),        square_a,  square_b, 1.8, {0,200,100,60}, rl.GREEN,  "Overlap union"},
        {libtess2.intersect_polygons({square_a, square_b}),    square_a,  square_b, 1.8, {200,0,255,60}, rl.PURPLE, "Overlap intersect"},
    }
    defer for c in cells { free_result(c.result) }

    // ── layout ───────────────────────────────────────────────
    COLS  :: 2
    ROWS  :: 2
    PER_PAGE :: COLS * ROWS

    col := [COLS]f32{300, 900}
    row := [ROWS]f32{250, 600}

    page     := 0
    n_pages  := (len(cells) + PER_PAGE - 1) / PER_PAGE

    for !rl.WindowShouldClose() {
        // input
        if rl.IsKeyPressed(.RIGHT) do page = (page + 1) % n_pages
        if rl.IsKeyPressed(.LEFT)  do page = (page - 1 + n_pages) % n_pages

        rl.BeginDrawing()
        rl.ClearBackground({20, 20, 25, 255})

        // draw current page
        base := page * PER_PAGE
        for slot in 0..<PER_PAGE {
            ci := base + slot
            if ci >= len(cells) do break
            c      := cells[ci]
            origin := [2]f32{col[slot % COLS], row[slot / COLS]}
            draw_cell(c.result, c.ghost, c.ghost2, origin, c.scale, c.fill, c.edge, c.label)
        }

        // page indicator
        page_text := rl.TextFormat("%d / %d", page + 1, n_pages)
        rl.DrawText(page_text, W/2 - 30, H - 30, 20, {255,255,255,180})
        rl.DrawText("< >  arrow keys to cycle", W/2 - 100, H - 55, 16, {255,255,255,80})

        rl.EndDrawing()
    }
}
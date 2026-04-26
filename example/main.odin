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

// H-shape: two vertical legs connected by a thin crossbar
// both legs are 20 wide, crossbar is 10 tall
// at d=-11 the crossbar collapses and the two legs separate
make_h_shape :: proc(cx, cy: f64) -> [12][2]f64 {
    return [12][2]f64{
        {cx-40, cy-60}, {cx-20, cy-60},
        {cx-20, cy-5}, {cx+20, cy-5},
        {cx+20, cy-60}, {cx+40, cy-60},
        {cx+40, cy+60}, {cx+20, cy+60},
        {cx+20, cy+5}, {cx-20, cy+5},
        {cx-20, cy+60}, {cx-40, cy+60},
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

MARGIN    :: f32(40)
LABEL_H   :: f32(24)
CELL_PAD  :: f32(20)

draw_cell :: proc(
    result:  [][][2]f64,
    ghost:   [][2]f64,
    ghost2:  [][2]f64,
    bounds:  rl.Rectangle,  // pixel rect this cell owns
    scale:   f32,
    fill:    rl.Color,
    edge:    rl.Color,
    label:   cstring,
) {
    // cell background
    rl.DrawRectangleRec(bounds, {255, 255, 255, 8})
    rl.DrawRectangleLinesEx(bounds, 1, {255, 255, 255, 25})

    // label strip at top
    label_rect := rl.Rectangle{bounds.x, bounds.y, bounds.width, LABEL_H}
    rl.DrawRectangleRec(label_rect, {255, 255, 255, 15})
    rl.DrawText(label,
        i32(bounds.x) + 8,
        i32(bounds.y) + 4,
        15, rl.WHITE)

    // geometry origin = center of the area below the label strip
    geo_x := bounds.x + bounds.width  * 0.5
    geo_y := bounds.y + LABEL_H + (bounds.height - LABEL_H) * 0.5
    origin := [2]f32{geo_x, geo_y}

    // fit scale: find bounding box of all points, scale to fill cell
    all: [dynamic][2]f64
    defer delete(all)
    if ghost  != nil { for p in ghost  { append(&all, p) } }
    if ghost2 != nil { for p in ghost2 { append(&all, p) } }
    for c in result   { for p in c     { append(&all, p) } }

    auto_scale := scale  // fallback to provided scale
    if len(all) > 0 {
        min_x, min_y :=  math.F64_MAX,  math.F64_MAX
        max_x, max_y := -math.F64_MAX, -math.F64_MAX
        for p in all {
            min_x = min(min_x, p.x); max_x = max(max_x, p.x)
            min_y = min(min_y, p.y); max_y = max(max_y, p.y)
        }
        geo_w := f64(bounds.width  - CELL_PAD * 2)
        geo_h := f64(bounds.height) - f64(CELL_PAD) * 2 - f64(LABEL_H)
        span_x := max_x - min_x
        span_y := max_y - min_y
        if span_x > 0 && span_y > 0 {
            auto_scale = f32(min(geo_w / span_x, geo_h / span_y))
        }
    }

    if ghost  != nil { draw_polygon(ghost,  origin, auto_scale, {255, 255, 255, 30}) }
    if ghost2 != nil { draw_polygon(ghost2, origin, auto_scale, {255, 255, 255, 30}) }
    draw_result(result, origin, auto_scale, fill, edge)
}

// compute cell bounds for a given slot on the current page
cell_bounds :: proc(slot, cols, rows: int, w, h: f32) -> rl.Rectangle {
    cell_w := (w - MARGIN * 2) / f32(cols)
    cell_h := (h - MARGIN * 2) / f32(rows)
    col_i  := slot % cols
    row_i  := slot / cols
    return {
        MARGIN + f32(col_i) * cell_w + CELL_PAD * 0.5,
        MARGIN + f32(row_i) * cell_h + CELL_PAD * 0.5,
        cell_w - CELL_PAD,
        cell_h - CELL_PAD,
    }
}

main :: proc() {
    W, H :: 1600, 1000
    rl.InitWindow(W, H, "libtess2 join type test")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    // ── shapes ───────────────────────────────────────────────
    // L shape with legs of different thickness
    l_shape := [][2]f64{
        {-60, -60}, {60, -60}, {60, -40},
        {-20, -40}, {-20,  60}, {-60, 60},
    }

    // H shape with thin crossbar
    h_shape := [][2]f64{
        {-40, -60}, {-20, -60},
        {-20, -6},  {20,  -6},
        {20,  -60}, {40,  -60},
        {40,   60}, {20,   60},
        {20,    6}, {-20,   6},
        {-20,  60}, {-40,  60},
    }

    // bowtie
    bowtie := [][2]f64{
        {-60, -40}, {60, 40},
        {60, -40},  {-60, 40},
    }

    Cell :: struct {
        result: [][][2]f64,
        ghost:  [][2]f64,
        fill:   rl.Color,
        edge:   rl.Color,
        label:  cstring,
    }

    in_d       :: f64(-4)
    out_d      :: f64(4)
    collapse_d :: f64(-10)

    l_per_edge      := []f64{-4, -15, -4, -4, -12, -4}
    h_per_edge      := []f64{-4, -4, -10, -4, -4, -4, -4, -4, -10, -4, -4, -4}
    bowtie_per_edge := []f64{-4, -12, -4, -12}

    cells := [?]Cell{
        // ── L shape ──────────────────────────────────────────
        {libtess2.offset_polygon_round( l_shape, {in_d},       0.5), l_shape, {255,80,80,60},   rl.RED,    "L round in"},
        {libtess2.offset_polygon_miter( l_shape, {in_d},       2.0), l_shape, {255,80,80,60},   rl.RED,    "L miter in"},
        {libtess2.offset_polygon_bevel( l_shape, {in_d}           ), l_shape, {255,80,80,60},   rl.RED,    "L bevel in"},
        {libtess2.offset_polygon_round( l_shape, {out_d},      0.5), l_shape, {80,255,80,60},   rl.GREEN,  "L round out"},
        {libtess2.offset_polygon_miter( l_shape, {out_d},      2.0), l_shape, {80,255,80,60},   rl.GREEN,  "L miter out"},
        {libtess2.offset_polygon_bevel( l_shape, {out_d}          ), l_shape, {80,255,80,60},   rl.GREEN,  "L bevel out"},
        {libtess2.offset_polygon_round( l_shape, l_per_edge,   0.5), l_shape, {0,180,255,60},   rl.SKYBLUE,"L round per-edge"},
        {libtess2.offset_polygon_miter( l_shape, l_per_edge,   2.0), l_shape, {0,180,255,60},   rl.SKYBLUE,"L miter per-edge"},
        {libtess2.offset_polygon_bevel( l_shape, l_per_edge       ), l_shape, {0,180,255,60},   rl.SKYBLUE,"L bevel per-edge"},
        {libtess2.offset_polygon_round( l_shape, {collapse_d}, 0.5), l_shape, {255,220,0,60},   rl.YELLOW, "L round collapse"},
        {libtess2.offset_polygon_miter( l_shape, {collapse_d}, 2.0), l_shape, {255,220,0,60},   rl.YELLOW, "L miter collapse"},
        {libtess2.offset_polygon_bevel( l_shape, {collapse_d}     ), l_shape, {255,220,0,60},   rl.YELLOW, "L bevel collapse"},

        // ── H shape ──────────────────────────────────────────
        {libtess2.offset_polygon_round( h_shape, {in_d},       0.5), h_shape, {255,80,80,60},   rl.RED,    "H round in"},
        {libtess2.offset_polygon_miter( h_shape, {in_d},       2.0), h_shape, {255,80,80,60},   rl.RED,    "H miter in"},
        {libtess2.offset_polygon_bevel( h_shape, {in_d}           ), h_shape, {255,80,80,60},   rl.RED,    "H bevel in"},
        {libtess2.offset_polygon_round( h_shape, {out_d},      0.5), h_shape, {80,255,80,60},   rl.GREEN,  "H round out"},
        {libtess2.offset_polygon_miter( h_shape, {out_d},      2.0), h_shape, {80,255,80,60},   rl.GREEN,  "H miter out"},
        {libtess2.offset_polygon_bevel( h_shape, {out_d}          ), h_shape, {80,255,80,60},   rl.GREEN,  "H bevel out"},
        {libtess2.offset_polygon_round( h_shape, h_per_edge,   0.5), h_shape, {0,180,255,60},   rl.SKYBLUE,"H round per-edge"},
        {libtess2.offset_polygon_miter( h_shape, h_per_edge,   2.0), h_shape, {0,180,255,60},   rl.SKYBLUE,"H miter per-edge"},
        {libtess2.offset_polygon_bevel( h_shape, h_per_edge       ), h_shape, {0,180,255,60},   rl.SKYBLUE,"H bevel per-edge"},
        {libtess2.offset_polygon_round( h_shape, {collapse_d * 0.75}, 0.5), h_shape, {255,220,0,60},   rl.YELLOW, "H round collapse"},
        {libtess2.offset_polygon_miter( h_shape, {collapse_d * 0.75}, 2.0), h_shape, {255,220,0,60},   rl.YELLOW, "H miter collapse"},
        {libtess2.offset_polygon_bevel( h_shape, {collapse_d * 0.75}     ), h_shape, {255,220,0,60},   rl.YELLOW, "H bevel collapse"},

        // ── bowtie ───────────────────────────────────────────
        {libtess2.offset_polygon_bevel( bowtie, {in_d}            ), bowtie, {255,80,80,60},    rl.RED,    "Bowtie bevel in"},
        {libtess2.offset_polygon_round( bowtie, {out_d},       0.5), bowtie, {80,255,80,60},    rl.GREEN,  "Bowtie round out"},
        {libtess2.offset_polygon_miter( bowtie, {out_d},       2.0), bowtie, {80,255,80,60},    rl.GREEN,  "Bowtie miter out"},
        {libtess2.offset_polygon_bevel( bowtie, {out_d}           ), bowtie, {80,255,80,60},    rl.GREEN,  "Bowtie bevel out"},
        {libtess2.offset_polygon_round( bowtie, bowtie_per_edge,0.5), bowtie, {0,180,255,60},   rl.SKYBLUE,"Bowtie round per-edge"},
        {libtess2.offset_polygon_miter( bowtie, bowtie_per_edge,2.0), bowtie, {0,180,255,60},   rl.SKYBLUE,"Bowtie miter per-edge"},
        {libtess2.offset_polygon_bevel( bowtie, bowtie_per_edge    ), bowtie, {0,180,255,60},   rl.SKYBLUE,"Bowtie bevel per-edge"},
    }
    defer for c in cells { 
        for r in c.result do delete(r)
        delete(c.result)
    }

    page    := 0
    n_pages := len(cells)

    for !rl.WindowShouldClose() {
        if rl.IsKeyPressed(.RIGHT) do page = (page + 1) % n_pages
        if rl.IsKeyPressed(.LEFT)  do page = (page - 1 + n_pages) % n_pages

        rl.BeginDrawing()
        rl.ClearBackground({20, 20, 25, 255})

        c      := cells[page]
        bounds := rl.Rectangle{MARGIN, MARGIN, W - MARGIN * 2, H - MARGIN * 2}
        draw_cell(c.result, c.ghost, nil, bounds, 2.0, c.fill, c.edge, c.label)

        page_text := rl.TextFormat("%d / %d", page + 1, n_pages)
        rl.DrawText(page_text, W/2 - 30, H - 30, 20, {255,255,255,180})
        rl.DrawText("< >  arrow keys to cycle", W/2 - 100, H - 55, 16, {255,255,255,80})

        rl.EndDrawing()
    }
}
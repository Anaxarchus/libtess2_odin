package main

import "core:math"
import rl "vendor:raylib"
import ".."

to_screen :: proc(p: [2]f64, origin: [2]f32, scale: f32) -> rl.Vector2 {
    return {origin.x + f32(p.x) * scale, origin.y - f32(p.y) * scale}
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
    tris := libtess2.tesselate_triangles(result, .Odd)
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

draw_cell :: proc(result: [][][2]f64, ghost: [][2]f64, ghost2: [][2]f64, origin: [2]f32, scale: f32, fill: rl.Color, edge: rl.Color, label: cstring) {
    // ghost shapes
    if ghost  != nil do draw_polygon(ghost,  origin, scale, {255, 255, 255, 30})
    if ghost2 != nil do draw_polygon(ghost2, origin, scale, {255, 255, 255, 30})
    draw_result(result, origin, scale, fill, edge)
    rl.DrawText(label, i32(origin.x) - 70, i32(origin.y) - 160, 16, rl.WHITE)
}

free_result :: proc(r: [][][2]f64) {
    for c in r do delete(c)
    delete(r)
}

main :: proc() {
    W, H :: 1200, 800
    rl.InitWindow(W, H, "libtess2 ops test")
    defer rl.CloseWindow()
    rl.SetTargetFPS(60)

    square := [][2]f64{
        {-60, -60}, {60, -60}, {60, 60}, {-60, 60},
    }

    // circle approximation, offset so it overlaps square
    circle := make([][2]f64, 32)
    for i in 0..<32 {
        angle   := f64(i) * 2.0 * math.PI / 32.0
        circle[i] = {math.cos(angle) * 50 + 30, math.sin(angle) * 50 + 30}
    }

    // L-shape for offset tests
    l_shape := [][2]f64{
        {-60, -60}, {60, -60}, {60, 0}, {0, 0}, {0, 60}, {-60, 60},
    }

    // per-edge deltas for the L, different insets per edge
    per_edge := []f64{-8, -20, -8, -8, -20, -8}

    // compute all results once
    r_union        := libtess2.union_polygons      ({square, circle})
    r_intersect    := libtess2.intersect_polygons  ({square, circle})
    r_difference   := libtess2.difference_polygons ({square, circle})
    r_xor          := libtess2.xor_polygons        ({square, circle})
    r_offset       := libtess2.offset_polygon      (l_shape, -10.0)
    r_offset_edges := libtess2.offset_polygon_edges(l_shape, per_edge)

    defer free_result(r_union)
    defer free_result(r_intersect)
    defer free_result(r_difference)
    defer free_result(r_xor)
    defer free_result(r_offset)
    defer free_result(r_offset_edges)
    defer delete(circle)

    // cell layout: 3 columns, 2 rows
    col := [3]f32{200, 600, 1000}
    row := [2]f32{220, 580}
    s   : f32 = 1.8

    for !rl.WindowShouldClose() {
        rl.BeginDrawing()
        rl.ClearBackground({20, 20, 25, 255})

        // row 0
        draw_cell(r_union,        square, circle,  {col[0], row[0]}, s, {0, 200, 100, 60},  rl.GREEN,  "Union")
        draw_cell(r_intersect,    square, circle,  {col[1], row[0]}, s, {200, 0, 255, 60},  rl.PURPLE, "Intersection")
        draw_cell(r_difference,   square, circle,  {col[2], row[0]}, s, {255, 140, 0, 60},  rl.ORANGE, "Difference (A - B)")

        // row 1
        draw_cell(r_xor,          square, circle,  {col[0], row[1]}, s, {0, 180, 255, 60},  rl.SKYBLUE, "XOR")
        draw_cell(r_offset,       l_shape, nil,    {col[1], row[1]}, s, {255, 80, 80, 60},  rl.RED,     "Offset (uniform -10)")
        draw_cell(r_offset_edges, l_shape, nil,    {col[2], row[1]}, s, {255, 220, 0, 60},  rl.YELLOW,  "Offset (per-edge)")

        rl.EndDrawing()
    }
}
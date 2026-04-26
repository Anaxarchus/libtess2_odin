package test

// By Claude


import "core:fmt"
import "core:math"
import "core:os"
import "core:strings"

@(private="file")
PANEL_W  :: 300.0
@(private="file")
PANEL_H  :: 300.0
@(private="file")
MARGIN   :: 30.0
@(private="file")
LEGEND_H :: 100.0
@(private="file")
GAP      :: 20.0

@(private="file")
COLORS := [?]string { "#f72585", "#7209b7", "#fb8500", "#06d6a0", "#4361ee", "#f77f00" }

@(private="file")
_flip_y :: #force_inline proc(y: f64) -> f64 { return PANEL_H - y }

@(private="file")
_fit :: proc(pts: [][2]f64) -> (ox, oy, scale: f64) {
    min_x, min_y :=  math.F64_MAX,  math.F64_MAX
    max_x, max_y := -math.F64_MAX, -math.F64_MAX
    for p in pts {
        if p.x < min_x do min_x = p.x
        if p.y < min_y do min_y = p.y
        if p.x > max_x do max_x = p.x
        if p.y > max_y do max_y = p.y
    }
    w := max(max_x - min_x, 1.0)
    h := max(max_y - min_y, 1.0)
    scale = math.min((PANEL_W - MARGIN*2) / w, (PANEL_H - MARGIN*2) / h)
    ox = -min_x + MARGIN / scale
    oy = -min_y + MARGIN / scale
    return
}

@(private="file")
_tf :: proc(p: [2]f64, ox, oy, scale, shift_x: f64) -> (sx, sy: f64) {
    sx = (p.x + ox) * scale + shift_x
    sy = _flip_y((p.y + oy) * scale)
    return
}

@(private="file")
_poly :: proc(b: ^strings.Builder, pts: [][2]f64, ox, oy, scale, shift_x: f64,
              fill, stroke: string, fill_opacity, stroke_width: f64,
              dashed := false) {
    fmt.sbprint(b, `  <polygon points="`)
    for p in pts {
        x, y := _tf(p, ox, oy, scale, shift_x)
        fmt.sbprintf(b, "%.2f,%.2f ", x, y)
    }
    dash_attr := ` stroke-dasharray="5 3"` if dashed else ""
    fmt.sbprintf(b,
        `" fill="%v" fill-opacity="%.2f" stroke="%v" stroke-width="%.1f"%v stroke-linejoin="round"/>`,
        fill, fill_opacity, stroke, stroke_width, dash_attr)
    fmt.sbprint(b, "\n")
}

@(private="file")
_dot :: proc(b: ^strings.Builder, p: [2]f64, idx: int, ox, oy, scale, shift_x: f64, color: string) {
    x, y := _tf(p, ox, oy, scale, shift_x)
    fmt.sbprintf(b, `  <circle cx="%.2f" cy="%.2f" r="3" fill="%v"/>`, x, y, color)
    fmt.sbprint(b, "\n")
    fmt.sbprintf(b,
        `  <text x="%.2f" y="%.2f" font-family="monospace" font-size="9" fill="%v" text-anchor="middle">(%v,%v)</text>`+"\n",
        x, y - 7, color, int(p.x), int(p.y))
}

@(private="file")
_label :: proc(b: ^strings.Builder, x, y: f64, text, color: string, size: int = 12) {
    fmt.sbprintf(b,
        `  <text x="%.2f" y="%.2f" font-family="monospace" font-size="%v" fill="%v">%v</text>`+"\n",
        x, y, size, color, text)
}

@(private="file")
_swatch :: proc(b: ^strings.Builder, x, y: f64, color, text: string) {
    fmt.sbprintf(b, `  <rect x="%.2f" y="%.2f" width="12" height="12" fill="%v" rx="2"/>`, x, y, color)
    fmt.sbprint(b, "\n")
    _label(b, x + 18, y + 10, text, "#cccccc", 11)
}

// Export a two-panel SVG comparing `basis` (before) with `result` (after).
// Each contour in `result` is drawn in a distinct colour.
// The file is written to `<description>.svg` with spaces replaced by underscores.
export_svg :: proc(basis: [][2]f64, result: [][][2]f64, description: string) -> bool {
    // ── collect all world-space points for a unified fit ────────────────
    all_pts: [dynamic][2]f64
    defer delete(all_pts)
    for p in basis { append(&all_pts, p) }
    for contour in result { for p in contour { append(&all_pts, p) } }

    ox, oy, scale := _fit(all_pts[:])

    canvas_w := PANEL_W * 2 + GAP
    canvas_h := PANEL_H + LEGEND_H

    b: strings.Builder
    strings.builder_init(&b)
    defer strings.builder_destroy(&b)

    fmt.sbprintf(&b,
        `<svg xmlns="http://www.w3.org/2000/svg" width="%.0f" height="%.0f" style="background:#1a1a2e">`+"\n",
        canvas_w, canvas_h)

    // ── panel A: basis ───────────────────────────────────────────────────
    _poly(&b, basis, ox, oy, scale, 0,
          fill="#4cc9f0", stroke="#90e0ef", fill_opacity=0.30, stroke_width=2)
    for p, i in basis { _dot(&b, p, i, ox, oy, scale, 0, "#90e0ef") }
    _label(&b, 10, 16, "basis", "#e0e0e0", 13)

    // ── panel B: result contours + faint basis reference ─────────────────
    shift := PANEL_W + GAP
    _poly(&b, basis, ox, oy, scale, shift,
          fill="#4cc9f0", stroke="#4cc9f0", fill_opacity=0.06, stroke_width=1, dashed=true)

    for contour, ci in result {
        col := COLORS[ci % len(COLORS)]
        _poly(&b, contour, ox, oy, scale, shift,
              fill=col, stroke=col, fill_opacity=0.40, stroke_width=2)
        for p, i in contour { _dot(&b, p, i, ox, oy, scale, shift, col) }
    }
    _label(&b, shift + 10, 16,
           fmt.tprintf("result (%v contour%v)", len(result), "s" if len(result) != 1 else ""),
           "#e0e0e0", 13)

    // ── legend ───────────────────────────────────────────────────────────
    ly := PANEL_H + 12.0
    _swatch(&b, 10, ly, "#4cc9f0", "basis")
    for contour, ci in result {
        col := COLORS[ci % len(COLORS)]
        _swatch(&b, 10, ly + f64(ci + 1) * 18, col, fmt.tprintf("contour %v", ci))
    }
    // description in bottom-right
    _label(&b, shift + 10, ly + 10, description, "#666666", 11)

    fmt.sbprint(&b, "</svg>\n")

    // ── write file ───────────────────────────────────────────────────────
    filename_raw := strings.clone(description)
    defer delete(filename_raw)
    filename, was_allocation := strings.replace_all(filename_raw, " ", "_")
    defer if was_allocation do delete(filename)
    path := fmt.tprintf("%v.svg", filename)

    return os.write_entire_file(path, transmute([]byte)strings.to_string(b))
}

package main

import "core:fmt"
import "core:strings"
import rl "vendor:raylib"

// In-app graphical model editor for free OdinVTube format (.ovt.json / avatar.json).
// Toggle with F5 from the main app.

Model_Editor :: struct {
	active:       bool,
	selected:     int,
	dragging:     bool,
	drag_off_x:   f32,
	drag_off_y:   f32,
	save_path:    string,
	status:       string,
	status_timer: f32,
	// panel
	panel_w:      f32,
	scroll:       f32,
	// live tracking still runs while editing
	preview_track: bool,
}

editor_init :: proc(save_path: string) -> Model_Editor {
	return Model_Editor{
		active        = false,
		selected      = 0,
		save_path     = strings.clone(save_path),
		status        = "",
		panel_w       = 320,
		preview_track = true,
	}
}

editor_destroy :: proc(e: ^Model_Editor) {
	delete(e.save_path)
	delete(e.status)
}

editor_set_status :: proc(e: ^Model_Editor, msg: string) {
	delete(e.status)
	e.status = strings.clone(msg)
	e.status_timer = 3.0
}

editor_toggle :: proc(e: ^Model_Editor) {
	e.active = !e.active
	if e.active {
		editor_set_status(e, "Model editor — drag layers, add parts, Ctrl+S save")
	}
}

// Button hit test
ui_btn :: proc(r: rl.Rectangle, label: cstring, accent: bool = false) -> bool {
	m := rl.GetMousePosition()
	hot := rl.CheckCollisionPointRec(m, r)
	col := rl.Color{40, 44, 58, 255}
	if accent do col = rl.Color{50, 90, 180, 255}
	if hot do col = rl.Color{col.r + 20, col.g + 20, col.b + 25, 255}
	rl.DrawRectangleRec(r, col)
	rl.DrawRectangleLinesEx(r, 1, rl.Color{80, 90, 120, 255})
	tw := rl.MeasureText(label, 16)
	rl.DrawText(label, i32(r.x + (r.width - f32(tw)) * 0.5), i32(r.y + r.height * 0.5 - 8), 16, rl.RAYWHITE)
	return hot && rl.IsMouseButtonPressed(.LEFT)
}

ui_label :: proc(x, y: f32, text: cstring, size: i32 = 16, col: rl.Color = rl.LIGHTGRAY) {
	rl.DrawText(text, i32(x), i32(y), size, col)
}

editor_add_part :: proc(a: ^Avatar, kind: string) {
	name := kind
	tint: [4]u8 = {255, 255, 255, 255}
	ox, oy: f32
	rot_p, px_p, py_p: string
	rz, pxs, pys: f32 = 1, 0, 0

	switch kind {
	case "head":
		oy = -20
		tint = {255, 224, 196, 255}
		rot_p = "ParamAngleZ"
		px_p = "ParamAngleX"
		pxs = 2.5
		py_p = "ParamAngleY"
		pys = -2
	case "body":
		oy = 120
		rot_p = "ParamBodyAngleZ"
		rz = 0.4
		px_p = "ParamBodyAngleX"
		pxs = 1.2
	case "hair":
		oy = -90
		tint = {90, 60, 140, 255}
		rot_p = "ParamAngleZ"
		rz = 1.2
		px_p = "ParamAngleX"
		pxs = 3
	case "eye_l":
		ox, oy = -36, -20
	case "eye_r":
		ox, oy = 36, -20
	case "brow_l":
		ox, oy = -38, -55
		tint = {60, 40, 30, 255}
	case "brow_r":
		ox, oy = 38, -55
		tint = {60, 40, 30, 255}
	case "mouth":
		oy = 40
		tint = {200, 80, 100, 255}
	case "blush":
		oy = 15
		tint = {255, 120, 140, 180}
	}

	append(&a.def.layers, make_layer(name, kind, ox, oy, tint, rot_p, rz, px_p, pxs, py_p, pys))
}

editor_delete_selected :: proc(e: ^Model_Editor, a: ^Avatar) {
	if e.selected < 0 || e.selected >= len(a.def.layers) do return
	layer := &a.def.layers[e.selected]
	if layer.has_tex do rl.UnloadTexture(layer.tex)
	avatar_layer_free_strings(layer)
	ordered_remove(&a.def.layers, e.selected)
	if e.selected >= len(a.def.layers) do e.selected = len(a.def.layers) - 1
}

editor_update_draw :: proc(
	e: ^Model_Editor,
	a: ^Avatar,
	params: Model_Params,
	phys: Physics_State,
	win_w, win_h: i32,
	user_scale: f32,
	dt: f32,
) {
	if !e.active do return

	if e.status_timer > 0 {
		e.status_timer -= dt
	}

	// Canvas: avatar already drawn by caller; we overlay gizmos + UI

	// --- Drag selected layer ---
	panel_w := e.panel_w
	canvas_w := f32(win_w) - panel_w
	m := rl.GetMousePosition()
	in_canvas := m.x < canvas_w

	if e.selected >= 0 && e.selected < len(a.def.layers) && in_canvas {
		lx, ly, ok := avatar_layer_screen_pos(a^, e.selected, win_w, win_h, user_scale)
		if ok {
			// gizmo
			rl.DrawCircleLines(i32(lx), i32(ly), 28, rl.Color{100, 200, 255, 220})
			rl.DrawCircle(i32(lx), i32(ly), 5, rl.Color{100, 200, 255, 255})
			rl.DrawText(strings.clone_to_cstring(a.def.layers[e.selected].name, context.temp_allocator), i32(lx + 32), i32(ly - 8), 16, rl.SKYBLUE)

			if rl.IsMouseButtonPressed(.LEFT) {
				if (m.x - lx) * (m.x - lx) + (m.y - ly) * (m.y - ly) < 40 * 40 {
					e.dragging = true
					sc := a.def.scale * user_scale
					if sc < 0.001 do sc = 1
					e.drag_off_x = (m.x - lx) / sc
					e.drag_off_y = (m.y - ly) / sc
				}
			}
			if e.dragging && rl.IsMouseButtonDown(.LEFT) {
				sc := a.def.scale * user_scale
				if sc < 0.001 do sc = 1
				cx := f32(win_w) * 0.5 + a.def.pos_x
				cy := f32(win_h) * 0.5 + a.def.pos_y
				a.def.layers[e.selected].ox = (m.x - e.drag_off_x * sc - cx) / sc
				a.def.layers[e.selected].oy = (m.y - e.drag_off_y * sc - cy) / sc
			}
			if rl.IsMouseButtonReleased(.LEFT) {
				e.dragging = false
			}
		}
	}

	// Keyboard nudge
	if e.selected >= 0 && e.selected < len(a.def.layers) {
		step: f32 = rl.IsKeyDown(.LEFT_SHIFT) ? 5 : 1
		if rl.IsKeyPressed(.LEFT) || (rl.IsKeyDown(.LEFT) && rl.IsKeyDown(.LEFT_CONTROL)) {
			a.def.layers[e.selected].ox -= step
		}
		if rl.IsKeyPressed(.RIGHT) || (rl.IsKeyDown(.RIGHT) && rl.IsKeyDown(.LEFT_CONTROL)) {
			a.def.layers[e.selected].ox += step
		}
		if rl.IsKeyPressed(.UP) || (rl.IsKeyDown(.UP) && rl.IsKeyDown(.LEFT_CONTROL)) {
			a.def.layers[e.selected].oy -= step
		}
		if rl.IsKeyPressed(.DOWN) || (rl.IsKeyDown(.DOWN) && rl.IsKeyDown(.LEFT_CONTROL)) {
			a.def.layers[e.selected].oy += step
		}
		if rl.IsKeyPressed(.DELETE) || rl.IsKeyPressed(.BACKSPACE) {
			editor_delete_selected(e, a)
		}
	}

	// Save
	if rl.IsKeyDown(.LEFT_CONTROL) && rl.IsKeyPressed(.S) {
		if save_avatar(a^, e.save_path) {
			editor_set_status(e, fmt.tprintf("Saved %s", e.save_path))
		} else {
			editor_set_status(e, "Save failed")
		}
	}

	// --- Right panel ---
	px := f32(win_w) - panel_w
	rl.DrawRectangle(i32(px), 0, i32(panel_w), win_h, rl.Color{18, 20, 28, 245})
	rl.DrawLine(i32(px), 0, i32(px), win_h, rl.Color{70, 80, 110, 255})

	y: f32 = 12
	ui_label(px + 12, y, "Model Editor", 22, rl.Color{140, 200, 255, 255})
	y += 28
	ui_label(px + 12, y, "Free format — no paid SDK", 14, rl.GRAY)
	y += 22
	ui_label(px + 12, y, strings.clone_to_cstring(fmt.tprintf("File: %s", e.save_path), context.temp_allocator), 14, rl.LIGHTGRAY)
	y += 26

	// Add parts
	ui_label(px + 12, y, "Add part", 16, rl.SKYBLUE)
	y += 22
	kinds := []string{"head", "body", "hair", "eye_l", "eye_r", "mouth", "brow_l", "brow_r", "blush"}
	bx := px + 10
	by := y
	for k, i in kinds {
		col := i % 3
		row := i / 3
		r := rl.Rectangle{bx + f32(col) * 100, by + f32(row) * 32, 94, 28}
		if ui_btn(r, strings.clone_to_cstring(k, context.temp_allocator)) {
			editor_add_part(a, k)
			e.selected = len(a.def.layers) - 1
			editor_set_status(e, fmt.tprintf("Added %s", k))
		}
	}
	y = by + 3 * 32 + 10

	// Layer list
	ui_label(px + 12, y, "Layers (click to select)", 16, rl.SKYBLUE)
	y += 22
	list_h: f32 = 160
	rl.DrawRectangle(i32(px + 8), i32(y), i32(panel_w - 16), i32(list_h), rl.Color{12, 14, 20, 255})
	ly := y + 4
	for layer, i in a.def.layers {
		row := rl.Rectangle{px + 10, ly, panel_w - 20, 22}
		if i == e.selected {
			rl.DrawRectangleRec(row, rl.Color{40, 70, 120, 255})
		}
		label := fmt.ctprintf("%d  %s  (%s)", i, layer.name, layer.kind)
		rl.DrawText(label, i32(row.x + 4), i32(row.y + 3), 14, rl.RAYWHITE)
		if rl.CheckCollisionPointRec(m, row) && rl.IsMouseButtonPressed(.LEFT) && m.x >= px {
			e.selected = i
		}
		ly += 24
		if ly > y + list_h - 20 do break
	}
	y += list_h + 12

	// Selected props
	if e.selected >= 0 && e.selected < len(a.def.layers) {
		layer := &a.def.layers[e.selected]
		ui_label(px + 12, y, "Selected layer", 16, rl.SKYBLUE)
		y += 22
		ui_label(px + 12, y, fmt.ctprintf("ox=%.1f  oy=%.1f", layer.ox, layer.oy), 15, rl.RAYWHITE)
		y += 20
		ui_label(px + 12, y, "Arrow keys nudge · Shift = 5px", 13, rl.GRAY)
		y += 20
		ui_label(px + 12, y, "Del = remove layer", 13, rl.GRAY)
		y += 24

		// Bind presets
		ui_label(px + 12, y, "Motion bind", 16, rl.SKYBLUE)
		y += 22
		if ui_btn({px + 10, y, 145, 28}, "Bind head angles") {
			delete(layer.rot_z_param)
			delete(layer.pos_x_param)
			delete(layer.pos_y_param)
			layer.rot_z_param = av_str("ParamAngleZ")
			layer.rot_z_scale = 1
			layer.pos_x_param = av_str("ParamAngleX")
			layer.pos_x_scale = 2.5
			layer.pos_y_param = av_str("ParamAngleY")
			layer.pos_y_scale = -2
			editor_set_status(e, "Bound head motion")
		}
		if ui_btn({px + 160, y, 145, 28}, "Bind body") {
			delete(layer.rot_z_param)
			delete(layer.pos_x_param)
			delete(layer.pos_y_param)
			layer.rot_z_param = av_str("ParamBodyAngleZ")
			layer.rot_z_scale = 0.4
			layer.pos_x_param = av_str("ParamBodyAngleX")
			layer.pos_x_scale = 1.2
			layer.pos_y_param = ""
			layer.pos_y_scale = 0
			editor_set_status(e, "Bound body motion")
		}
		y += 34
		if ui_btn({px + 10, y, 145, 28}, "Clear binds") {
			delete(layer.rot_z_param)
			delete(layer.pos_x_param)
			delete(layer.pos_y_param)
			layer.rot_z_param = ""
			layer.pos_x_param = ""
			layer.pos_y_param = ""
			layer.rot_z_scale = 1
			layer.pos_x_scale = 0
			layer.pos_y_scale = 0
		}
		if ui_btn({px + 160, y, 145, 28}, "Delete layer", false) {
			editor_delete_selected(e, a)
		}
		y += 40

		// Tint RGB quick
		ui_label(px + 12, y, "Tint (R/G/B ±)", 16, rl.SKYBLUE)
		y += 22
		adj :: proc(v: ^u8, d: int) {
			n := int(v^) + d
			if n < 0 do n = 0
			if n > 255 do n = 255
			v^ = u8(n)
		}
		if ui_btn({px + 10, y, 44, 26}, "R-") do adj(&layer.tint[0], -10)
		if ui_btn({px + 56, y, 44, 26}, "R+") do adj(&layer.tint[0], 10)
		if ui_btn({px + 110, y, 44, 26}, "G-") do adj(&layer.tint[1], -10)
		if ui_btn({px + 156, y, 44, 26}, "G+") do adj(&layer.tint[1], 10)
		if ui_btn({px + 210, y, 44, 26}, "B-") do adj(&layer.tint[2], -10)
		if ui_btn({px + 256, y, 44, 26}, "B+") do adj(&layer.tint[2], 10)
		y += 32
		ui_label(px + 12, y, fmt.ctprintf("RGB %d %d %d  A %d", layer.tint[0], layer.tint[1], layer.tint[2], layer.tint[3]), 14, rl.LIGHTGRAY)
		y += 28
	}

	// Model root
	ui_label(px + 12, y, "Model root", 16, rl.SKYBLUE)
	y += 22
	if ui_btn({px + 10, y, 70, 26}, "X-") do a.def.pos_x -= 5
	if ui_btn({px + 84, y, 70, 26}, "X+") do a.def.pos_x += 5
	if ui_btn({px + 158, y, 70, 26}, "Y-") do a.def.pos_y -= 5
	if ui_btn({px + 232, y, 70, 26}, "Y+") do a.def.pos_y += 5
	y += 32
	if ui_btn({px + 10, y, 90, 28}, "Scale -") do a.def.scale = max(0.2, a.def.scale - 0.05)
	if ui_btn({px + 108, y, 90, 28}, "Scale +") do a.def.scale = min(3.0, a.def.scale + 0.05)
	if ui_btn({px + 206, y, 100, 28}, "Reset root") {
		a.def.pos_x = 0
		a.def.pos_y = 40
		a.def.scale = 1
	}
	y += 36

	// Save / new
	if ui_btn({px + 10, y, 145, 34}, "Save model", true) {
		if save_avatar(a^, e.save_path) {
			editor_set_status(e, fmt.tprintf("Saved %s", e.save_path))
		} else {
			editor_set_status(e, "Save failed")
		}
	}
	if ui_btn({px + 165, y, 145, 34}, "Reset default") {
		avatar_destroy(a)
		a^ = avatar_default_procedural()
		e.selected = 0
		editor_set_status(e, "Reset to default procedural")
	}
	y += 44

	ui_label(px + 12, y, "F5 leave editor · Ctrl+S save", 14, rl.GRAY)
	y += 20
	ui_label(px + 12, y, "Tracking still live (mouse)", 14, rl.GRAY)

	if e.status_timer > 0 && e.status != "" {
		rl.DrawRectangle(8, win_h - 40, win_w - i32(panel_w) - 16, 32, rl.Color{20, 40, 30, 220})
		rl.DrawText(strings.clone_to_cstring(e.status, context.temp_allocator), 16, win_h - 32, 18, rl.Color{120, 255, 180, 255})
	}

	// Title banner on canvas
	rl.DrawText("EDIT MODE — drag the blue handle · F5 back to stream", 12, 10, 18, rl.Color{180, 220, 255, 230})
}

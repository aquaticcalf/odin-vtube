package main

import "core:encoding/json"
import "core:fmt"
import "core:math"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// OdinVTube avatar format — layered 2D, parameter-driven.
// Not Live2D moc3 (that needs Cubism SDK). This is our clean-room format
// that gives the same *feel* for streaming: head angles, eyes, mouth, physics.

Avatar_Layer :: struct {
	name:     string,
	texture:  string, // relative path, optional
	// base draw
	ox, oy:   f32, // offset from center
	w, h:     f32, // size; 0 = use texture size
	// which params affect this layer
	rot_z_param:   string, // e.g. ParamAngleZ
	rot_z_scale:   f32,
	pos_x_param:   string,
	pos_x_scale:   f32,
	pos_y_param:   string,
	pos_y_scale:   f32,
	scale_param:   string,
	scale_amount:  f32,
	visible_param: string, // if set, hide when value < 0.5
	// color tint channel (optional)
	tint:     [4]u8,
	// loaded
	tex:      rl.Texture2D,
	has_tex:  bool,
	// procedural kind if no texture: "head" | "eye_l" | "eye_r" | "mouth" | "brow_l" | "brow_r" | "hair" | "body" | "blush"
	kind:     string,
}

Avatar_Def :: struct {
	name:   string,
	layers: [dynamic]Avatar_Layer,
	// model screen position
	pos_x:  f32,
	pos_y:  f32,
	scale:  f32,
}

Avatar :: struct {
	def:      Avatar_Def,
	loaded:   bool,
	// optional full texture billboard (e.g. VTS PNG preview)
	billboard: rl.Texture2D,
	has_billboard: bool,
}

avatar_default_procedural :: proc() -> Avatar {
	a: Avatar
	a.def.name = "Default Procedural"
	a.def.pos_x = 0
	a.def.pos_y = 40
	a.def.scale = 1
	a.def.layers = make([dynamic]Avatar_Layer)

	append(&a.def.layers, Avatar_Layer{name = "body", kind = "body", oy = 120, tint = {255, 255, 255, 255}, rot_z_param = "ParamBodyAngleZ", rot_z_scale = 0.4, pos_x_param = "ParamBodyAngleX", pos_x_scale = 1.2})
	append(&a.def.layers, Avatar_Layer{name = "head", kind = "head", oy = -20, tint = {255, 224, 196, 255}, rot_z_param = "ParamAngleZ", rot_z_scale = 1, pos_x_param = "ParamAngleX", pos_x_scale = 2.5, pos_y_param = "ParamAngleY", pos_y_scale = -2.0})
	append(&a.def.layers, Avatar_Layer{name = "hair", kind = "hair", oy = -90, tint = {90, 60, 140, 255}, rot_z_param = "ParamAngleZ", rot_z_scale = 1.2, pos_x_param = "ParamAngleX", pos_x_scale = 3})
	append(&a.def.layers, Avatar_Layer{name = "brow_l", kind = "brow_l", ox = -38, oy = -55, tint = {60, 40, 30, 255}})
	append(&a.def.layers, Avatar_Layer{name = "brow_r", kind = "brow_r", ox = 38, oy = -55, tint = {60, 40, 30, 255}})
	append(&a.def.layers, Avatar_Layer{name = "eye_l", kind = "eye_l", ox = -36, oy = -20, tint = {255, 255, 255, 255}})
	append(&a.def.layers, Avatar_Layer{name = "eye_r", kind = "eye_r", ox = 36, oy = -20, tint = {255, 255, 255, 255}})
	append(&a.def.layers, Avatar_Layer{name = "mouth", kind = "mouth", oy = 40, tint = {200, 80, 100, 255}})
	append(&a.def.layers, Avatar_Layer{name = "blush", kind = "blush", oy = 15, tint = {255, 120, 140, 180}})
	a.loaded = true
	return a
}

// JSON file format for custom layered avatars
Avatar_File :: struct {
	name:   string,
	pos_x:  f32,
	pos_y:  f32,
	scale:  f32,
	// optional single image path (billboard mode + procedural face overlay)
	image:  string,
	layers: []Avatar_Layer_File,
}

Avatar_Layer_File :: struct {
	name:          string,
	texture:       string,
	kind:          string,
	ox:            f32,
	oy:            f32,
	w:             f32,
	h:             f32,
	rot_z_param:   string,
	rot_z_scale:   f32,
	pos_x_param:   string,
	pos_x_scale:   f32,
	pos_y_param:   string,
	pos_y_scale:   f32,
	scale_param:   string,
	scale_amount:  f32,
	visible_param: string,
	tint:          [4]u8,
}

load_avatar :: proc(path: string) -> Avatar {
	data, rerr := os.read_entire_file(path, context.allocator)
	if rerr != nil {
		fmt.println("[avatar] missing", path, "— using procedural default")
		return avatar_default_procedural()
	}
	defer delete(data)

	file: Avatar_File
	if err := json.unmarshal(data, &file); err != nil {
		fmt.println("[avatar] parse error:", err)
		return avatar_default_procedural()
	}

	a: Avatar
	a.def.name = file.name != "" ? file.name : "Loaded"
	a.def.pos_x = file.pos_x
	a.def.pos_y = file.pos_y
	a.def.scale = file.scale != 0 ? file.scale : 1
	a.def.layers = make([dynamic]Avatar_Layer)

	dir := filepath.dir(path)

	if file.image != "" {
		img_path, _ := filepath.join({dir, file.image})
		defer delete(img_path)
		if rl.FileExists(strings.clone_to_cstring(img_path, context.temp_allocator)) {
			a.billboard = rl.LoadTexture(strings.clone_to_cstring(img_path, context.temp_allocator))
			a.has_billboard = a.billboard.id != 0
			fmt.println("[avatar] billboard texture:", img_path)
		}
	}

	if len(file.layers) == 0 && !a.has_billboard {
		// empty file → procedural
		avatar_destroy(&a)
		return avatar_default_procedural()
	}

	for lf in file.layers {
		layer: Avatar_Layer
		layer.name = strings.clone(lf.name)
		layer.texture = strings.clone(lf.texture)
		layer.kind = strings.clone(lf.kind)
		layer.ox = lf.ox
		layer.oy = lf.oy
		layer.w = lf.w
		layer.h = lf.h
		layer.rot_z_param = strings.clone(lf.rot_z_param)
		layer.rot_z_scale = lf.rot_z_scale != 0 ? lf.rot_z_scale : 1
		layer.pos_x_param = strings.clone(lf.pos_x_param)
		layer.pos_x_scale = lf.pos_x_scale
		layer.pos_y_param = strings.clone(lf.pos_y_param)
		layer.pos_y_scale = lf.pos_y_scale
		layer.scale_param = strings.clone(lf.scale_param)
		layer.scale_amount = lf.scale_amount
		layer.visible_param = strings.clone(lf.visible_param)
		layer.tint = lf.tint
		if layer.tint[3] == 0 && layer.tint[0] == 0 && layer.tint[1] == 0 && layer.tint[2] == 0 {
			layer.tint = {255, 255, 255, 255}
		}
		if layer.texture != "" {
			tp, _ := filepath.join({dir, layer.texture})
			cpath := strings.clone_to_cstring(tp, context.temp_allocator)
			if rl.FileExists(cpath) {
				layer.tex = rl.LoadTexture(cpath)
				layer.has_tex = layer.tex.id != 0
			}
			delete(tp)
		}
		append(&a.def.layers, layer)
	}

	// If only image provided, still add procedural face overlay for tracking feedback
	if a.has_billboard && len(a.def.layers) == 0 {
		// keep billboard only
	}

	a.loaded = true
	fmt.println("[avatar] loaded", a.def.name, "layers:", len(a.def.layers))
	return a
}

avatar_destroy :: proc(a: ^Avatar) {
	if a.has_billboard {
		rl.UnloadTexture(a.billboard)
		a.has_billboard = false
	}
	for &layer in a.def.layers {
		if layer.has_tex {
			rl.UnloadTexture(layer.tex)
		}
		delete(layer.name)
		delete(layer.texture)
		delete(layer.kind)
		delete(layer.rot_z_param)
		delete(layer.pos_x_param)
		delete(layer.pos_y_param)
		delete(layer.scale_param)
		delete(layer.visible_param)
	}
	delete(a.def.layers)
	a.loaded = false
}

avatar_draw :: proc(a: Avatar, params: Model_Params, phys: Physics_State, win_w, win_h: i32, user_scale: f32) {
	if !a.loaded {
		return
	}

	cx := f32(win_w) * 0.5 + a.def.pos_x
	cy := f32(win_h) * 0.5 + a.def.pos_y
	base_scale := a.def.scale * user_scale

	angle_x := get_param(params, "ParamAngleX")
	angle_y := get_param(params, "ParamAngleY")
	angle_z := get_param(params, "ParamAngleZ")
	breath := get_param(params, "ParamBreath", 0.5)
	bscale := breathe_scale(breath)

	// Billboard (full character art) with simple 3D-ish fake rotation
	if a.has_billboard {
		tw := f32(a.billboard.width)
		th := f32(a.billboard.height)
		// scale to fit ~70% of height
		fit := (f32(win_h) * 0.75) / th
		sc := fit * base_scale * bscale
		// squash/skew for angle_x/y
		skew_x := angle_x * 0.004
		draw_w := tw * sc * (1.0 - abs_f(angle_x) * 0.003)
		draw_h := th * sc * (1.0 - abs_f(angle_y) * 0.002)
		src := rl.Rectangle{0, 0, tw, th}
		dst := rl.Rectangle{
			cx + angle_x * 2.5 + phys.hair_x.pos * 10 + skew_x * 20,
			cy + angle_y * -2.0 + phys.hair_y.pos * 8,
			draw_w,
			draw_h,
		}
		origin := rl.Vector2{draw_w * 0.5, draw_h * 0.55}
		rot := angle_z + phys.hair_z.pos * 20
		rl.DrawTexturePro(a.billboard, src, dst, origin, rot, rl.WHITE)
	}

	// Layers (procedural or textured)
	for layer in a.def.layers {
		if layer.visible_param != "" {
			if get_param(params, layer.visible_param, 1) < 0.5 {
				continue
			}
		}

		lx := cx + layer.ox * base_scale
		ly := cy + layer.oy * base_scale
		rot: f32 = 0
		sc := base_scale * bscale

		if layer.pos_x_param != "" {
			lx += get_param(params, layer.pos_x_param) * layer.pos_x_scale * base_scale
		}
		if layer.pos_y_param != "" {
			ly += get_param(params, layer.pos_y_param) * layer.pos_y_scale * base_scale
		}
		if layer.rot_z_param != "" {
			rot += get_param(params, layer.rot_z_param) * layer.rot_z_scale
		}
		if layer.scale_param != "" {
			sc *= 1.0 + get_param(params, layer.scale_param) * layer.scale_amount
		}

		// physics extras on hair
		if layer.kind == "hair" || layer.name == "hair" {
			lx += phys.hair_x.pos * 40
			ly += phys.hair_y.pos * 30
			rot += phys.hair_z.pos * 25
		}

		if layer.has_tex {
			tw := f32(layer.tex.width)
			th := f32(layer.tex.height)
			dw := (layer.w > 0 ? layer.w : tw) * sc
			dh := (layer.h > 0 ? layer.h : th) * sc
			src := rl.Rectangle{0, 0, tw, th}
			dst := rl.Rectangle{lx, ly, dw, dh}
			origin := rl.Vector2{dw * 0.5, dh * 0.5}
			col := rl.Color{layer.tint[0], layer.tint[1], layer.tint[2], layer.tint[3]}
			rl.DrawTexturePro(layer.tex, src, dst, origin, rot, col)
		} else {
			draw_procedural_part(layer.kind, lx, ly, rot, sc, params, layer.tint)
		}
	}

	// If we only have billboard, still draw eyes/mouth HUD overlay lightly? skip.
	// If procedural and no billboard, parts already drawn.
	if !a.has_billboard && len(a.def.layers) == 0 {
		// nothing
	}
}

draw_procedural_part :: proc(kind: string, x, y, rot, scale: f32, params: Model_Params, tint: [4]u8) {
	col := rl.Color{tint[0], tint[1], tint[2], tint[3]}
	s := scale

	// apply rotation by transforming around center via Draw* with manual offsets
	// for simplicity most parts ignore rot except head/hair which we approximate
	_ = rot

	switch kind {
	case "body":
		rl.DrawEllipse(i32(x), i32(y), 70 * s, 100 * s, rl.Color{120, 160, 220, 255})
		// neck
		rl.DrawRectangle(i32(x - 18 * s), i32(y - 100 * s), i32(36 * s), i32(50 * s), rl.Color{255, 224, 196, 255})
	case "head":
		rl.DrawCircle(i32(x), i32(y), 90 * s, col)
		// ear L/R
		rl.DrawCircle(i32(x - 85 * s), i32(y), 22 * s, col)
		rl.DrawCircle(i32(x + 85 * s), i32(y), 22 * s, col)
	case "hair":
		rl.DrawEllipse(i32(x), i32(y), 100 * s, 55 * s, col)
		// side bangs
		rl.DrawEllipse(i32(x - 70 * s), i32(y + 40 * s), 28 * s, 55 * s, col)
		rl.DrawEllipse(i32(x + 70 * s), i32(y + 40 * s), 28 * s, 55 * s, col)
	case "eye_l", "eye_r":
		open_p := get_param(params, "ParamEyeLOpen", 1) if kind == "eye_l" else get_param(params, "ParamEyeROpen", 1)
		open_p = clamp(open_p / 1.9, 0, 1) // VTS often maps to ~1.9 max
		ex := get_param(params, "ParamEyeBallX") * 8 * s
		ey := get_param(params, "ParamEyeBallY") * 6 * s
		smile := get_param(params, "ParamEyeLSmile", 0) if kind == "eye_l" else get_param(params, "ParamEyeRSmile", 0)

		ew := 28 * s
		eh := 22 * s * open_p
		if eh < 2 * s {
			// closed line
			rl.DrawLineEx({x - ew, y}, {x + ew, y}, 3 * s, rl.Color{40, 30, 30, 255})
		} else {
			// white
			rl.DrawEllipse(i32(x), i32(y), ew, eh, rl.WHITE)
			// iris
			iris_col := rl.Color{70, 130, 200, 255}
			rl.DrawCircle(i32(x + ex), i32(y + ey), 12 * s * open_p, iris_col)
			rl.DrawCircle(i32(x + ex), i32(y + ey), 6 * s * open_p, rl.Color{20, 20, 30, 255})
			// highlight
			rl.DrawCircle(i32(x + ex - 4 * s), i32(y + ey - 4 * s), 3 * s * open_p, rl.Color{255, 255, 255, 200})
			// smile squint overlay
			if smile > 0.3 {
				rl.DrawEllipse(i32(x), i32(y + eh * 0.3), ew, eh * 0.35, rl.Color{255, 224, 196, u8(smile * 200)})
			}
		}
	case "brow_l", "brow_r":
		by := get_param(params, "ParamBrowLY", 0) if kind == "brow_l" else get_param(params, "ParamBrowRY", 0)
		// -1..1 → offset
		oy := -by * 12 * s
		x0 := x - 20 * s
		x1 := x + 20 * s
		y0 := y + oy
		// slight angle for form
		form := by * 0.15
		rl.DrawLineEx({x0, y0 + form * 10}, {x1, y0 - form * 10}, 4 * s, col)
	case "mouth":
		open := clamp(get_param(params, "ParamMouthOpenY") / 2.3, 0, 1)
		form := get_param(params, "ParamMouthForm") // -1..1
		mx := get_param(params, "ParamMouthX") * 10 * s
		mw := 28 * s + form * 6 * s
		mh := 6 * s + open * 28 * s
		if open < 0.05 {
			// smile/frown line
			curve := form * 10 * s
			rl.DrawLineBezier({x - mw + mx, y - curve * 0.2}, {x + mw + mx, y - curve * 0.2}, 3 * s, col)
			// approximate smile with second point
			_ = curve
			rl.DrawLineEx({x - mw + mx, y}, {x + mx, y + form * 8 * s}, 3 * s, col)
			rl.DrawLineEx({x + mx, y + form * 8 * s}, {x + mw + mx, y}, 3 * s, col)
		} else {
			// open mouth ellipse
			rl.DrawEllipse(i32(x + mx), i32(y), mw, mh, rl.Color{80, 20, 30, 255})
			// teeth
			if open > 0.25 {
				rl.DrawRectangle(i32(x + mx - mw * 0.6), i32(y - mh * 0.5), i32(mw * 1.2), i32(6 * s), rl.Color{255, 255, 250, 255})
			}
			// lips outline
			draw_ellipse_lines(i32(x + mx), i32(y), mw, mh, col)
		}
	case "blush":
		cheek := clamp(get_param(params, "ParamCheek", 0.5), 0, 1)
		alpha := u8(cheek * 160)
		c := rl.Color{tint[0], tint[1], tint[2], alpha}
		rl.DrawEllipse(i32(x - 48 * s), i32(y), 22 * s, 12 * s, c)
		rl.DrawEllipse(i32(x + 48 * s), i32(y), 22 * s, 12 * s, c)
	case:
		// unknown: small debug rect
		rl.DrawRectangle(i32(x - 10), i32(y - 10), 20, 20, col)
	}
}

draw_ellipse_lines :: proc(cx, cy: i32, rx, ry: f32, color: rl.Color) {
	prev_x, prev_y: f32
	for i in 0 ..= 32 {
		ang := f32(i) / 32.0 * math.PI * 2
		px := f32(cx) + math.cos(ang) * rx
		py := f32(cy) + math.sin(ang) * ry
		if i > 0 {
			rl.DrawLineEx({prev_x, prev_y}, {px, py}, 2, color)
		}
		prev_x, prev_y = px, py
	}
}

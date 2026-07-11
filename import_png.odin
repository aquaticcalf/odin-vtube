package main

import "core:fmt"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

// Import art from Krita / MS Paint / any PNG exporter.

is_image_path :: proc(path: string) -> bool {
	ext := strings.to_lower(filepath.ext(path), context.temp_allocator)
	return ext == ".png" || ext == ".jpg" || ext == ".jpeg" || ext == ".bmp"
}

guess_kind_from_filename :: proc(path: string) -> string {
	base := strings.to_lower(filepath.stem(path), context.temp_allocator)
	base = strings.trim_suffix(base, "_layer")
	base = strings.trim_suffix(base, "-layer")

	switch {
	case strings.contains(base, "eye_l") || strings.contains(base, "eye-l") || strings.contains(base, "lefteye") || base == "eye_left" || base == "l_eye":
		return "eye_l"
	case strings.contains(base, "eye_r") || strings.contains(base, "eye-r") || strings.contains(base, "righteye") || base == "eye_right" || base == "r_eye":
		return "eye_r"
	case strings.contains(base, "brow_l") || strings.contains(base, "brow-l") || base == "left_brow":
		return "brow_l"
	case strings.contains(base, "brow_r") || strings.contains(base, "brow-r") || base == "right_brow":
		return "brow_r"
	case strings.contains(base, "mouth") || strings.contains(base, "lips"):
		return "mouth"
	case strings.contains(base, "hair") || strings.contains(base, "bangs"):
		return "hair"
	case strings.contains(base, "blush") || strings.contains(base, "cheek"):
		return "blush"
	case strings.contains(base, "body") || strings.contains(base, "torso"):
		return "body"
	case strings.contains(base, "head") || strings.contains(base, "face"):
		return "head"
	case strings.contains(base, "full") || strings.contains(base, "character") || strings.contains(base, "avatar") || strings.contains(base, "billboard") || base == "model" || base == "all":
		return "billboard"
	}
	return "sprite"
}

// Copy image into <model_dir>/textures/<filename>. Returns relative "textures/name.png".
import_copy_texture_into_model_dir :: proc(src_path, model_json_path: string) -> (rel: string, ok: bool) {
	model_dir := filepath.dir(model_json_path)
	tex_dir, jerr := filepath.join({model_dir, "textures"})
	if jerr != nil do return "", false
	defer delete(tex_dir)

	_ = os.make_directory(model_dir)
	_ = os.make_directory(tex_dir)

	base := filepath.base(src_path)
	if base == "" || base == "." || base == "/" || base == "\\" {
		base = "layer.png"
	}

	dest, derr := filepath.join({tex_dir, base})
	if derr != nil do return "", false
	defer delete(dest)

	src_data, rerr := os.read_entire_file(src_path, context.allocator)
	if rerr != nil {
		fmt.println("[import] cannot read", src_path)
		return "", false
	}
	defer delete(src_data)

	if werr := os.write_entire_file(dest, src_data); werr != nil {
		fmt.println("[import] cannot write", dest)
		return "", false
	}

	rel_out, rerr2 := filepath.join({"textures", base})
	if rerr2 != nil do return "", false
	return rel_out, true
}

layer_set_texture_from_file :: proc(layer: ^Avatar_Layer, src_path, model_json_path: string) -> bool {
	rel, ok := import_copy_texture_into_model_dir(src_path, model_json_path)
	load_path: string
	owned_load := false

	if ok {
		delete(layer.texture)
		layer.texture = rel
		model_dir := filepath.dir(model_json_path)
		load_path, _ = filepath.join({model_dir, layer.texture})
		owned_load = true
	} else {
		// fall back to original path
		delete(layer.texture)
		layer.texture = av_str(src_path)
		load_path = src_path
	}
	if owned_load {
		defer delete(load_path)
	}

	if layer.has_tex {
		rl.UnloadTexture(layer.tex)
		layer.has_tex = false
	}

	cpath := strings.clone_to_cstring(load_path, context.temp_allocator)
	if !rl.FileExists(cpath) {
		fmt.println("[import] missing", load_path)
		return false
	}
	layer.tex = rl.LoadTexture(cpath)
	layer.has_tex = layer.tex.id != 0
	if !layer.has_tex do return false

	tw := f32(layer.tex.width)
	th := f32(layer.tex.height)
	if tw > 512 {
		layer.w = 512
		layer.h = 512 * th / tw
	} else {
		layer.w = 0
		layer.h = 0
	}
	return true
}

import_png_as_billboard :: proc(a: ^Avatar, png_path, model_json_path: string) -> bool {
	rel, ok := import_copy_texture_into_model_dir(png_path, model_json_path)
	load_path := png_path
	owned := false
	if ok {
		delete(a.def.image)
		a.def.image = rel
		model_dir := filepath.dir(model_json_path)
		load_path, _ = filepath.join({model_dir, a.def.image})
		owned = true
	}
	if owned {
		defer delete(load_path)
	}

	if a.has_billboard {
		rl.UnloadTexture(a.billboard)
		a.has_billboard = false
	}
	cpath := strings.clone_to_cstring(load_path, context.temp_allocator)
	if !rl.FileExists(cpath) do return false
	a.billboard = rl.LoadTexture(cpath)
	a.has_billboard = a.billboard.id != 0
	return a.has_billboard
}

// Returns new layer index, -1 if billboard, -2 on failure
import_png_as_new_layer :: proc(a: ^Avatar, png_path, model_json_path: string) -> int {
	kind := guess_kind_from_filename(png_path)
	if kind == "billboard" {
		if import_png_as_billboard(a, png_path, model_json_path) {
			return -1
		}
		return -2
	}

	stem := filepath.stem(png_path)
	layer_kind := kind
	layer := make_layer(stem, layer_kind, 0, 0, {255, 255, 255, 255})

	if kind == "head" || kind == "hair" {
		delete(layer.rot_z_param)
		delete(layer.pos_x_param)
		delete(layer.pos_y_param)
		layer.rot_z_param = av_str("ParamAngleZ")
		layer.rot_z_scale = kind == "hair" ? 1.2 : 1
		layer.pos_x_param = av_str("ParamAngleX")
		layer.pos_x_scale = kind == "hair" ? 3 : 2.5
		layer.pos_y_param = av_str("ParamAngleY")
		layer.pos_y_scale = -2
		if kind == "hair" do layer.oy = -40
	} else if kind == "body" {
		delete(layer.rot_z_param)
		delete(layer.pos_x_param)
		layer.rot_z_param = av_str("ParamBodyAngleZ")
		layer.rot_z_scale = 0.4
		layer.pos_x_param = av_str("ParamBodyAngleX")
		layer.pos_x_scale = 1.2
		layer.oy = 80
	} else if kind == "eye_l" {
		layer.ox, layer.oy = -36, -20
	} else if kind == "eye_r" {
		layer.ox, layer.oy = 36, -20
	} else if kind == "mouth" {
		layer.oy = 40
	} else if kind == "brow_l" {
		layer.ox, layer.oy = -38, -55
	} else if kind == "brow_r" {
		layer.ox, layer.oy = 38, -55
	} else if kind == "blush" {
		layer.oy = 15
	}

	if !layer_set_texture_from_file(&layer, png_path, model_json_path) {
		avatar_layer_free_strings(&layer)
		return -2
	}
	append(&a.def.layers, layer)
	return len(a.def.layers) - 1
}

import_png_onto_selected :: proc(a: ^Avatar, selected: int, png_path, model_json_path: string) -> bool {
	if selected < 0 || selected >= len(a.def.layers) do return false
	return layer_set_texture_from_file(&a.def.layers[selected], png_path, model_json_path)
}

import_folder_pngs :: proc(a: ^Avatar, folder, model_json_path: string) -> int {
	if !os.exists(folder) do return 0
	cfold := strings.clone_to_cstring(folder, context.temp_allocator)
	list := rl.LoadDirectoryFilesEx(cfold, ".png", false)
	defer rl.UnloadDirectoryFiles(list)

	n := 0
	if list.paths == nil || list.count == 0 do return 0
	for i in 0 ..< int(list.count) {
		p := string(list.paths[i])
		if !is_image_path(p) do continue
		idx := import_png_as_new_layer(a, p, model_json_path)
		if idx >= -1 do n += 1
	}
	return n
}

// Handle OS drag-and-drop into the window while editor is open.
editor_handle_file_drops :: proc(e: ^Model_Editor, a: ^Avatar) {
	if !e.active do return
	if !rl.IsFileDropped() do return

	list := rl.LoadDroppedFiles()
	defer rl.UnloadDroppedFiles(list)
	if list.count == 0 do return

	shift := rl.IsKeyDown(.LEFT_SHIFT) || rl.IsKeyDown(.RIGHT_SHIFT)
	added := 0
	for i in 0 ..< int(list.count) {
		p := string(list.paths[i])
		if !is_image_path(p) {
			// if directory, import all pngs
			if os.is_directory(p) {
				n := import_folder_pngs(a, p, e.save_path)
				added += n
				continue
			}
			continue
		}
		if shift && e.selected >= 0 && e.selected < len(a.def.layers) {
			if import_png_onto_selected(a, e.selected, p, e.save_path) {
				added += 1
				editor_set_status(e, "Replaced texture on selected layer")
			}
		} else {
			idx := import_png_as_new_layer(a, p, e.save_path)
			if idx >= 0 {
				e.selected = idx
				added += 1
			} else if idx == -1 {
				added += 1
				editor_set_status(e, "Imported full-body billboard PNG")
			}
		}
	}
	if added > 0 && e.status_timer <= 0 {
		editor_set_status(e, fmt.tprintf("Imported %d image(s) — Ctrl+S to save", added))
	}
}

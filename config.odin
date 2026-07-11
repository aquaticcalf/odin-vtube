package main

import "core:encoding/json"
import "core:fmt"
import "core:os"

App_Config :: struct {
	window_width:  i32,
	window_height: i32,
	window_title:  string,
	target_fps:    i32,
	bg_color:      [4]u8,
	show_hud:      bool,
	api_enabled:   bool,
	api_port:      int,
	tracking_mode: string,
	model_path:    string,
	background:    string,
	avatar_scale:  f32,
	chroma_key:    bool,
	chroma_color:  [4]u8,
}

default_config :: proc() -> App_Config {
	return App_Config{
		window_width  = 1280,
		window_height = 720,
		window_title  = "OdinVTube — local only",
		target_fps    = 60,
		bg_color      = {30, 32, 48, 255},
		show_hud      = true,
		api_enabled   = true,
		api_port      = 8001,
		tracking_mode = "mouse",
		model_path    = "assets/models/default/avatar.json",
		background    = "",
		avatar_scale  = 1.0,
		chroma_key    = false,
		chroma_color  = {0, 255, 0, 255},
	}
}

load_config :: proc(path: string) -> App_Config {
	cfg := default_config()
	data, err := os.read_entire_file(path, context.allocator)
	if err != nil {
		fmt.println("[config] using defaults (no file at", path, ")")
		return cfg
	}
	defer delete(data)

	if jerr := json.unmarshal(data, &cfg); jerr != nil {
		fmt.println("[config] parse error:", jerr, "— using defaults")
		return default_config()
	}
	fmt.println("[config] loaded", path)
	return cfg
}

save_config :: proc(path: string, cfg: App_Config) -> bool {
	data, err := json.marshal(cfg, {pretty = true})
	if err != nil {
		fmt.println("[config] marshal error:", err)
		return false
	}
	defer delete(data)
	werr := os.write_entire_file(path, data)
	if werr != nil {
		fmt.println("[config] write failed:", path, werr)
		return false
	}
	return true
}

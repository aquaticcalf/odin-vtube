package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:path/filepath"
import "core:strings"
import rl "vendor:raylib"

/*
	OdinVTube — clean-room local VTuber avatar app.

	Inspired by public VTube Studio concepts (parameter names, mapping ranges,
	local plugin API message types) but 100% original code. No Steam, no
	telemetry, no watermark, no network except optional localhost plugin API.

	Build (from this folder):
	  odin build . -out:odin-vtube.exe -collection:shared=./

	Or use build.bat
*/

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		context.allocator = mem.tracking_allocator(&track)
		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("[leak] %d allocations not freed\n", len(track.allocation_map))
			}
			mem.tracking_allocator_destroy(&track)
		}
	}

	// Prefer config next to cwd
	cfg_path := "configs/default.json"
	if !os.exists(cfg_path) {
		_ = os.make_directory("configs")
		save_config(cfg_path, default_config())
	}
	cfg := load_config(cfg_path)

	rl.SetConfigFlags({.WINDOW_RESIZABLE, .VSYNC_HINT})
	rl.InitWindow(cfg.window_width, cfg.window_height, strings.clone_to_cstring(cfg.window_title, context.temp_allocator))
	defer rl.CloseWindow()
	rl.SetTargetFPS(cfg.target_fps)
	rl.SetExitKey(rl.KeyboardKey(0)) // we handle Esc ourselves

	// Systems
	tracker := tracker_init(cfg.tracking_mode)
	defer tracker_destroy(&tracker)

	rules := default_param_rules()
	defer delete(rules)

	model: Model_Params
	model_params_init(&model)
	defer model_params_destroy(&model)

	phys := physics_init()
	exprs := expressions_init()
	defer expressions_destroy(&exprs)

	hot := hotkeys_init()
	defer hotkeys_destroy(&hot)

	avatar := load_avatar(cfg.model_path)
	defer avatar_destroy(&avatar)

	bg_tex: rl.Texture2D
	has_bg := false
	if cfg.background != "" && os.exists(cfg.background) {
		bg_tex = rl.LoadTexture(strings.clone_to_cstring(cfg.background, context.temp_allocator))
		has_bg = bg_tex.id != 0
	}
	defer if has_bg do rl.UnloadTexture(bg_tex)

	api: ^Plugin_API
	if cfg.api_enabled {
		api = api_init(cfg.api_port, true)
	}
	defer if api != nil do api_shutdown(api)

	show_hud := cfg.show_hud
	chroma := cfg.chroma_key
	user_scale := cfg.avatar_scale
	running := true

	fmt.println("========================================")
	fmt.println(" OdinVTube — fully local VTuber runtime")
	fmt.println(" No Steam · No cloud · No watermark")
	fmt.println("========================================")
	fmt.println("Model:", avatar.def.name)
	if api != nil && api.enabled {
		fmt.println("Plugin API: 127.0.0.1:", cfg.api_port, "(TCP JSON lines)")
	}

	for running && !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		if dt > 0.1 do dt = 0.1
		win_w := rl.GetScreenWidth()
		win_h := rl.GetScreenHeight()

		// Hotkeys
		hotkeys_update(&hot)
		for action in hot.fired {
			switch action {
			case .Toggle_HUD:
				show_hud = !show_hud
			case .Tracking_Mouse:
				tracker_set_mode(&tracker, .Mouse)
				fmt.println("[track] mouse")
			case .Tracking_Idle:
				tracker_set_mode(&tracker, .Idle)
				fmt.println("[track] idle")
			case .Tracking_Demo:
				tracker_set_mode(&tracker, .Demo)
				fmt.println("[track] demo")
			case .Expr_Happy:
				expressions_toggle(&exprs, "happy")
			case .Expr_Angry:
				expressions_toggle(&exprs, "angry")
			case .Expr_Sad:
				expressions_toggle(&exprs, "sad")
			case .Expr_Shock:
				expressions_toggle(&exprs, "shock")
			case .Expr_Clear:
				expressions_set(&exprs, "happy", false)
				expressions_set(&exprs, "angry", false)
				expressions_set(&exprs, "sad", false)
				expressions_set(&exprs, "shock", false)
			case .Physics_Toggle:
				phys.enabled = !phys.enabled
				fmt.println("[phys]", phys.enabled)
			case .Chroma_Toggle:
				chroma = !chroma
				fmt.println("[chroma]", chroma)
			case .Reset_Pose:
				tracker.state.FaceAngleX = 0
				tracker.state.FaceAngleY = 0
				tracker.state.FaceAngleZ = 0
				tracker.state.MouthOpen = 0
				tracker.state.MouthSmile = 0
			case .Quit:
				running = false
			case .None, .Toggle_API_Info:
			}
		}

		// Zoom with mouse wheel
		wheel := rl.GetMouseWheelMove()
		if wheel != 0 {
			user_scale = clamp(user_scale + wheel * 0.05, 0.3, 3.0)
		}

		// Tracking → mappings → expressions → physics
		tracker_update(&tracker, dt, win_w, win_h)

		// Plugin injects into tracking/params
		if api != nil {
			api_apply_injects(api, &tracker.state, &model)
		}

		apply_mappings(rules[:], tracker.state, &model, dt)
		expressions_update(&exprs, &model, dt)

		ax := get_param(model, "ParamAngleX")
		ay := get_param(model, "ParamAngleY")
		az := get_param(model, "ParamAngleZ")
		physics_update(&phys, ax, ay, az, dt)

		if api != nil {
			api_sync_from_app(api, tracker.state, model, avatar.def.name)
		}

		// Draw
		bg: rl.Color
		if chroma {
			bg = rl.Color{cfg.chroma_color[0], cfg.chroma_color[1], cfg.chroma_color[2], cfg.chroma_color[3]}
		} else {
			bg = rl.Color{cfg.bg_color[0], cfg.bg_color[1], cfg.bg_color[2], cfg.bg_color[3]}
		}
		rl.BeginDrawing()
		rl.ClearBackground(bg)

		if has_bg && !chroma {
			// cover
			src := rl.Rectangle{0, 0, f32(bg_tex.width), f32(bg_tex.height)}
			dst := rl.Rectangle{0, 0, f32(win_w), f32(win_h)}
			rl.DrawTexturePro(bg_tex, src, dst, {0, 0}, 0, rl.WHITE)
		}

		avatar_draw(avatar, model, phys, win_w, win_h, user_scale)

		hud_draw(
			show_hud,
			cfg,
			tracker.state,
			model,
			tracker.mode,
			phys.enabled,
			cfg.api_port,
			api != nil && api.enabled,
			avatar.def.name,
			f32(rl.GetFPS()),
		)

		rl.EndDrawing()
	}

	fmt.println("[odin-vtube] bye")
}

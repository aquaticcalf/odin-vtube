package main

import "core:fmt"
import "core:mem"
import "core:os"
import "core:strings"
import rl "vendor:raylib"

/*
	OdinVTube — local avatar runtime + model editor + OBS mode.

	Build:
	  odin build . -out:odin-vtube.exe
	  build.bat
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
	rl.SetExitKey(rl.KeyboardKey(0))

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

	editor := editor_init(cfg.model_path)
	defer editor_destroy(&editor)

	obs := obs_mode_init()

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
	fmt.println(" OdinVTube")
	fmt.println(" F5 model editor · F9 OBS mode")
	fmt.println("========================================")
	fmt.println("Model:", avatar.def.name)
	if api != nil && api.enabled {
		fmt.println("Plugin API: 127.0.0.1:", cfg.api_port)
	}

	for running && !rl.WindowShouldClose() {
		dt := rl.GetFrameTime()
		if dt > 0.1 do dt = 0.1
		win_w := rl.GetScreenWidth()
		win_h := rl.GetScreenHeight()

		hotkeys_update(&hot)
		for action in hot.fired {
			switch action {
			case .Toggle_HUD:
				show_hud = !show_hud
			case .Tracking_Mouse:
				tracker_set_mode(&tracker, .Mouse)
			case .Tracking_Idle:
				tracker_set_mode(&tracker, .Idle)
			case .Tracking_Demo:
				tracker_set_mode(&tracker, .Demo)
			case .Expr_Happy:
				if !editor.active do expressions_toggle(&exprs, "happy")
			case .Expr_Angry:
				if !editor.active do expressions_toggle(&exprs, "angry")
			case .Expr_Sad:
				if !editor.active do expressions_toggle(&exprs, "sad")
			case .Expr_Shock:
				if !editor.active do expressions_toggle(&exprs, "shock")
			case .Expr_Clear:
				if !editor.active {
					expressions_set(&exprs, "happy", false)
					expressions_set(&exprs, "angry", false)
					expressions_set(&exprs, "sad", false)
					expressions_set(&exprs, "shock", false)
				}
			case .Physics_Toggle:
				phys.enabled = !phys.enabled
			case .Chroma_Toggle:
				if !obs.active do chroma = !chroma
			case .Toggle_Editor:
				// leave OBS if entering editor
				if !editor.active && obs.active {
					obs_mode_toggle(&obs, &chroma, &show_hud)
				}
				editor_toggle(&editor)
			case .Toggle_OBS:
				if editor.active do editor_toggle(&editor)
				obs_mode_toggle(&obs, &chroma, &show_hud)
			case .Reset_Pose:
				tracker.state.FaceAngleX = 0
				tracker.state.FaceAngleY = 0
				tracker.state.FaceAngleZ = 0
				tracker.state.MouthOpen = 0
				tracker.state.MouthSmile = 0
			case .Quit:
				if editor.active {
					editor_toggle(&editor)
				} else if obs.active {
					obs_mode_toggle(&obs, &chroma, &show_hud)
				} else {
					running = false
				}
			case .None, .Toggle_API_Info:
			}
		}

		// Zoom (not when over editor panel)
		if !editor.active || rl.GetMouseX() < win_w - i32(editor.panel_w) {
			wheel := rl.GetMouseWheelMove()
			if wheel != 0 {
				user_scale = clamp(user_scale + wheel * 0.05, 0.3, 3.0)
			}
		}

		tracker_update(&tracker, dt, win_w, win_h)

		if api != nil {
			api_apply_injects(api, &tracker.state, &model)
		}

		apply_mappings(rules[:], tracker.state, &model, dt)
		if !editor.active {
			expressions_update(&exprs, &model, dt)
		}

		ax := get_param(model, "ParamAngleX")
		ay := get_param(model, "ParamAngleY")
		az := get_param(model, "ParamAngleZ")
		physics_update(&phys, ax, ay, az, dt)

		if api != nil {
			api_sync_from_app(api, tracker.state, model, avatar.def.name)
		}

		// Background
		bg: rl.Color
		if chroma || obs.active {
			kc := obs.active ? obs.key_color : cfg.chroma_color
			bg = rl.Color{kc[0], kc[1], kc[2], kc[3]}
		} else {
			bg = rl.Color{cfg.bg_color[0], cfg.bg_color[1], cfg.bg_color[2], cfg.bg_color[3]}
		}

		rl.BeginDrawing()
		rl.ClearBackground(bg)

		if has_bg && !chroma && !obs.active {
			src := rl.Rectangle{0, 0, f32(bg_tex.width), f32(bg_tex.height)}
			dst := rl.Rectangle{0, 0, f32(win_w), f32(win_h)}
			rl.DrawTexturePro(bg_tex, src, dst, {0, 0}, 0, rl.WHITE)
		}

		avatar_draw(avatar, model, phys, win_w, win_h, user_scale)

		if editor.active {
			editor_update_draw(&editor, &avatar, model, phys, win_w, win_h, user_scale, dt)
		} else {
			if show_hud {
				hud_draw(
					true,
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
			}
			obs_mode_draw_hint(obs, win_w, win_h)
		}

		rl.EndDrawing()
	}

	fmt.println("[odin-vtube] bye")
}

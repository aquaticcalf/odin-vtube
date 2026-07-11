package main

import "core:fmt"
import rl "vendor:raylib"

hud_draw :: proc(
	show: bool,
	cfg: App_Config,
	track: Tracking_Inputs,
	params: Model_Params,
	tracker_mode: Tracking_Mode,
	phys_on: bool,
	api_port: int,
	api_on: bool,
	model_name: string,
	fps: f32,
) {
	if !show do return

	// panel
	rl.DrawRectangle(8, 8, 340, 420, rl.Color{0, 0, 0, 160})
	rl.DrawRectangleLines(8, 8, 340, 420, rl.Color{100, 180, 255, 200})

	y: i32 = 16
	line :: proc(text: cstring, y: ^i32, color: rl.Color = rl.RAYWHITE) {
		rl.DrawText(text, 18, y^, 16, color)
		y^ += 18
	}

	line(fmt.ctprintf("OdinVTube  %.0f FPS", fps), &y, rl.Color{120, 220, 255, 255})
	line(fmt.ctprintf("model: %s", model_name), &y)
	mode_s := "mouse"
	switch tracker_mode {
	case .Mouse:
		mode_s = "mouse"
	case .Idle:
		mode_s = "idle"
	case .Demo:
		mode_s = "demo"
	}
	line(fmt.ctprintf("tracking: %s", mode_s), &y, rl.Color{180, 255, 180, 255})
	phys_s := phys_on ? "on" : "off"
	api_s := api_on ? "on" : "off"
	line(fmt.ctprintf("physics: %s  api: %s :%d", phys_s, api_s, api_port), &y)
	line("— tracking inputs —", &y, rl.Color{200, 200, 100, 255})
	line(fmt.ctprintf("FaceAngle X/Y/Z  %.1f  %.1f  %.1f", track.FaceAngleX, track.FaceAngleY, track.FaceAngleZ), &y)
	line(fmt.ctprintf("Eyes open L/R    %.2f  %.2f", track.EyeOpenLeft, track.EyeOpenRight), &y)
	line(fmt.ctprintf("Mouth open/smile %.2f  %.2f", track.MouthOpen, track.MouthSmile), &y)
	line(fmt.ctprintf("Breath           %.2f", track.Breath), &y)
	line("— model params —", &y, rl.Color{200, 200, 100, 255})
	line(fmt.ctprintf("ParamAngleX/Y/Z  %.1f  %.1f  %.1f",
		get_param(params, "ParamAngleX"),
		get_param(params, "ParamAngleY"),
		get_param(params, "ParamAngleZ")), &y)
	line(fmt.ctprintf("MouthOpenY/Form  %.2f  %.2f",
		get_param(params, "ParamMouthOpenY"),
		get_param(params, "ParamMouthForm")), &y)

	y += 6
	line("— hotkeys —", &y, rl.Color{200, 200, 100, 255})
	for s in HOTKEY_HELP {
		line(fmt.ctprintf("%s", s), &y, rl.Color{200, 200, 200, 255})
	}

	// watermark-free badge
	rl.DrawText("LOCAL ONLY — no Steam, no cloud, no watermark", 18, cfg.window_height - 28, 16, rl.Color{100, 255, 160, 220})
}

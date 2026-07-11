package main

import rl "vendor:raylib"

Hotkey_Action :: enum {
	None,
	Toggle_HUD,
	Toggle_API_Info,
	Tracking_Mouse,
	Tracking_Idle,
	Tracking_Demo,
	Expr_Happy,
	Expr_Angry,
	Expr_Sad,
	Expr_Shock,
	Expr_Clear,
	Reset_Pose,
	Physics_Toggle,
	Chroma_Toggle,
	Quit,
}

Hotkey_System :: struct {
	fired: [dynamic]Hotkey_Action,
}

hotkeys_init :: proc() -> Hotkey_System {
	return Hotkey_System{fired = make([dynamic]Hotkey_Action)}
}

hotkeys_destroy :: proc(h: ^Hotkey_System) {
	delete(h.fired)
}

hotkeys_update :: proc(h: ^Hotkey_System) {
	clear(&h.fired)

	if rl.IsKeyPressed(.F1) {
		append(&h.fired, Hotkey_Action.Toggle_HUD)
	}
	if rl.IsKeyPressed(.F2) {
		append(&h.fired, Hotkey_Action.Tracking_Mouse)
	}
	if rl.IsKeyPressed(.F3) {
		append(&h.fired, Hotkey_Action.Tracking_Idle)
	}
	if rl.IsKeyPressed(.F4) {
		append(&h.fired, Hotkey_Action.Tracking_Demo)
	}
	if rl.IsKeyPressed(.ONE) {
		append(&h.fired, Hotkey_Action.Expr_Happy)
	}
	if rl.IsKeyPressed(.TWO) {
		append(&h.fired, Hotkey_Action.Expr_Angry)
	}
	if rl.IsKeyPressed(.THREE) {
		append(&h.fired, Hotkey_Action.Expr_Sad)
	}
	if rl.IsKeyPressed(.FOUR) {
		append(&h.fired, Hotkey_Action.Expr_Shock)
	}
	if rl.IsKeyPressed(.ZERO) {
		append(&h.fired, Hotkey_Action.Expr_Clear)
	}
	if rl.IsKeyPressed(.P) {
		append(&h.fired, Hotkey_Action.Physics_Toggle)
	}
	if rl.IsKeyPressed(.C) && rl.IsKeyDown(.LEFT_CONTROL) {
		append(&h.fired, Hotkey_Action.Chroma_Toggle)
	}
	if rl.IsKeyPressed(.R) && rl.IsKeyDown(.LEFT_CONTROL) {
		append(&h.fired, Hotkey_Action.Reset_Pose)
	}
	if rl.IsKeyPressed(.ESCAPE) {
		append(&h.fired, Hotkey_Action.Quit)
	}
}

HOTKEY_HELP := [10]string{
	"F1  toggle HUD",
	"F2  mouse tracking",
	"F3  idle tracking",
	"F4  demo animation",
	"1-4 expressions  0 clear",
	"Space mouth  S smile  W brows",
	"Q/E roll  B blink",
	"P physics  Ctrl+C chroma",
	"Ctrl+R reset  Esc quit",
	"Move mouse = look around",
}

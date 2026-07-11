package main

import "core:math"
import rl "vendor:raylib"

// Tracking backends — completely local. No network.

Tracking_Mode :: enum {
	Mouse,
	Idle,
	Demo, // idle + gentle auto animation
}

Tracker :: struct {
	mode:          Tracking_Mode,
	state:         Tracking_Inputs,
	// blink
	blink_timer:   f32,
	blink_phase:   f32, // 0 idle, >0 blinking
	// breath
	time:          f32,
	// mouse smoothing
	smooth_x:      f32,
	smooth_y:      f32,
	// demo
	demo_phase:    f32,
}

tracker_init :: proc(mode_name: string) -> Tracker {
	t: Tracker
	t.state = default_tracking()
	switch mode_name {
	case "idle":
		t.mode = .Idle
	case "demo":
		t.mode = .Demo
	case:
		t.mode = .Mouse
	}
	t.blink_timer = 2.5
	return t
}

tracker_destroy :: proc(t: ^Tracker) {
	destroy_tracking(&t.state)
}

tracker_set_mode :: proc(t: ^Tracker, mode: Tracking_Mode) {
	t.mode = mode
}

// Called every frame. window size used for mouse normalize.
tracker_update :: proc(t: ^Tracker, dt: f32, win_w, win_h: i32) {
	t.time += dt

	// Breath always
	t.state.Breath = 0.5 + 0.5 * math.sin(t.time * 1.4)

	// Auto blink
	t.blink_timer -= dt
	if t.blink_phase > 0 {
		t.blink_phase -= dt
		// triangle close/open ~0.12s
		p := 1.0 - abs(t.blink_phase - 0.06) / 0.06
		p = clamp(p, 0, 1)
		open := 1.0 - p
		t.state.EyeOpenLeft = open
		t.state.EyeOpenRight = open
		if t.blink_phase <= 0 {
			t.state.EyeOpenLeft = 1
			t.state.EyeOpenRight = 1
			t.blink_timer = 2.0 + f32(rl.GetRandomValue(0, 250)) / 100.0
		}
	} else if t.blink_timer <= 0 {
		t.blink_phase = 0.12
	}

	switch t.mode {
	case .Mouse:
		tracker_mouse(t, dt, win_w, win_h)
	case .Idle:
		// keep defaults + breath + blink; zero head
		t.state.FaceAngleX = apply_smoothing(t.state.FaceAngleX, 0, 20, dt)
		t.state.FaceAngleY = apply_smoothing(t.state.FaceAngleY, 0, 20, dt)
		t.state.FaceAngleZ = apply_smoothing(t.state.FaceAngleZ, 0, 20, dt)
		tracker_keyboard_modifiers(t, dt)
	case .Demo:
		tracker_demo(t, dt)
		tracker_keyboard_modifiers(t, dt)
	}

	// Manual overrides that work in all modes
	tracker_keyboard_modifiers(t, dt)
}

tracker_mouse :: proc(t: ^Tracker, dt: f32, win_w, win_h: i32) {
	m := rl.GetMousePosition()
	cx := f32(win_w) * 0.5
	cy := f32(win_h) * 0.5
	// normalize -1..1-ish
	nx := (m.x - cx) / (f32(win_w) * 0.5)
	ny := (m.y - cy) / (f32(win_h) * 0.5)
	nx = clamp(nx, -1.2, 1.2)
	ny = clamp(ny, -1.2, 1.2)

	t.smooth_x = apply_smoothing(t.smooth_x, nx, 8, dt)
	t.smooth_y = apply_smoothing(t.smooth_y, ny, 8, dt)

	// Map to face angles similar to VTS webcam ranges
	t.state.FaceAngleX = t.smooth_x * 30
	t.state.FaceAngleY = -t.smooth_y * 20
	// slight auto roll with X
	t.state.FaceAngleZ = t.smooth_x * -8

	// Eyes look toward mouse
	t.state.EyeLeftX = t.smooth_x
	t.state.EyeLeftY = -t.smooth_y
	t.state.EyeRightX = t.smooth_x
	t.state.EyeRightY = -t.smooth_y
}

tracker_demo :: proc(t: ^Tracker, dt: f32) {
	t.demo_phase += dt
	t.state.FaceAngleX = math.sin(t.demo_phase * 0.7) * 18
	t.state.FaceAngleY = math.sin(t.demo_phase * 0.5) * 10
	t.state.FaceAngleZ = math.sin(t.demo_phase * 0.9) * 8
	t.state.MouthSmile = 0.4 + 0.3 * math.sin(t.demo_phase * 0.3)
	t.state.MouthOpen = max(0, math.sin(t.demo_phase * 2.5) * 0.35)
	t.state.EyeLeftX = math.sin(t.demo_phase * 0.6) * 0.4
	t.state.EyeRightX = t.state.EyeLeftX
	t.state.EyeLeftY = math.sin(t.demo_phase * 0.4) * 0.2
	t.state.EyeRightY = t.state.EyeLeftY
}

// Hold keys for mouth / smile / brows / roll (local only).
tracker_keyboard_modifiers :: proc(t: ^Tracker, dt: f32) {
	// Space = mouth open
	if rl.IsKeyDown(.SPACE) {
		t.state.MouthOpen = apply_smoothing(t.state.MouthOpen, 1, 5, dt)
	} else if t.mode == .Mouse || t.mode == .Idle {
		t.state.MouthOpen = apply_smoothing(t.state.MouthOpen, 0, 8, dt)
	}

	// S = smile
	if rl.IsKeyDown(.S) && !rl.IsKeyDown(.LEFT_CONTROL) {
		t.state.MouthSmile = apply_smoothing(t.state.MouthSmile, 1, 5, dt)
	} else if t.mode == .Mouse || t.mode == .Idle {
		t.state.MouthSmile = apply_smoothing(t.state.MouthSmile, 0, 10, dt)
	}

	// Q / E roll
	if rl.IsKeyDown(.Q) {
		t.state.FaceAngleZ = apply_smoothing(t.state.FaceAngleZ, 25, 10, dt)
	} else if rl.IsKeyDown(.E) {
		t.state.FaceAngleZ = apply_smoothing(t.state.FaceAngleZ, -25, 10, dt)
	}

	// Brows up: W
	if rl.IsKeyDown(.W) {
		t.state.BrowLeftY = apply_smoothing(t.state.BrowLeftY, 1, 8, dt)
		t.state.BrowRightY = apply_smoothing(t.state.BrowRightY, 1, 8, dt)
	} else {
		t.state.BrowLeftY = apply_smoothing(t.state.BrowLeftY, 0.5, 12, dt)
		t.state.BrowRightY = apply_smoothing(t.state.BrowRightY, 0.5, 12, dt)
	}

	// Manual blink: B
	if rl.IsKeyPressed(.B) {
		t.blink_phase = 0.12
	}
}

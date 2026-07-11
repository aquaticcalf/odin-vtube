package main

import "core:fmt"
import rl "vendor:raylib"

// OBS Mode — capture-friendly out of the box (no Spout/NDI required).
// Uses borderless window + solid chroma key. OBS: Window Capture → Chroma Key.

OBS_Mode :: struct {
	active:          bool,
	// restore
	prev_w, prev_h:  i32,
	prev_x, prev_y:  i32,
	// chroma for keying
	key_color:       [4]u8,
	// hide UI chrome
	hide_hud:        bool,
}

obs_mode_init :: proc() -> OBS_Mode {
	return OBS_Mode{
		active    = false,
		key_color = {0, 255, 0, 255}, // classic green
		hide_hud  = true,
	}
}

obs_mode_toggle :: proc(o: ^OBS_Mode, chroma: ^bool, show_hud: ^bool) {
	if !o.active {
		// enter
		o.prev_w = rl.GetScreenWidth()
		o.prev_h = rl.GetScreenHeight()
		wp := rl.GetWindowPosition()
		o.prev_x = i32(wp.x)
		o.prev_y = i32(wp.y)

		rl.SetWindowState({.WINDOW_UNDECORATED, .WINDOW_TOPMOST})
		// Clean 16:9 capture size common for streams
		rl.SetWindowSize(1280, 720)
		// Center on current monitor roughly
		mon := rl.GetCurrentMonitor()
		mw := rl.GetMonitorWidth(mon)
		mh := rl.GetMonitorHeight(mon)
		rl.SetWindowPosition((mw - 1280) / 2, (mh - 720) / 2)

		rl.SetWindowTitle("OdinVTube OBS")
		chroma^ = true
		if o.hide_hud do show_hud^ = false
		o.active = true
		fmt.println("[obs] ON — borderless 1280x720, green key, topmost")
		fmt.println("[obs] OBS Studio: Sources → Window Capture → select 'OdinVTube OBS'")
		fmt.println("[obs]            Filters → Chroma Key → Key Color Type: Green")
	} else {
		// leave
		rl.ClearWindowState({.WINDOW_UNDECORATED, .WINDOW_TOPMOST})
		rl.SetWindowSize(o.prev_w > 0 ? o.prev_w : 1280, o.prev_h > 0 ? o.prev_h : 720)
		rl.SetWindowPosition(o.prev_x, o.prev_y)
		rl.SetWindowTitle("OdinVTube — local only")
		o.active = false
		fmt.println("[obs] OFF")
	}
}

obs_mode_draw_hint :: proc(o: OBS_Mode, win_w, win_h: i32) {
	if !o.active do return
	// tiny corner mark so user knows mode is on (outside typical head area)
	// Use almost-black text on green so chroma may still key it if needed — keep minimal
	rl.DrawText("OBS MODE  F9 exit  F1 HUD", 8, win_h - 22, 14, rl.Color{0, 40, 0, 180})
}

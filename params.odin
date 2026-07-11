package main

import "core:math"

// Tracking / Live2D-style parameter names used by VTube Studio configs.
// Sources are public: .vtube.json ParameterSettings Input fields.

// Input tracking parameters (from webcam / mouse / plugins)
Tracking_Inputs :: struct {
	// Head
	FaceAngleX: f32, // left/right degrees-ish (-30..30 typical)
	FaceAngleY: f32, // up/down
	FaceAngleZ: f32, // roll / lean
	// Position (optional model move)
	FacePositionX: f32,
	FacePositionY: f32,
	FacePositionZ: f32,
	// Eyes
	EyeOpenLeft:  f32, // 0 closed .. 1 open
	EyeOpenRight: f32,
	EyeLeftX:     f32, // -1..1
	EyeLeftY:     f32,
	EyeRightX:    f32,
	EyeRightY:    f32,
	// Brows
	BrowLeftY:  f32, // 0..1
	BrowRightY: f32,
	// Mouth
	MouthOpen:  f32, // 0..1
	MouthSmile: f32, // 0..1
	MouthX:     f32, // -1..1
	// Misc generated
	Breath: f32, // 0..1
	// Custom bag (plugin-injected)
	custom: map[string]f32,
}

// Model output parameters (Live2D-style names)
Model_Params :: struct {
	values: map[string]f32,
}

// One mapping rule — mirrors VTS ParameterSettings entry shape.
Param_Map_Rule :: struct {
	name:               string,
	input:              string,
	input_range_lower:  f32,
	input_range_upper:  f32,
	output_range_lower: f32,
	output_range_upper: f32,
	clamp_input:        bool,
	clamp_output:       bool,
	output_live2d:      string,
	smoothing:          f32, // 0..100 VTS style; higher = more smooth
	// runtime
	_smoothed: f32,
	_has:      bool,
}

default_tracking :: proc() -> Tracking_Inputs {
	t: Tracking_Inputs
	t.EyeOpenLeft = 1
	t.EyeOpenRight = 1
	t.BrowLeftY = 0.5
	t.BrowRightY = 0.5
	t.custom = make(map[string]f32)
	return t
}

destroy_tracking :: proc(t: ^Tracking_Inputs) {
	delete(t.custom)
}

model_params_init :: proc(m: ^Model_Params) {
	m.values = make(map[string]f32)
}

model_params_destroy :: proc(m: ^Model_Params) {
	delete(m.values)
}

get_input :: proc(t: Tracking_Inputs, name: string) -> f32 {
	switch name {
	case "FaceAngleX":
		return t.FaceAngleX
	case "FaceAngleY":
		return t.FaceAngleY
	case "FaceAngleZ":
		return t.FaceAngleZ
	case "FacePositionX":
		return t.FacePositionX
	case "FacePositionY":
		return t.FacePositionY
	case "FacePositionZ":
		return t.FacePositionZ
	case "EyeOpenLeft":
		return t.EyeOpenLeft
	case "EyeOpenRight":
		return t.EyeOpenRight
	case "EyeLeftX":
		return t.EyeLeftX
	case "EyeLeftY":
		return t.EyeLeftY
	case "EyeRightX":
		return t.EyeRightX
	case "EyeRightY":
		return t.EyeRightY
	case "BrowLeftY":
		return t.BrowLeftY
	case "BrowRightY":
		return t.BrowRightY
	case "MouthOpen":
		return t.MouthOpen
	case "MouthSmile":
		return t.MouthSmile
	case "MouthX":
		return t.MouthX
	case "Breath":
		return t.Breath
	case:
		if v, ok := t.custom[name]; ok {
			return v
		}
		return 0
	}
}

// Remap value from [in_lo, in_hi] to [out_lo, out_hi]
remap_range :: proc(v, in_lo, in_hi, out_lo, out_hi: f32, clamp_in, clamp_out: bool) -> f32 {
	x := v
	if clamp_in {
		x = clamp(x, min(in_lo, in_hi), max(in_lo, in_hi))
	}
	span_in := in_hi - in_lo
	t: f32
	if abs(span_in) < 1e-6 {
		t = 0
	} else {
		t = (x - in_lo) / span_in
	}
	out := out_lo + t * (out_hi - out_lo)
	if clamp_out {
		out = clamp(out, min(out_lo, out_hi), max(out_lo, out_hi))
	}
	return out
}

// VTS smoothing: higher number = slower response. Approximate as exponential.
// smoothing 0 = instant; 15 ~ medium; 45 ~ soft.
apply_smoothing :: proc(prev, target, smoothing, dt: f32) -> f32 {
	if smoothing <= 0 {
		return target
	}
	// convert VTS-ish 0..100 into time constant
	tau := (smoothing / 100.0) * 0.45 + 0.001
	alpha := 1.0 - math.exp(-dt / tau)
	return prev + (target - prev) * alpha
}

apply_mappings :: proc(rules: []Param_Map_Rule, track: Tracking_Inputs, out: ^Model_Params, dt: f32) {
	for &rule in rules {
		raw := get_input(track, rule.input)
		mapped := remap_range(
			raw,
			rule.input_range_lower,
			rule.input_range_upper,
			rule.output_range_lower,
			rule.output_range_upper,
			rule.clamp_input,
			rule.clamp_output,
		)
		if !rule._has {
			rule._smoothed = mapped
			rule._has = true
		} else {
			rule._smoothed = apply_smoothing(rule._smoothed, mapped, rule.smoothing, dt)
		}
		out.values[rule.output_live2d] = rule._smoothed
	}
}

// Built-in default maps (same shape as Hiyori's public .vtube.json ParameterSettings).
default_param_rules :: proc() -> [dynamic]Param_Map_Rule {
	rules := make([dynamic]Param_Map_Rule)
	append(&rules, Param_Map_Rule{"Face Left/Right", "FaceAngleX", -30, 30, -30, 30, false, false, "ParamAngleX", 15, 0, false})
	append(&rules, Param_Map_Rule{"Face Up/Down", "FaceAngleY", -20, 20, -30, 30, false, false, "ParamAngleY", 15, 0, false})
	append(&rules, Param_Map_Rule{"Face Lean", "FaceAngleZ", -30, 30, -30, 30, false, false, "ParamAngleZ", 30, 0, false})
	append(&rules, Param_Map_Rule{"Body X", "FaceAngleX", -30, 30, -10, 10, false, false, "ParamBodyAngleX", 20, 0, false})
	append(&rules, Param_Map_Rule{"Body Y", "FaceAngleY", -30, 30, -10, 10, false, false, "ParamBodyAngleY", 20, 0, false})
	append(&rules, Param_Map_Rule{"Body Z", "FaceAngleZ", -30, 30, -10, 10, false, false, "ParamBodyAngleZ", 20, 0, false})
	append(&rules, Param_Map_Rule{"Eye Open L", "EyeOpenLeft", 0, 1, 0, 1.9, false, false, "ParamEyeLOpen", 10, 0, false})
	append(&rules, Param_Map_Rule{"Eye Open R", "EyeOpenRight", 0, 1, 0, 1.9, false, false, "ParamEyeROpen", 10, 0, false})
	append(&rules, Param_Map_Rule{"Eye X", "EyeRightX", -1, 1, 1, -1, false, false, "ParamEyeBallX", 15, 0, false})
	append(&rules, Param_Map_Rule{"Eye Y", "EyeRightY", -1, 1, -1, 1, false, false, "ParamEyeBallY", 15, 0, false})
	append(&rules, Param_Map_Rule{"Brow L", "BrowLeftY", 0, 1, -1, 1, false, false, "ParamBrowLY", 10, 0, false})
	append(&rules, Param_Map_Rule{"Brow R", "BrowRightY", 0, 1, -1, 1, false, false, "ParamBrowRY", 10, 0, false})
	append(&rules, Param_Map_Rule{"Mouth Smile", "MouthSmile", 0, 1, -1, 1, false, false, "ParamMouthForm", 0, 0, false})
	append(&rules, Param_Map_Rule{"Mouth Open", "MouthOpen", 0, 1, 0, 2.3, false, false, "ParamMouthOpenY", 0, 0, false})
	append(&rules, Param_Map_Rule{"Cheek", "MouthSmile", 0, 1, 0.5, 1, false, false, "ParamCheek", 45, 0, false})
	append(&rules, Param_Map_Rule{"Breath", "Breath", 0, 1, 0, 1, false, false, "ParamBreath", 5, 0, false})
	return rules
}

get_param :: proc(m: Model_Params, name: string, fallback: f32 = 0) -> f32 {
	if v, ok := m.values[name]; ok {
		return v
	}
	return fallback
}

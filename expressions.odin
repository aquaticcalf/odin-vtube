package main

import "core:fmt"

// Expression: temporary overrides on model params (like Live2D .exp3 / VTS expressions).

Expression :: struct {
	name:     string,
	targets:  map[string]f32,
	weight:   f32,
	fade_in:  f32,
	fade_out: f32,
	active:   bool,
	current:  f32,
}

Expression_System :: struct {
	list: [dynamic]Expression,
}

expressions_init :: proc() -> Expression_System {
	es: Expression_System
	es.list = make([dynamic]Expression)

	add_expression(&es, "neutral", 0.15, 0.15)
	{
		e := add_expression(&es, "happy", 0.2, 0.25)
		e.targets["ParamMouthForm"] = 1
		e.targets["ParamCheek"] = 1
		e.targets["ParamEyeLSmile"] = 1
		e.targets["ParamEyeRSmile"] = 1
	}
	{
		e := add_expression(&es, "angry", 0.15, 0.2)
		e.targets["ParamBrowLY"] = -0.8
		e.targets["ParamBrowRY"] = -0.8
		e.targets["ParamMouthForm"] = -0.6
	}
	{
		e := add_expression(&es, "sad", 0.2, 0.25)
		e.targets["ParamBrowLY"] = 0.6
		e.targets["ParamBrowRY"] = 0.6
		e.targets["ParamMouthForm"] = -0.4
		e.targets["ParamEyeLOpen"] = 0.7
		e.targets["ParamEyeROpen"] = 0.7
	}
	{
		e := add_expression(&es, "shock", 0.1, 0.3)
		e.targets["ParamEyeLOpen"] = 1.9
		e.targets["ParamEyeROpen"] = 1.9
		e.targets["ParamMouthOpenY"] = 1.5
		e.targets["ParamBrowLY"] = 1
		e.targets["ParamBrowRY"] = 1
	}

	return es
}

// Returns pointer into es.list for filling targets.
add_expression :: proc(es: ^Expression_System, name: string, fade_in, fade_out: f32) -> ^Expression {
	e: Expression
	e.name = name
	e.targets = make(map[string]f32)
	e.fade_in = fade_in
	e.fade_out = fade_out
	e.weight = 1
	append(&es.list, e)
	return &es.list[len(es.list) - 1]
}

expressions_destroy :: proc(es: ^Expression_System) {
	for &e in es.list {
		delete(e.targets)
	}
	delete(es.list)
}

expressions_toggle :: proc(es: ^Expression_System, name: string) {
	for &e in es.list {
		if e.name == name {
			e.active = !e.active
			fmt.println("[expr]", name, "->", e.active)
			return
		}
	}
	fmt.println("[expr] unknown:", name)
}

expressions_set :: proc(es: ^Expression_System, name: string, active: bool) {
	for &e in es.list {
		if e.name == name {
			e.active = active
			return
		}
	}
}

expressions_update :: proc(es: ^Expression_System, params: ^Model_Params, dt: f32) {
	for &e in es.list {
		if e.name == "neutral" {
			continue
		}
		target: f32 = e.active ? 1 : 0
		speed := target > e.current ? e.fade_in : e.fade_out
		if speed < 0.001 {
			e.current = target
		} else {
			step := dt / speed
			if e.current < target {
				e.current = min(e.current + step, target)
			} else {
				e.current = max(e.current - step, target)
			}
		}
		if e.current <= 0.001 {
			continue
		}
		for key, val in e.targets {
			base := get_param(params^, key)
			blended := base + (val - base) * (e.current * e.weight)
			params.values[key] = blended
		}
	}
}

package main

import "core:math"

// Simple spring physics for secondary motion (hair, accessories).
// Inspired by Live2D physics concept: input motion → delayed spring output.

Spring :: struct {
	pos:     f32,
	vel:     f32,
	stiffness: f32,
	damping:   f32,
}

spring_init :: proc(stiffness: f32 = 80, damping: f32 = 12) -> Spring {
	return Spring{0, 0, stiffness, damping}
}

spring_update :: proc(s: ^Spring, target: f32, dt: f32) {
	// critical-ish spring: a = k*(target-pos) - d*vel
	force := s.stiffness * (target - s.pos) - s.damping * s.vel
	s.vel += force * dt
	s.pos += s.vel * dt
}

// Multi-axis physics pack driven by head angles.
Physics_State :: struct {
	hair_x: Spring,
	hair_y: Spring,
	hair_z: Spring,
	body_lag_x: Spring,
	body_lag_y: Spring,
	enabled: bool,
	strength: f32, // 0..1
}

physics_init :: proc() -> Physics_State {
	return Physics_State{
		hair_x     = spring_init(60, 10),
		hair_y     = spring_init(50, 10),
		hair_z     = spring_init(70, 12),
		body_lag_x = spring_init(25, 8),
		body_lag_y = spring_init(25, 8),
		enabled    = true,
		strength   = 0.5,
	}
}

physics_update :: proc(p: ^Physics_State, angle_x, angle_y, angle_z: f32, dt: f32) {
	if !p.enabled {
		return
	}
	// target offsets from head motion (hair swings opposite)
	tx := -angle_x * 0.15 * p.strength
	ty := -angle_y * 0.12 * p.strength
	tz := -angle_z * 0.1 * p.strength
	spring_update(&p.hair_x, tx, dt)
	spring_update(&p.hair_y, ty, dt)
	spring_update(&p.hair_z, tz, dt)
	spring_update(&p.body_lag_x, angle_x * 0.08 * p.strength, dt)
	spring_update(&p.body_lag_y, angle_y * 0.08 * p.strength, dt)
}

// Soft clamp for stability
soft_clamp :: proc(v, lim: f32) -> f32 {
	if v > lim do return lim
	if v < -lim do return -lim
	return v
}

// Utility used by avatar for breath scale
breathe_scale :: proc(breath: f32) -> f32 {
	return 1.0 + (breath - 0.5) * 0.02
}

lerp_f :: proc(a, b, t: f32) -> f32 {
	return a + (b - a) * clamp(t, 0, 1)
}

// safe math abs for f32 without importing all of math everywhere again
abs_f :: proc(x: f32) -> f32 {
	return math.abs(x)
}

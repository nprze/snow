package bridge

import "core:math"
import mu "vendor:microui"

muContext: mu.Context

UpdateContext :: struct {
	dt:         f64,
	globalTime: f64,
	muContext:  ^mu.Context,
}


Vec2 :: [2]f32
Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32

mat4_identity :: proc() -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		0, 0, 0, 1,
	}
}
mat4_scale :: proc(s: [3]f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		s[0], 0, 0, 0,
		0, s[1], 0, 0,
		0, 0, s[2], 0,
		0, 0, 0, 1,
	}
}
mat4_translate :: proc(p: [3]f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		1, 0, 0, 0,
		0, 1, 0, 0,
		0, 0, 1, 0,
		p[0], p[1], p[2], 1,
	}
}
mat4_rotate :: proc(r: [3]f32) -> matrix[4, 4]f32 {
	cx := math.cos(r[0]); sx := math.sin(r[0])
	cy := math.cos(r[1]); sy := math.sin(r[1])
	cz := math.cos(r[2]); sz := math.sin(r[2])

	return matrix[4, 4]f32{
		cy * cz, sx * sy * cz - cx * sz, cx * sy * cz + sx * sz, 0,
		cy * sz, sx * sy * sz + cx * cz, cx * sy * sz - sx * cz, 0,
		-sy, sx * cy, cx * cy, 0,
		0, 0, 0, 1,
	}
}
mat4_from_transform :: proc(pos, rot, scale: [3]f32) -> matrix[4, 4]f32 {
	S := mat4_scale(scale)
	R := mat4_rotate(rot)
	T := mat4_translate(pos)

	return S * R * T
}
mat4_transpose :: proc(m: matrix[4, 4]f32) -> matrix[4, 4]f32 {
	return matrix[4, 4]f32{
		m[0, 0], m[1, 0], m[2, 0], m[3, 0],
		m[0, 1], m[1, 1], m[2, 1], m[3, 1],
		m[0, 2], m[1, 2], m[2, 2], m[3, 2],
		m[0, 3], m[1, 3], m[2, 3], m[3, 3],
	}
}

package renderer

import math "core:math"
get_point_UV_shpere := proc(
	h: int,
	v: int,
	divV: int,
	divH: int,
	pos: Vec3,
	radius: f32,
) -> (
	Vec3,
	Vec3,
) {
	using math
	t_h := f32(h) / f32(divH)
	t_v := f32(v) / f32(divV)

	theta := t_h * TAU
	phi := t_v * PI

	sin_phi := sin(phi)
	cos_phi := cos(phi)

	x := sin_phi * cos(theta)
	y := cos_phi
	z := sin_phi * sin(theta)

	return Vec3{pos[0] + x * radius, pos[1] + y * radius, pos[2] + z * radius}, Vec3{x, y, z}
}
create_UV_sphere :: proc(
	pos: Vec3,
	radius: f32,
	divHArg: int,
	divVArg: int,
	color: Vec3 = {1, 1, 1},
) {
	divV: int = divVArg
	divH: int = divHArg

	if divHArg < 3 do divH = 3
	if divVArg < 2 do divV = 2

	tri_count := divH * divV * 2
	verts := make([]BasicVertex, tri_count * 3)

	idx := 0

	for v := 0; v < divV; v += 1 {
		for h := 0; h < divH; h += 1 {
			p00, n00 := get_point_UV_shpere(h, v, divV, divH, pos, radius)
			p10, n10 := get_point_UV_shpere(h + 1, v, divV, divH, pos, radius)
			p01, n01 := get_point_UV_shpere(h, v + 1, divV, divH, pos, radius)
			p11, n11 := get_point_UV_shpere(h + 1, v + 1, divV, divH, pos, radius)

			u0 := 0
			v0 := 0
			u1 := 1
			v1 := 1

			verts[idx + 0] = BasicVertex{p00, n00, color, {1, 0}}
			verts[idx + 1] = BasicVertex{p10, n10, color, {0, 0}}
			verts[idx + 2] = BasicVertex{p01, n01, color, {1, 1}}

			verts[idx + 3] = BasicVertex{p10, n10, color, {0, 0}}
			verts[idx + 4] = BasicVertex{p11, n11, color, {0, 1}}
			verts[idx + 5] = BasicVertex{p01, n01, color, {1, 1}}

			idx += 6
		}
	}
	add_vertices(&basicTrigBuffer, verts[:])
}

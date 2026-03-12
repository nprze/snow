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
	Vec2,
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
	uv := Vec2{t_h, t_v}

	return Vec3{pos[0] + x * radius, pos[1] + y * radius, pos[2] + z * radius}, Vec3{x, y, z}, uv
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
			p00, n00, uv00 := get_point_UV_shpere(h, v, divV, divH, pos, radius)
			p10, n10, uv10 := get_point_UV_shpere(h + 1, v, divV, divH, pos, radius)
			p01, n01, uv01 := get_point_UV_shpere(h, v + 1, divV, divH, pos, radius)
			p11, n11, uv11 := get_point_UV_shpere(h + 1, v + 1, divV, divH, pos, radius)

			verts[idx + 0] = BasicVertex{p00, n00, color, uv00}
			verts[idx + 1] = BasicVertex{p10, n10, color, uv10}
			verts[idx + 2] = BasicVertex{p01, n01, color, uv01}

			verts[idx + 3] = BasicVertex{p10, n10, color, uv10}
			verts[idx + 4] = BasicVertex{p11, n11, color, uv11}
			verts[idx + 5] = BasicVertex{p01, n01, color, uv01}

			idx += 6
		}
	}
	add_vertices(&basicTrigBuffer, verts[:])
}

package renderer

import fmt "core:fmt"
import math "core:math"
import slice "core:slice"
import "core:strings"
import cgltf "vendor:cgltf"

get_point_UV_shpere :: proc(
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

			verts[idx + 0] = BasicVertex{p00, n00, color, uv00, 0}
			verts[idx + 1] = BasicVertex{p01, n01, color, uv01, 0}
			verts[idx + 2] = BasicVertex{p10, n10, color, uv10, 0}

			verts[idx + 3] = BasicVertex{p10, n10, color, uv10, 0}
			verts[idx + 4] = BasicVertex{p01, n01, color, uv01, 0}
			verts[idx + 5] = BasicVertex{p11, n11, color, uv11, 0}

			idx += 6
		}
	}
	add_vertices(&basicTrigBuffer, verts[:])
}
create_rect :: proc(middle: Vec3, normal: Vec3, color: Vec3, halfSideLenght: f32) {
	tangent: Vec3
	if (abs(normal.x) > abs(normal.z)) {
		tangent = normalize(Vec3{-normal.y, normal.x, 0.0})
	} else {
		tangent = normalize(Vec3{0, -normal.z, normal.y})
	}
	bitangent := cross(normal, tangent)

	verts := make([]BasicVertex, 6)

	p00 := middle + (tangent * halfSideLenght) + (bitangent * halfSideLenght)
	p10 := middle - (tangent * halfSideLenght) + (bitangent * halfSideLenght)
	p01 := middle + (tangent * halfSideLenght) - (bitangent * halfSideLenght)
	p11 := middle - (tangent * halfSideLenght) - (bitangent * halfSideLenght)

	uv00: Vec2 = {0, 0}
	uv10: Vec2 = {1, 0}
	uv01: Vec2 = {0, 1}
	uv11: Vec2 = {1, 1}

	verts[0] = BasicVertex{p00, normal, color, uv00, 0}
	verts[1] = BasicVertex{p01, normal, color, uv01, 0}
	verts[2] = BasicVertex{p10, normal, color, uv10, 0}

	verts[3] = BasicVertex{p10, normal, color, uv10, 0}
	verts[4] = BasicVertex{p01, normal, color, uv01, 0}
	verts[5] = BasicVertex{p11, normal, color, uv11, 0}

	add_vertices(&basicTrigBuffer, verts[:])
}
ugly_load_gltf :: proc(path: string) { 	// todo: optimize this
	pathCStr: cstring = strings.clone_to_cstring(path)

	options: cgltf.options
	data, result := cgltf.parse_file(options, pathCStr)
	assert(result == .success)
	defer cgltf.free(data)

	result = cgltf.load_buffers(options, data, pathCStr)
	assert(result == .success)

	assert(len(data.meshes[0].primitives) == 1 && len(data.meshes) == 1) // for now only one mesh with only triangles

	posAcc: ^cgltf.accessor
	normAcc: ^cgltf.accessor
	indicesAcc: ^cgltf.accessor = data.meshes[0].primitives[0].indices
	assert(indicesAcc.type == .scalar)
	assert(indicesAcc.component_type == .r_32u)

	for i in data.meshes[0].primitives[0].attributes {
		switch i.type {
		case .position:
			posAcc = i.data
			assert(i.data.type == .vec3)
			assert(i.data.component_type == .r_32f)
		case .texcoord:
		// todo: load this
		case .normal:
			normAcc = i.data
			assert(i.data.type == .vec3)
			assert(i.data.component_type == .r_32f)
		case .color:
		case .invalid:
		case .tangent:
		case .joints:
		case .weights:
		case .custom:
		}
	}

	indices_view := indicesAcc.buffer_view
	indices_buf := indices_view.buffer
	base := cast(uintptr)indices_buf.data
	ptr := cast(uintptr)(cast(uint)base + indices_view.offset + indicesAcc.offset)
	indices: []u32 = slice.from_ptr(cast(^u32)ptr, int(indicesAcc.count))

	positions_view := posAcc.buffer_view
	positions_buf := positions_view.buffer
	base = cast(uintptr)positions_buf.data
	ptr = cast(uintptr)(cast(uint)base + positions_view.offset + posAcc.offset)
	positions: []Vec3 = slice.from_ptr(cast(^Vec3)ptr, int(posAcc.count))

	normal_view := normAcc.buffer_view
	normal_buf := normal_view.buffer
	base = cast(uintptr)normal_buf.data
	ptr = cast(uintptr)(cast(uint)base + normal_view.offset + normAcc.offset)
	normals: []Vec3 = slice.from_ptr(cast(^Vec3)ptr, int(normAcc.count))

	verts: []BasicVertex = make([]BasicVertex, indicesAcc.count)

	for j in 0 ..< indicesAcc.count / 3 {
		i := j * 3
		index := indices[i]
		verts[i + 2] = BasicVertex{positions[index], normals[index], {1, 1, 1}, {1, 0}, 0}
		index = indices[i + 1]
		verts[i + 1] = BasicVertex{positions[index], normals[index], {1, 1, 1}, {1, 0}, 0}
		index = indices[i + 2]
		verts[i + 0] = BasicVertex{positions[index], normals[index], {1, 1, 1}, {1, 0}, 0}
	}
	add_vertices(&basicTrigBuffer, verts)
}

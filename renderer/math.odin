package renderer
import "core:fmt"
import "core:math"
import "core:mem"

Vec2 :: struct {
	x: f32,
	y: f32,
}

Vec3 :: [3]f32
Vec4 :: [4]f32
Mat4 :: matrix[4, 4]f32

// vector
add :: proc(a: Vec3, b: Vec3) -> Vec3 {
	return Vec3{a.x + b.x, a.y + b.y, a.z + b.z}
}

sub :: proc(a: Vec3, b: Vec3) -> Vec3 {
	return Vec3{a.x - b.x, a.y - b.y, a.z - b.z}
}

dot :: proc(a: Vec3, b: Vec3) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z
}

dot4 :: proc(a: Vec4, b: Vec4) -> f32 {
	return a.x * b.x + a.y * b.y + a.z * b.z + a.w * b.w
}

cross :: proc(a: Vec3, b: Vec3) -> Vec3 {
	return Vec3{a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x}
}

normalize :: proc(v: Vec3) -> Vec3 {
	length := math.sqrt(dot(v, v))
	if length == 0 {
		return Vec3{0, 0, 0}
	}
	return Vec3{v.x / length, v.y / length, v.z / length}
}

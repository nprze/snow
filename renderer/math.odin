package renderer
import "core:fmt"
import "core:math"
import "core:mem"

Vec2 :: struct {
	x: f32,
	y: f32,
}

Vec3 :: struct {
	x: f32,
	y: f32,
	z: f32,
}

Vec4 :: struct {
	x: f32,
	y: f32,
	z: f32,
	w: f32,
}

Mat4 :: struct {
	a: Vec4,
	b: Vec4,
	c: Vec4,
	d: Vec4,
}

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
// matrix
zero_mat :: proc() -> Mat4 {
	return Mat4{{0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}, {0, 0, 0, 0}}
}
mul_mat :: proc(a, b: Mat4) -> Mat4 {
	return Mat4 {
		Vec4 {
			a.a.x * b.a.x + a.b.x * b.a.y + a.c.x * b.a.z + a.d.x * b.a.w,
			a.a.y * b.a.x + a.b.y * b.a.y + a.c.y * b.a.z + a.d.y * b.a.w,
			a.a.z * b.a.x + a.b.z * b.a.y + a.c.z * b.a.z + a.d.z * b.a.w,
			a.a.w * b.a.x + a.b.w * b.a.y + a.c.w * b.a.z + a.d.w * b.a.w,
		},
		Vec4 {
			a.a.x * b.b.x + a.b.x * b.b.y + a.c.x * b.b.z + a.d.x * b.b.w,
			a.a.y * b.b.x + a.b.y * b.b.y + a.c.y * b.b.z + a.d.y * b.b.w,
			a.a.z * b.b.x + a.b.z * b.b.y + a.c.z * b.b.z + a.d.z * b.b.w,
			a.a.w * b.b.x + a.b.w * b.b.y + a.c.w * b.b.z + a.d.w * b.b.w,
		},
		Vec4 {
			a.a.x * b.c.x + a.b.x * b.c.y + a.c.x * b.c.z + a.d.x * b.c.w,
			a.a.y * b.c.x + a.b.y * b.c.y + a.c.y * b.c.z + a.d.y * b.c.w,
			a.a.z * b.c.x + a.b.z * b.c.y + a.c.z * b.c.z + a.d.z * b.c.w,
			a.a.w * b.c.x + a.b.w * b.c.y + a.c.w * b.c.z + a.d.w * b.c.w,
		},
		Vec4 {
			a.a.x * b.d.x + a.b.x * b.d.y + a.c.x * b.d.z + a.d.x * b.d.w,
			a.a.y * b.d.x + a.b.y * b.d.y + a.c.y * b.d.z + a.d.y * b.d.w,
			a.a.z * b.d.x + a.b.z * b.d.y + a.c.z * b.d.z + a.d.z * b.d.w,
			a.a.w * b.d.x + a.b.w * b.d.y + a.c.w * b.d.z + a.d.w * b.d.w,
		},
	}
}
look_at :: proc(center: Vec3, eye: Vec3, up: Vec3) -> Mat4 {
	zaxis: Vec3 = normalize(sub(center, eye))
	xaxis: Vec3 = normalize(cross(up, zaxis))
	yaxis: Vec3 = cross(zaxis, xaxis)

	return Mat4 {
		{xaxis.x, yaxis.x, zaxis.x, -dot(xaxis, eye)},
		{xaxis.y, yaxis.y, zaxis.y, -dot(yaxis, eye)},
		{xaxis.z, yaxis.z, zaxis.z, -dot(zaxis, eye)},
		{0, 0, 0, 1},
	}
}

perspective :: proc(fov: f32, aspect: f32, near: f32, far: f32) -> Mat4 {
	f := 1 / math.tan(fov * 0.5)

	mat := zero_mat()
	mat.a.x = f / aspect
	mat.b.y = f
	mat.c.z = -(far + near) / (far - near)
	mat.c.w = -(2 * far * near) / (far - near)
	mat.d.z = -1
	mat.d.w = 0

	return mat
}

// debug
print_vec :: proc(vec: Vec4) {
	fmt.printf("%3f %3f %3f %3f", vec.x, vec.y, vec.z, vec.w)
}
print_mat :: proc(mat: Mat4) {
	fmt.println("vvvvvvvvvvvvv")
	print_vec(mat.a)
	fmt.println()
	print_vec(mat.b)
	fmt.println()
	print_vec(mat.c)
	fmt.println()
	print_vec(mat.d)
	fmt.println()
	fmt.println("^^^^^^^^^^^^^")

}

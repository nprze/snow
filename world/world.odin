package world

import math "core:math"
import snow "snow:bridge"
import ren "snow:renderer"
import mu "vendor:microui"

object :: struct {
	position:            snow.Vec3,
	rotation:            snow.Vec3,
	scale:               snow.Vec3,
	objectIndexMatrix:   u32,
	objectIndexCollider: u32,
}

cube: object

create_world :: proc() {
	physics_init()
	// create cube object
	cube.position = {3, 0, 3}
	cube.rotation = {0, 0, 0}
	cube.scale = {1, 1, 1}
	cube.objectIndexMatrix = ren.create_cube_mesh(
		cube.position,
		cube.rotation,
		cube.scale,
		{1, 1, 1},
	)
}

update_world :: proc(ctx: snow.UpdateContext) {
	if mu.begin_window(ctx.muContext, "settings", mu.Rect{10, 10, 350, 200}) {
		widths := []i32{}
		mu.layout_row(ctx.muContext, widths[:])

		mu.label(ctx.muContext, "camera options:")
		widths2 := [2]i32{150, 150}
		mu.layout_row(ctx.muContext, widths2[:])
		mu.label(ctx.muContext, "move")
		mu.slider(ctx.muContext, &ren.cameraData.movingSpeed, 0, 20)
		mu.label(ctx.muContext, "drag")
		mu.slider(ctx.muContext, &ren.cameraData.dragSpeed, -3, 3)
		mu.end_window(ctx.muContext)
	}

	physics_update()

	r: f32 = 2
	cube.position.x = 3 + r * f32(math.cos(ctx.globalTime))
	cube.position.z = 3 + r * f32(math.sin(ctx.globalTime))
	cube.rotation.x = 3 + r * f32(math.sin(ctx.globalTime))
	cube.rotation.y = 3 + r * f32(math.cos(ctx.globalTime))
	ren.modify_matrix(cube.position, cube.rotation, cube.scale, cube.objectIndexMatrix)

	ren.debug_point({1, 0, 3})
}

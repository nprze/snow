package renderer

import mu "vendor:microui"

UpdateContext :: struct {
	dt:        f64,
	muContext: ^mu.Context,
}

update_world :: proc(ctx: UpdateContext) {
	if mu.begin_window(ctx.muContext, "settings", mu.Rect{10, 10, 350, 200}) {
		widths := []i32{}
		mu.layout_row(ctx.muContext, widths[:])

		mu.label(ctx.muContext, "camera options:")
		widths2 := [2]i32{150, 150}
		mu.layout_row(ctx.muContext, widths2[:])
		mu.label(ctx.muContext, "move")
		mu.slider(ctx.muContext, &cameraData.movingSpeed, 0, 20)
		mu.label(ctx.muContext, "drag")
		mu.slider(ctx.muContext, &cameraData.dragSpeed, -3, 3)
		mu.end_window(ctx.muContext)
	}
}

get_context :: proc(dt: f64) -> UpdateContext {
	return {dt, &muContext}
}

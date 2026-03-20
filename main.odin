package main

import "core:time"
import ren "renderer"
import glfw "vendor:glfw"

main :: proc() {
	// viewer width, viewer height
	vw: i32 = 1800
	vh: i32 = 900
	// window
	window := ren.create_window(vw, vh)
	defer ren.delete_window(window)
	// renderer
	ren.create_renderer(u32(vw), u32(vh), window)
	last_time := time.now()
	for !glfw.WindowShouldClose(window) {
		now := time.now()
		dt := time.duration_seconds(time.diff(now, last_time))
		last_time = now
		updateContext: UpdateContext = {dt, ren.muContext}
		ren.before_update()
		ren.update_world(updateContext)
		ren.post_update()
		ren.render_all(updateContext)
	}
	ren.cleanup_renderer()
}

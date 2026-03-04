package main

import ren "renderer"
import glfw "vendor:glfw"


main :: proc() {
	// viewer width, viewer height
	vw: i32 = 1600
	vh: i32 = 800
	// window
	window := ren.create_window(vw, vh)
	defer ren.delete_window(window)
	// renderer
	ren.create_renderer(u32(vw), u32(vh), window)
	ren.main_loop(window)
	ren.cleanup_renderer()
}

package renderer

import "base:runtime"
import "core:unicode/utf8"
import glfw "vendor:glfw"
import mu "vendor:microui"

oneOver255: f32 = 1.0 / 255.0

UiVertex :: struct {
	// include allignment padding here.
	position: Vec2,
	color:    Vec3,
	index:    int,
}

uiVertexBuffer: VertexBuffer

char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	buf, n := utf8.encode_rune(codepoint)
	mu.input_text(&muContext, string(buf[:n]))
}
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos: f64, ypos: f64) {
	context = runtime.default_context()
	mu.input_mouse_move(&muContext, i32(xpos), i32(ypos))
}

mu_init :: proc() {
	mu.init(&muContext)
	glfw.SetCharCallback(renderer.windowHandle, char_callback)
	glfw.SetCursorPosCallback(renderer.windowHandle, cursor_pos_callback)
	initialize_vbuffer(&uiVertexBuffer, size_of(BasicVertex) * 265)
}
mu_begin :: proc() {
	mu.begin(&muContext)
	clean_vbuffer(&uiVertexBuffer)
}
mu_end :: proc() {
	mu.end(&muContext)
}
mu_render :: proc() {
	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(&muContext, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Rect:
		case ^mu.Command_Jump:
		case ^mu.Command_Clip:
		case ^mu.Command_Text:
		case ^mu.Command_Icon:
		}
	}
}

add_rect :: proc(area: Vec4, color: Vec3) {
	verts := [?]UiVertex {
		{{area.x, area.y}, color, -1},
		{{area.x + area.z, area.y}, color, -1},
		{{area.x + area.z, area.y + area.w}, color, -1},
		{{area.x, area.y}, color, -1},
		{{area.x, area.y + area.w}, color, -1},
		{{area.x + area.z, area.y + area.w}, color, -1},
	}
	add_vertices_ui(&uiVertexBuffer, verts[:])
}

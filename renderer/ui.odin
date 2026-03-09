package renderer

import "base:runtime"
import fmt "core:fmt"
import "core:unicode/utf8"
import d3d12 "vendor:directx/d3d12"
import glfw "vendor:glfw"
import mu "vendor:microui"

oneOver255: f32 = 1.0 / 255.0
defaultFontSizePixel: i32 = 16

UiVertex :: struct {
	// include allignment padding here.
	position: Vec2,
	uv:       Vec2,
	color:    Vec4,
}

lastX, lastY: i32

char_callback :: proc "c" (window: glfw.WindowHandle, codepoint: rune) {
	context = runtime.default_context()
	buf, n := utf8.encode_rune(codepoint)
	mu.input_text(&muContext, string(buf[:n]))
}
cursor_pos_callback :: proc "c" (window: glfw.WindowHandle, xpos: f64, ypos: f64) {
	context = runtime.default_context()
	mu.input_mouse_move(&muContext, i32(xpos), i32(ypos))
	lastX = i32(xpos)
	lastY = i32(ypos)
}
scroll_callback :: proc "c" (window: glfw.WindowHandle, xoffset: f64, yoffset: f64) {
	context = runtime.default_context()
	mu.input_scroll(&muContext, 0, i32(-yoffset * 10))
}
mouse_button_callback :: proc "c" (
	window: glfw.WindowHandle,
	button: i32,
	action: i32,
	mods: i32,
) {
	context = runtime.default_context()
	btn: mu.Mouse
	switch button {
	case glfw.MOUSE_BUTTON_LEFT:
		btn = mu.Mouse.LEFT
	case glfw.MOUSE_BUTTON_RIGHT:
		btn = mu.Mouse.RIGHT
	case glfw.MOUSE_BUTTON_MIDDLE:
		btn = mu.Mouse.MIDDLE
	}
	if action == glfw.PRESS {
		mu.input_mouse_down(&muContext, lastX, lastY, btn)
	} else if action == glfw.RELEASE {
		mu.input_mouse_up(&muContext, lastX, lastY, btn)
	}
}

ui_init :: proc() {
	init_texture_loader()
	renderer.consolasFont = load_font("renderer/fonts/consolas.txt")

	mu.init(&muContext)
	muContext.text_width = mu.default_atlas_text_width
	muContext.text_height = text_height

	glfw.SetCharCallback(renderer.windowHandle, char_callback)
	glfw.SetCursorPosCallback(renderer.windowHandle, cursor_pos_callback)
	glfw.SetScrollCallback(renderer.windowHandle, scroll_callback)
	glfw.SetMouseButtonCallback(renderer.windowHandle, mouse_button_callback)

	initialize_vbuffer(&renderer.uiVertexBuffer, 2048, size_of(UiVertex))

	hr: d3d12.HRESULT
	// root signature
	desc := d3d12.VERSIONED_ROOT_SIGNATURE_DESC {
		Version = ._1_0,
	}
	srv_range := d3d12.DESCRIPTOR_RANGE {
		RangeType                         = .SRV,
		NumDescriptors                    = 1,
		BaseShaderRegister                = 0,
		RegisterSpace                     = 0,
		OffsetInDescriptorsFromTableStart = 0,
	}

	sampler_range := d3d12.DESCRIPTOR_RANGE {
		RangeType                         = .SAMPLER,
		NumDescriptors                    = 1,
		BaseShaderRegister                = 0,
		RegisterSpace                     = 0,
		OffsetInDescriptorsFromTableStart = 0,
	}

	root_params: [2]d3d12.ROOT_PARAMETER

	root_params[0] = {
		ParameterType    = .DESCRIPTOR_TABLE,
		ShaderVisibility = .PIXEL,
	}
	root_params[0].DescriptorTable = {
		NumDescriptorRanges = 1,
		pDescriptorRanges   = &srv_range,
	}

	root_params[1] = {
		ParameterType    = .DESCRIPTOR_TABLE,
		ShaderVisibility = .PIXEL,
	}
	root_params[1].DescriptorTable = {
		NumDescriptorRanges = 1,
		pDescriptorRanges   = &sampler_range,
	}
	desc.Desc_1_0 = {
		NumParameters     = 2,
		pParameters       = &root_params[0],
		NumStaticSamplers = 0,
		pStaticSamplers   = nil,
		Flags             = {.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT},
	}
	desc.Desc_1_0.Flags = {.ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT}
	serialized_desc: ^d3d12.IBlob
	hr = d3d12.SerializeVersionedRootSignature(&desc, &serialized_desc, nil)
	check(hr, "Failed to serialize root signature")
	hr = renderer.device->CreateRootSignature(
		0,
		serialized_desc->GetBufferPointer(),
		serialized_desc->GetBufferSize(),
		d3d12.IRootSignature_UUID,
		(^rawptr)(&renderer.uiRootSignature),
	)
	check(hr, "Failed creating root signature")
	serialized_desc->Release()
	// pso
	vs: ^d3d12.IBlob = nil
	ps: ^d3d12.IBlob = nil

	compile_shaders("ui.hlsl", &vs, &ps)

	vertex_format: []d3d12.INPUT_ELEMENT_DESC = {
		{
			SemanticName = "POSITION",
			Format = .R32G32_FLOAT,
			AlignedByteOffset = 0,
			InputSlotClass = .PER_VERTEX_DATA,
		},
		{
			SemanticName = "TEXCOORD",
			Format = .R32G32_FLOAT,
			AlignedByteOffset = size_of(Vec2),
			InputSlotClass = .PER_VERTEX_DATA,
		},
		{
			SemanticName = "COLOR",
			Format = .R32G32B32A32_FLOAT,
			AlignedByteOffset = size_of(Vec2) * 2,
			InputSlotClass = .PER_VERTEX_DATA,
		},
	}

	default_blend_state := d3d12.RENDER_TARGET_BLEND_DESC {
		BlendEnable           = true,
		LogicOpEnable         = false,
		SrcBlend              = .SRC_ALPHA,
		DestBlend             = .INV_SRC_ALPHA,
		BlendOp               = .ADD,
		SrcBlendAlpha         = .ONE,
		DestBlendAlpha        = .INV_SRC_ALPHA,
		BlendOpAlpha          = .ADD,
		RenderTargetWriteMask = u8(d3d12.COLOR_WRITE_ENABLE_ALL),
	}

	pipeline_state_desc := d3d12.GRAPHICS_PIPELINE_STATE_DESC {
		pRootSignature = renderer.uiRootSignature,
		VS = {pShaderBytecode = vs->GetBufferPointer(), BytecodeLength = vs->GetBufferSize()},
		PS = {pShaderBytecode = ps->GetBufferPointer(), BytecodeLength = ps->GetBufferSize()},
		StreamOutput = {},
		BlendState = {
			AlphaToCoverageEnable = false,
			IndependentBlendEnable = false,
			RenderTarget = {0 = default_blend_state, 1 ..< 7 = {}},
		},
		SampleMask = 0xFFFFFFFF,
		RasterizerState = {
			FillMode = .SOLID,
			CullMode = .NONE,
			FrontCounterClockwise = false,
			DepthBias = 0,
			DepthBiasClamp = 0,
			SlopeScaledDepthBias = 0,
			DepthClipEnable = true,
			MultisampleEnable = false,
			AntialiasedLineEnable = false,
			ForcedSampleCount = 0,
			ConservativeRaster = .OFF,
		},
		DepthStencilState = {DepthEnable = false, StencilEnable = false},
		InputLayout = {
			pInputElementDescs = &vertex_format[0],
			NumElements = u32(len(vertex_format)),
		},
		PrimitiveTopologyType = .TRIANGLE,
		NumRenderTargets = 1,
		RTVFormats = {0 = .R8G8B8A8_UNORM, 1 ..< 7 = .UNKNOWN},
		DSVFormat = .UNKNOWN,
		SampleDesc = {Count = 1, Quality = 0},
	}

	hr = renderer.device->CreateGraphicsPipelineState(
		&pipeline_state_desc,
		d3d12.IPipelineState_UUID,
		(^rawptr)(&renderer.uiPipeline),
	)
	check(hr, "Pipeline creation failed")

	vs->Release()
	ps->Release()
}
ui_cleanup :: proc() {
	renderer.uiPipeline->Release()
	renderer.uiRootSignature->Release()
	cleanup_texture_loader()
	cleanup_vbuffer(&renderer.uiVertexBuffer)
	cleanup_font(&renderer.consolasFont)
}
ui_begin :: proc() {
	mu.begin(&muContext)
	reset_vbuffer(&renderer.uiVertexBuffer)
}
ui_end :: proc() {
	mu.end(&muContext)
}
ui_render :: proc() {

	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(&muContext, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Rect:
			{
				add_rect_screen(
					{f32(cmd.rect.x), f32(cmd.rect.y), f32(cmd.rect.w), f32(cmd.rect.h)},
					{
						f32(cmd.color.r) * oneOver255,
						f32(cmd.color.g) * oneOver255,
						f32(cmd.color.b) * oneOver255,
						f32(cmd.color.a) * oneOver255,
					},
				)
				break
			}
		case ^mu.Command_Text:
			{
				add_text(
					string(cmd.str),
					renderer.consolasFont,
					Vec2{f32(cmd.pos.x), f32(cmd.pos.y)},
					Vec3{1, 1, 1},
				)
				break
			}
		case ^mu.Command_Icon:
			text: rune
			switch cmd.id {
			case .NONE:
			case .CLOSE:
				text = '✖'
			case .CHECK:
				text = '✔'
			case .COLLAPSED:
				text = '▶'
			case .EXPANDED:
				text = '▼'
			case .RESIZE:
				text = '⇲'
			}
			add_icon_screen(text, renderer.consolasFont, cmd.rect, Vec3{1, 1, 1})

		case ^mu.Command_Jump:
		case ^mu.Command_Clip:
		}
	}

	viewport := d3d12.VIEWPORT {
		Width  = f32(renderer.displayWidth),
		Height = f32(renderer.displayHeight),
	}

	scissor_rect := d3d12.RECT {
		left   = 0,
		right  = i32(renderer.displayWidth),
		top    = 0,
		bottom = i32(renderer.displayHeight),
	}
	renderer.commandList->RSSetViewports(1, &viewport)
	renderer.commandList->RSSetScissorRects(1, &scissor_rect)

	renderer.commandList->SetGraphicsRootSignature(renderer.uiRootSignature)
	renderer.commandList->SetPipelineState(renderer.uiPipeline)
	renderer.commandList->IASetPrimitiveTopology(.TRIANGLELIST)

	heaps := [?]^d3d12.IDescriptorHeap{srvHeap, samplerHeap}

	srv_gpu: d3d12.GPU_DESCRIPTOR_HANDLE
	sampler_gpu: d3d12.GPU_DESCRIPTOR_HANDLE

	srvHeap.GetGPUDescriptorHandleForHeapStart(srvHeap, &srv_gpu)
	samplerHeap.GetGPUDescriptorHandleForHeapStart(samplerHeap, &sampler_gpu)

	renderer.commandList->SetDescriptorHeaps(len(heaps), &heaps[0])
	renderer.commandList->SetGraphicsRootDescriptorTable(0, srv_gpu)
	renderer.commandList->SetGraphicsRootDescriptorTable(1, sampler_gpu)

	renderer.commandList->IASetVertexBuffers(0, 1, &renderer.uiVertexBuffer.dBufferView)
	renderer.commandList->DrawInstanced(u32(renderer.uiVertexBuffer.vertexCount), 1, 0, 0)

	renderer.uiVertexBuffer.vertexCount = 0
}

add_rect_screen :: proc(areaArg: Vec4, color: Vec4) {
	area := areaArg
	area.x *= renderer.oneOverDisplayWidth
	area.y *= renderer.oneOverDisplayHeight
	area.x = area.x * 2 - 1
	area.y = 1 - area.y * 2
	area.z *= renderer.oneOverDisplayWidth * 2
	area.w *= -renderer.oneOverDisplayHeight * 2
	add_rect(area, color)
}
add_icon_screen :: proc(text: rune, font: Font, rect: mu.Rect, color: Vec3) {
	glyph := font.glyphMap[text]
	minX := f32(rect.x) * renderer.oneOverDisplayWidth * 2 - 1 + 0.008
	minY := 1 - f32(rect.y) * renderer.oneOverDisplayHeight * 2 - 0.008
	maxX := f32(rect.x + rect.w) * renderer.oneOverDisplayWidth * 2 - 1 - 0.008
	maxY := 1 - f32(rect.y + rect.h) * renderer.oneOverDisplayHeight * 2 + 0.008

	u0 := glyph.uv.x
	v0 := glyph.uv.y
	u1 := glyph.uv.z
	v1 := glyph.uv.w

	colorVec4 := Vec4{color.x, color.y, color.z, 0.0}
	vertices := [?]UiVertex {
		{{maxX, maxY}, {u1, v1}, colorVec4},
		{{maxX, minY}, {u1, v0}, colorVec4},
		{{minX, minY}, {u0, v0}, colorVec4},
		{{minX, minY}, {u0, v0}, colorVec4},
		{{minX, maxY}, {u0, v1}, colorVec4},
		{{maxX, maxY}, {u1, v1}, colorVec4},
	}

	write_ui(&renderer.uiVertexBuffer, vertices[:])

}

add_rect :: proc(area: Vec4, color: Vec4) {
	vertices := [?]UiVertex {
		{{area.x + area.z, area.y + area.w}, {1.0, 1.0}, color},
		{{area.x + area.z, area.y}, {1.0, 0.0}, color},
		{{area.x, area.y}, {0.0, 0.0}, color},
		{{area.x, area.y}, {0.0, 0.0}, color},
		{{area.x, area.y + area.w}, {0.0, 1.0}, color},
		{{area.x + area.z, area.y + area.w}, {1.0, 1.0}, color},

		/*
		proper order for fullscreen quad (cull mode back)
		{{1.0, 1.0}, {1, 1, 1, 1}},
		{{1.0, -1.0}, {1, 1, 1, 1}},
		{{-1.0, -1.0}, {1, 1, 1, 1}},
		{{-1.0, -1.0}, {1, 1, 1, 1}},
		{{-1.0, 1.0}, {1, 1, 1, 1}},
		{{1.0, 1.0}, {1, 1, 1, 1}},
		*/
	}
	write_ui(&renderer.uiVertexBuffer, vertices[:])
}

add_text :: proc(text: string, font: Font, cursorPos: Vec2, color: Vec3) {
	scale := f32(defaultFontSizePixel) / font.size

	cursorMU := cursorPos

	for r in text {
		glyph, ok := font.glyphMap[r]
		if !ok {
			continue
		}

		w := (glyph.width * scale) * renderer.oneOverDisplayWidth * 2
		h := (glyph.height * scale) * renderer.oneOverDisplayHeight * 2

		x := (cursorMU.x + glyph.xOffset * scale) * renderer.oneOverDisplayWidth * 2 - 1
		y := 1 - (cursorMU.y + glyph.yOffset * scale) * renderer.oneOverDisplayHeight * 2

		cursorMU.x += (glyph.xAdvance) * scale

		u0 := glyph.uv.x
		v0 := glyph.uv.y
		u1 := glyph.uv.z
		v1 := glyph.uv.w

		area: Vec4 = {x, y, w, h}
		colorVec4 := Vec4{color.x, color.y, color.z, 0.0}
		vertices := [?]UiVertex {
			{{area.x + area.z, area.y - area.w}, {u1, v1}, colorVec4},
			{{area.x + area.z, area.y}, {u1, v0}, colorVec4},
			{{area.x, area.y}, {u0, v0}, colorVec4},
			{{area.x, area.y}, {u0, v0}, colorVec4},
			{{area.x, area.y - area.w}, {u0, v1}, colorVec4},
			{{area.x + area.z, area.y - area.w}, {u1, v1}, colorVec4},
		}

		write_ui(&renderer.uiVertexBuffer, vertices[:])
	}
}
text_height :: proc(font: mu.Font) -> i32 {
	return defaultFontSizePixel
}

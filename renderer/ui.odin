package renderer

import "base:runtime"
import fmt "core:fmt"
import "core:unicode/utf8"
import d3d12 "vendor:directx/d3d12"
import glfw "vendor:glfw"
import mu "vendor:microui"

oneOver255: f32 = 1.0 / 255.0

UiVertex :: struct {
	// include allignment padding here.
	position: Vec2,
	uv:       Vec2,
	color:    Vec4,
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

ui_init :: proc() {
	mu.init(&muContext)
	muContext.text_width = mu.default_atlas_text_width
	muContext.text_height = mu.default_atlas_text_height

	init_texture_loader()

	glfw.SetCharCallback(renderer.windowHandle, char_callback)
	glfw.SetCursorPosCallback(renderer.windowHandle, cursor_pos_callback)
	initialize_vbuffer(&uiVertexBuffer, 265, size_of(UiVertex))

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
			CullMode = .BACK,
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
	cleanup_vbuffer(&uiVertexBuffer)
}
ui_begin :: proc() {
	mu.begin(&muContext)
	reset_vbuffer(&uiVertexBuffer)
}
ui_end :: proc() {
	mu.end(&muContext)
}
ui_render :: proc() {
	/*
	command_backing: ^mu.Command
	for variant in mu.next_command_iterator(&muContext, &command_backing) {
		switch cmd in variant {
		case ^mu.Command_Rect:
		case ^mu.Command_Jump:
		case ^mu.Command_Clip:
		case ^mu.Command_Text:
		case ^mu.Command_Icon:
		}
	}*/

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

	renderer.commandList->SetGraphicsRootDescriptorTable(0, srv_gpu)
	renderer.commandList->SetGraphicsRootDescriptorTable(1, sampler_gpu)
	renderer.commandList->SetDescriptorHeaps(len(heaps), &heaps[0])

	renderer.commandList->IASetVertexBuffers(0, 1, &uiVertexBuffer.dBufferView)
	assert(uiVertexBuffer.vertexCount > 0)
	renderer.commandList->DrawInstanced(u32(uiVertexBuffer.vertexCount), 1, 0, 0)

	uiVertexBuffer.vertexCount = 0
}

add_rect :: proc(area: Vec4, color: Vec4) {
	vertices := [?]UiVertex {
		{{area.x + area.z, area.y + area.w}, {0.0, 0.0}, color},
		{{area.x + area.z, area.y}, {0.0, 1.0}, color},
		{{area.x, area.y}, {1.0, 1.0}, color},
		{{area.x, area.y}, {1.0, 1.0}, color},
		{{area.x, area.y + area.w}, {1.0, 0.0}, color},
		{{area.x + area.z, area.y + area.w}, {0.0, 0.0}, color},

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
	write_ui(&uiVertexBuffer, vertices[:])
}

package renderer

import os "core:os"
import d3d12 "vendor:directx/d3d12"
import d3dc "vendor:directx/d3d_compiler"

basicTrigBuffer: VertexBuffer

read_file :: proc(path: string) -> cstring {
	data_slice, ok := os.read_entire_file(path)
	if !ok {
		panic("Failed to read file")
	}
	data := make([]u8, len(data_slice) + 1)
	copy(data, data_slice)
	data[len(data_slice)] = 0
	return cstring(&data[0])
}
create_root_signature :: proc() -> ^d3d12.IRootSignature {
	hr: d3d12.HRESULT
	desc := d3d12.VERSIONED_ROOT_SIGNATURE_DESC {
		Version = ._1_0,
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
		(^rawptr)(&renderer.rootSignature),
	)
	check(hr, "Failed creating root signature")
	serialized_desc->Release()
	return renderer.rootSignature
}
create_pipeline :: proc() -> ^d3d12.IPipelineState {
	hr: d3d12.HRESULT
	// Compile vertex and pixel shaders
	data: cstring = read_file("renderer/shaders/base.hlsl")

	data_size: uint = len(data)

	compile_flags: u32 = 0
	when ODIN_DEBUG {
		compile_flags |= u32(d3dc.D3DCOMPILE.DEBUG)
		compile_flags |= u32(d3dc.D3DCOMPILE.SKIP_OPTIMIZATION)
	}

	vs: ^d3d12.IBlob = nil
	ps: ^d3d12.IBlob = nil

	hr = d3dc.Compile(
		rawptr(data),
		data_size,
		nil,
		nil,
		nil,
		"VSMain",
		"vs_4_0",
		compile_flags,
		0,
		&vs,
		nil,
	)
	check(hr, "Failed to compile vertex shader")

	hr = d3dc.Compile(
		rawptr(data),
		data_size,
		nil,
		nil,
		nil,
		"PSMain",
		"ps_4_0",
		compile_flags,
		0,
		&ps,
		nil,
	)
	check(hr, "Failed to compile pixel shader")

	vertex_format: []d3d12.INPUT_ELEMENT_DESC = {
		{SemanticName = "POSITION", Format = .R32G32B32_FLOAT, InputSlotClass = .PER_VERTEX_DATA},
		{
			SemanticName = "COLOR",
			Format = .R32G32B32A32_FLOAT,
			AlignedByteOffset = size_of(f32) * 3,
			InputSlotClass = .PER_VERTEX_DATA,
		},
	}

	default_blend_state := d3d12.RENDER_TARGET_BLEND_DESC {
		BlendEnable           = false,
		LogicOpEnable         = false,
		SrcBlend              = .ONE,
		DestBlend             = .ZERO,
		BlendOp               = .ADD,
		SrcBlendAlpha         = .ONE,
		DestBlendAlpha        = .ZERO,
		BlendOpAlpha          = .ADD,
		LogicOp               = .NOOP,
		RenderTargetWriteMask = u8(d3d12.COLOR_WRITE_ENABLE_ALL),
	}

	pipeline_state_desc := d3d12.GRAPHICS_PIPELINE_STATE_DESC {
		pRootSignature = renderer.rootSignature,
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
		(^rawptr)(&renderer.pipeline),
	)
	check(hr, "Pipeline creation failed")

	vs->Release()
	ps->Release()

	return renderer.pipeline
}
create_command_list :: proc(
	commandListOut: ^^d3d12.IGraphicsCommandList,
) -> ^^d3d12.IGraphicsCommandList {
	hr: d3d12.HRESULT
	hr = renderer.device->CreateCommandList(
		0,
		.DIRECT,
		renderer.commandAllocator,
		renderer.pipeline,
		d3d12.ICommandList_UUID,
		(^rawptr)(commandListOut),
	)
	check(hr, "Failed to create command list")
	hr = (commandListOut^)->Close()
	check(hr, "Failed to close command list")
	return commandListOut
}

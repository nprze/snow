package renderer

import os "core:os"
import "core:slice"
import d3d12 "vendor:directx/d3d12"


basicTrigBuffer: VertexBuffer
noiseTexture: Texture
matrixBuffer: ^d3d12.IResource
matrixMapped: []Mat4

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
create_depth_buffer :: proc() {
	// desc heap
	hr: d3d12.HRESULT
	desc := d3d12.DESCRIPTOR_HEAP_DESC {
		NumDescriptors = RENDERTARGETS_COUNT,
		Type           = .DSV,
		Flags          = {},
	}

	hr = renderer.device->CreateDescriptorHeap(
		&desc,
		d3d12.IDescriptorHeap_UUID,
		(^rawptr)(&renderer.dsvDescriptorHeap),
	)
	check(hr, "Failed creating depth stencil descriptor heap")

	// buffer
	heap_props := d3d12.HEAP_PROPERTIES {
		Type = .DEFAULT,
	}
	depthDesc: d3d12.RESOURCE_DESC = {
		Dimension = .TEXTURE2D,
		Width = u64(renderer.displayWidth),
		Height = renderer.displayHeight,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .D32_FLOAT,
		SampleDesc = {Count = 1},
		Flags = d3d12.RESOURCE_FLAGS{.ALLOW_DEPTH_STENCIL},
	}
	clearValue: d3d12.CLEAR_VALUE = {
		Format = .D32_FLOAT,
		DepthStencil = d3d12.DEPTH_STENCIL_VALUE{Depth = 1, Stencil = 0},
	}

	hr = renderer.device->CreateCommittedResource(
		&heap_props,
		{},
		&depthDesc,
		d3d12.RESOURCE_STATES{.DEPTH_WRITE},
		&clearValue,
		d3d12.IResource_UUID,
		(^rawptr)(&renderer.depthBuffer),
	)
	check(hr, "Failed to create depth buffer")

	handle: d3d12.CPU_DESCRIPTOR_HANDLE
	renderer.dsvDescriptorHeap->GetCPUDescriptorHandleForHeapStart(&handle)
	renderer.device->CreateDepthStencilView(renderer.depthBuffer, nil, handle)
}
create_root_signature :: proc() -> ^d3d12.IRootSignature {
	hr: d3d12.HRESULT
	desc := d3d12.VERSIONED_ROOT_SIGNATURE_DESC {
		Version = ._1_0,
	}
	srv_range := d3d12.DESCRIPTOR_RANGE {
		RangeType                         = .SRV,
		NumDescriptors                    = 1,
		BaseShaderRegister                = 1,
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
	root_params: [4]d3d12.ROOT_PARAMETER

	root_params[0] = {
		ParameterType    = .CBV,
		ShaderVisibility = .VERTEX,
	}
	root_params[0].Descriptor = {
		ShaderRegister = 0,
		RegisterSpace  = 0,
	}

	root_params[1] = {
		ParameterType    = .SRV,
		ShaderVisibility = .VERTEX,
	}
	root_params[1].Descriptor = {
		ShaderRegister = 0,
		RegisterSpace  = 0,
	}

	root_params[2] = {
		ParameterType    = .DESCRIPTOR_TABLE,
		ShaderVisibility = .PIXEL,
	}
	root_params[2].DescriptorTable = {
		NumDescriptorRanges = 1,
		pDescriptorRanges   = &srv_range,
	}

	root_params[3] = {
		ParameterType    = .DESCRIPTOR_TABLE,
		ShaderVisibility = .PIXEL,
	}
	root_params[3].DescriptorTable = {
		NumDescriptorRanges = 1,
		pDescriptorRanges   = &sampler_range,
	}

	desc.Desc_1_0 = {
		NumParameters     = 4,
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
		(^rawptr)(&renderer.rootSignature),
	)
	check(hr, "Failed creating root signature")
	serialized_desc->Release()
	return renderer.rootSignature
}
create_pipeline :: proc() -> ^d3d12.IPipelineState {
	hr: d3d12.HRESULT

	vs: ^d3d12.IBlob = nil
	ps: ^d3d12.IBlob = nil

	compile_shaders("base.hlsl", &vs, &ps)

	vertex_format: []d3d12.INPUT_ELEMENT_DESC = {
		{SemanticName = "POSITION", Format = .R32G32B32_FLOAT, InputSlotClass = .PER_VERTEX_DATA},
		{
			SemanticName = "NORMAL",
			Format = .R32G32B32_FLOAT,
			AlignedByteOffset = size_of(f32) * 3,
			InputSlotClass = .PER_VERTEX_DATA,
		},
		{
			SemanticName = "COLOR",
			Format = .R32G32B32_FLOAT,
			AlignedByteOffset = size_of(f32) * 6,
			InputSlotClass = .PER_VERTEX_DATA,
		},
		{
			SemanticName = "TEXCOORD",
			Format = .R32G32_FLOAT,
			AlignedByteOffset = size_of(f32) * 9,
			InputSlotClass = .PER_VERTEX_DATA,
		},
		{
			SemanticName = "INDEX",
			Format = .R32_UINT,
			AlignedByteOffset = size_of(f32) * 11,
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
		DepthStencilState = {
			DepthEnable = true,
			DepthWriteMask = d3d12.DEPTH_WRITE_MASK.ALL,
			DepthFunc = d3d12.COMPARISON_FUNC.LESS,
			StencilEnable = false,
		},
		InputLayout = {
			pInputElementDescs = &vertex_format[0],
			NumElements = u32(len(vertex_format)),
		},
		PrimitiveTopologyType = .TRIANGLE,
		NumRenderTargets = 1,
		RTVFormats = {0 = .R8G8B8A8_UNORM, 1 ..< 7 = .UNKNOWN},
		DSVFormat = .D32_FLOAT,
		SampleDesc = {Count = 1, Quality = 0},
	}

	hr = renderer.device->CreateGraphicsPipelineState(
		&pipeline_state_desc,
		d3d12.IPipelineState_UUID,
		(^rawptr)(&renderer.worldPipeline),
	)
	check(hr, "Pipeline creation failed")

	vs->Release()
	ps->Release()

	return renderer.worldPipeline
}
create_noise_tex :: proc() {
	load_texture("renderer/assets/noise1.jpg", &noiseTexture)
}
create_matrices_buffer :: proc() {
	hr: d3d12.HRESULT

	heap_props := d3d12.HEAP_PROPERTIES {
		Type = .UPLOAD,
	}

	bufferSizeBytes: int = 4 * 4 * 4 * 1024

	resource_desc := d3d12.RESOURCE_DESC {
		Dimension = .BUFFER,
		Alignment = 0,
		Width = u64(bufferSizeBytes),
		Height = 1,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .UNKNOWN,
		SampleDesc = {Count = 1, Quality = 0},
		Layout = .ROW_MAJOR,
		Flags = {},
	}

	hr = renderer.device->CreateCommittedResource(
		&heap_props,
		{},
		&resource_desc,
		d3d12.RESOURCE_STATE_GENERIC_READ,
		nil,
		d3d12.IResource_UUID,
		(^rawptr)(&matrixBuffer),
	)
	check(hr, "Failed creating ssbo buffer")

	read_range: d3d12.RANGE

	val: rawptr

	hr = matrixBuffer->Map(0, &read_range, &val)
	check(hr, "Failed to map ssbo buffer")

	mapped: ^Mat4 = cast(^Mat4)val
	matrixMapped = slice.from_ptr(mapped, 1024)

	matrixMapped[0][0][0] = 0.02
	matrixMapped[0][1][1] = 0.02
	matrixMapped[0][2][2] = 0.02
	matrixMapped[0][3][3] = 1.0
}

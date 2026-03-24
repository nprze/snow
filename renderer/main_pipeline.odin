package renderer

import "core:slice"
import snow "snow:bridge"
import d3d12 "vendor:directx/d3d12"

worldPipeline: ^d3d12.IPipelineState
worldPipelineRootSignature: ^d3d12.IRootSignature
mainTrianangleleBuffer: VertexBuffer
debugDrawBuffer: VertexBuffer
noiseTexture: Texture
matrixBuffer: ^d3d12.IResource
matrixMapped: []Mat4
maxMatrices: u32 = 1024
matricesCounter: u32

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
		(^rawptr)(&worldPipelineRootSignature),
	)
	check(hr, "Failed creating root signature")
	serialized_desc->Release()
	return worldPipelineRootSignature
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
		pRootSignature = worldPipelineRootSignature,
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
		(^rawptr)(&worldPipeline),
	)
	check(hr, "Pipeline creation failed")

	vs->Release()
	ps->Release()

	return worldPipeline
}
create_noise_tex :: proc() {
	load_texture("renderer/assets/noise1.jpg", &noiseTexture)
}
create_matrices_buffer :: proc() {
	hr: d3d12.HRESULT

	heap_props := d3d12.HEAP_PROPERTIES {
		Type = .UPLOAD,
	}

	bufferSizeBytes: int = 4 * 4 * 4 * int(maxMatrices)

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

	matrixMapped[0][0][0] = 1.0
	matrixMapped[0][1][1] = 1.0
	matrixMapped[0][2][2] = 1.0
	matrixMapped[0][3][3] = 1.0

	matricesCounter = 1
}

// matrices buffer utilities
add_matrix :: proc(pos: Vec3, rot: Vec3, scale: Vec3) -> u32 {
	matricesCounter += 1
	assert(matricesCounter < maxMatrices, "matrices buffer is too small")
	matrixMapped[matricesCounter] = snow.mat4_from_transform(pos, rot, scale)
	return matricesCounter
}
add_matrix_mat :: proc(mat: Mat4) -> u32 {
	matricesCounter += 1
	assert(matricesCounter < maxMatrices, "matrices buffer is too small")
	matrixMapped[matricesCounter] = mat
	return matricesCounter
}
modify_matrix :: proc(pos: Vec3, rot: Vec3, scale: Vec3, index: u32) {
	matrixMapped[index] = snow.mat4_from_transform(pos, rot, scale)
}
modify_matrix_mat :: proc(mat: Mat4, index: u32) {
	matrixMapped[index] = mat
}

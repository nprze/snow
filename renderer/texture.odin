package renderer

import "core:c"
import fmt "core:fmt"
import mem "core:mem"
import strings "core:strings"
import d3d12 "vendor:directx/d3d12"
import dxgi "vendor:directx/dxgi"
import stbi "vendor:stb/image"

Texture :: struct {
	width:          u32,
	height:         u32,
	dHandle:        ^d3d12.IResource,
	dSamplerHandle: d3d12.CPU_DESCRIPTOR_HANDLE,
	dSrvHandle:     d3d12.CPU_DESCRIPTOR_HANDLE,
}
maxDescCount: u32 = 16
samplerHeap: ^d3d12.IDescriptorHeap
textureHeap: ^d3d12.IDescriptorHeap
srvSize: u32
samplerSize: u32
nestSrvSamplerIndex: u32 = 0

init_texture_loader :: proc() {
	stbi.set_flip_vertically_on_load(1)
	// sampler heap
	sampler_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC {
		Type           = .SAMPLER,
		NumDescriptors = maxDescCount,
		Flags          = d3d12.DESCRIPTOR_HEAP_FLAGS{.SHADER_VISIBLE},
	}

	hr := renderer.device->CreateDescriptorHeap(
		&sampler_heap_desc,
		d3d12.IDescriptorHeap_UUID,
		cast(^rawptr)&samplerHeap,
	)
	check(hr, "Failed to create sampler heap")
	// SRV heap
	srv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC {
		Type           = .CBV_SRV_UAV,
		NumDescriptors = maxDescCount,
		Flags          = d3d12.DESCRIPTOR_HEAP_FLAGS{.SHADER_VISIBLE},
	}

	hr = renderer.device->CreateDescriptorHeap(
		&srv_heap_desc,
		d3d12.IDescriptorHeap_UUID,
		cast(^rawptr)&textureHeap,
	)
	check(hr, "Failed to create SRV heap")
	// sizes
	srvSize = renderer.device->GetDescriptorHandleIncrementSize(
		d3d12.DESCRIPTOR_HEAP_TYPE.CBV_SRV_UAV,
	)
	samplerSize = renderer.device->GetDescriptorHandleIncrementSize(
		d3d12.DESCRIPTOR_HEAP_TYPE.SAMPLER,
	)
}
cleanup_texture_loader :: proc() {
	samplerHeap->Release()
	textureHeap->Release()
}

load_texture :: proc(path: string, textureOut: ^Texture) {
	// file -> data
	pathCStr: cstring = strings.clone_to_cstring(path)
	width, height, channels: i32
	data := stbi.load(pathCStr, &width, &height, &channels, i32(4))
	if data == nil {
		fmt.printf("Failed to load texture: %s", path)
		assert(false)
	}
	textureOut.width = u32(width)
	textureOut.height = u32(height)

	hr: d3d12.HRESULT

	// create texture
	texture_desc := d3d12.RESOURCE_DESC {
		Dimension = .TEXTURE2D,
		Alignment = 0,
		Width = u64(width),
		Height = u32(height),
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .R8G8B8A8_UNORM,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Layout = .UNKNOWN,
	}
	default_heap := d3d12.HEAP_PROPERTIES{}
	default_heap.Type = d3d12.HEAP_TYPE.DEFAULT

	upload_heap := d3d12.HEAP_PROPERTIES{}
	upload_heap.Type = d3d12.HEAP_TYPE.UPLOAD

	texture: ^d3d12.IResource
	hr = renderer.device->CreateCommittedResource(
		&default_heap,
		d3d12.HEAP_FLAGS{},
		&texture_desc,
		d3d12.RESOURCE_STATES{d3d12.RESOURCE_STATE.COPY_DEST},
		nil,
		d3d12.IResource_UUID,
		cast(^rawptr)&texture,
	)
	check(hr, "Failed to create texture resource")

	footprint := d3d12.PLACED_SUBRESOURCE_FOOTPRINT{}
	num_rows: u32
	row_size: u64
	total_bytes: u64

	renderer.device->GetCopyableFootprints(
		&texture_desc,
		0,
		1,
		0,
		&footprint,
		&num_rows,
		&row_size,
		&total_bytes,
	)

	// create staging buffer
	buffer_desc := d3d12.RESOURCE_DESC {
		Dimension = .BUFFER,
		Alignment = 0,
		Width = total_bytes,
		Height = 1,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .UNKNOWN,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Layout = .ROW_MAJOR,
	}

	texture_upload: ^d3d12.IResource
	hr = renderer.device->CreateCommittedResource(
		&upload_heap,
		d3d12.HEAP_FLAGS{},
		&buffer_desc,
		d3d12.RESOURCE_STATE_GENERIC_READ,
		nil,
		d3d12.IResource_UUID,
		cast(^rawptr)&texture_upload,
	)
	check(hr, "Failed to create texture upload resource")

	// data -> staging buffer
	mapped: rawptr
	texture_upload.Map(texture_upload, 0, nil, &mapped)

	dst := cast(^u8)mapped
	src := cast(^u8)data

	src_row_pitch := width * 4
	dst_row_pitch := footprint.Footprint.RowPitch


	for y in 0 ..< height {
		dst_offset := (^u8)(uintptr(dst) + uintptr(y * i32(dst_row_pitch)))
		src_offset := (^u8)(uintptr(src) + uintptr(y * i32(src_row_pitch)))

		mem.copy(dst_offset, src_offset, int(src_row_pitch))
	}

	texture_upload.Unmap(texture_upload, 0, nil)

	// staging buffer -> texture
	cmdList: ^d3d12.IGraphicsCommandList
	hr = renderer.device->CreateCommandList(
		0,
		.DIRECT,
		renderer.commandAllocator,
		nil,
		d3d12.ICommandList_UUID,
		(^rawptr)(&cmdList),
	)
	check(hr, "Failed to create command list")
	hr = cmdList->Close()
	check(hr, "Failed to close command list")
	hr = cmdList->Reset(renderer.commandAllocator, nil)
	check(hr, "Failed to reset command list")

	src_location := d3d12.TEXTURE_COPY_LOCATION {
		pResource = texture_upload,
		Type      = .PLACED_FOOTPRINT,
	}
	src_location.PlacedFootprint = footprint

	dst_location := d3d12.TEXTURE_COPY_LOCATION {
		pResource        = texture,
		Type             = .SUBRESOURCE_INDEX,
		SubresourceIndex = 0,
	}
	cmdList.CopyTextureRegion(cmdList, &dst_location, 0, 0, 0, &src_location, nil)

	barrier := d3d12.RESOURCE_BARRIER {
		Type = .TRANSITION,
		Transition = d3d12.RESOURCE_TRANSITION_BARRIER {
			pResource = texture,
			Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
			StateBefore = d3d12.RESOURCE_STATES{d3d12.RESOURCE_STATE.COPY_DEST},
			StateAfter = d3d12.RESOURCE_STATES{d3d12.RESOURCE_STATE.PIXEL_SHADER_RESOURCE},
		},
	}

	cmdList.ResourceBarrier(cmdList, 1, &barrier)

	hr = cmdList->Close()
	check(hr, "Failed to close command list")

	fence: Fence
	create_fence(&fence)

	cmdlists := [?]^d3d12.IGraphicsCommandList{cmdList}
	renderer.queue->ExecuteCommandLists(len(cmdlists), (^^d3d12.ICommandList)(&cmdlists[0]))
	fence.fenceValue += 1
	hr = renderer.queue->Signal(fence.dFence, fence.fenceValue)
	check(hr, "Failed to signal fence")

	wait_for_fence(&fence)

	// sampler
	sampler_desc := d3d12.SAMPLER_DESC {
		Filter         = .MIN_MAG_MIP_LINEAR,
		AddressU       = .WRAP,
		AddressV       = .WRAP,
		AddressW       = .WRAP,
		MipLODBias     = 0,
		MaxAnisotropy  = 1,
		ComparisonFunc = .NEVER,
		BorderColor    = {0, 0, 0, 0},
		MinLOD         = 0,
		MaxLOD         = d3d12.FLOAT32_MAX,
	}
	base_sampler_cpu: d3d12.CPU_DESCRIPTOR_HANDLE
	samplerHeap.GetCPUDescriptorHandleForHeapStart(samplerHeap, &base_sampler_cpu)

	sampler_handle := base_sampler_cpu
	sampler_handle.ptr += uint(uintptr(nestSrvSamplerIndex) * uintptr(samplerSize))

	textureOut.dSamplerHandle = sampler_handle

	renderer.device->CreateSampler(&sampler_desc, textureOut.dSamplerHandle)

	// srv
	srv_desc := d3d12.SHADER_RESOURCE_VIEW_DESC {
		Format                  = .R8G8B8A8_UNORM,
		ViewDimension           = .TEXTURE2D,
		Shader4ComponentMapping = d3d12.DEFAULT_SHADER_4_COMPONENT_MAPPING,
	}

	srv_desc.Texture2D = d3d12.TEX2D_SRV {
		MostDetailedMip     = 0,
		MipLevels           = 1,
		ResourceMinLODClamp = 0,
	}

	base_srv_cpu: d3d12.CPU_DESCRIPTOR_HANDLE
	textureHeap->GetCPUDescriptorHandleForHeapStart(&base_srv_cpu)

	srv_handle := base_srv_cpu
	srv_handle.ptr += uint(uintptr(nestSrvSamplerIndex) * uintptr(srvSize))

	textureOut.dSrvHandle = srv_handle

	renderer.device->CreateShaderResourceView(texture, &srv_desc, textureOut.dSrvHandle)

	// output
	textureOut.dHandle = texture
	nestSrvSamplerIndex += 1

	// cleanup
	stbi.image_free(data)
	texture_upload->Release()
	cmdList->Release()
	cleanup_fence(&fence)
}
cleanup_texture :: proc(texture: ^Texture) {
	texture.dHandle->Release()
}

package renderer

import fmt "core:fmt"
import "core:math"
import mem "core:mem"
import d3d12 "vendor:directx/d3d12"
import dxgi "vendor:directx/dxgi"

UniformData :: struct {
	camera: [16]f32,
}

currentData: UniformData
dBuffer: ^d3d12.IResource
cbvHeap: ^d3d12.IDescriptorHeap
heapHandle: d3d12.CPU_DESCRIPTOR_HANDLE

create_camera :: proc() {
	hr: d3d12.HRESULT
	bufferSize: int = int(math.ceil(f32(f32(size_of(UniformData)) / f32(256))) * 256)
	// cbv heap
	cbv_heap_desc := d3d12.DESCRIPTOR_HEAP_DESC {
		Type           = .CBV_SRV_UAV,
		NumDescriptors = 16,
		Flags          = d3d12.DESCRIPTOR_HEAP_FLAGS{.SHADER_VISIBLE},
	}

	hr = renderer.device.CreateDescriptorHeap(
		renderer.device,
		&cbv_heap_desc,
		d3d12.IDescriptorHeap_UUID,
		cast(^rawptr)&cbvHeap,
	)
	check(hr, "Failed to create CBV heap")
	// resource create
	cam_buffer_desc := d3d12.RESOURCE_DESC {
		Dimension = .BUFFER,
		Alignment = 0,
		Width = u64(bufferSize),
		Height = 1,
		DepthOrArraySize = 1,
		MipLevels = 1,
		Format = .UNKNOWN,
		SampleDesc = dxgi.SAMPLE_DESC{Count = 1, Quality = 0},
		Layout = .ROW_MAJOR,
	}

	heap := d3d12.HEAP_PROPERTIES{}
	heap.Type = d3d12.HEAP_TYPE.UPLOAD

	hr = renderer.device.CreateCommittedResource(
		renderer.device,
		&heap,
		d3d12.HEAP_FLAGS{},
		&cam_buffer_desc,
		d3d12.RESOURCE_STATE_GENERIC_READ,
		nil,
		d3d12.IResource_UUID,
		cast(^rawptr)&dBuffer,
	)
	check(hr, "Failed to create texture resource")

	// identity
	mem.set(&currentData, 0, size_of(currentData))
	currentData.camera[0] = 1
	currentData.camera[5] = 1
	currentData.camera[10] = 1
	currentData.camera[15] = 1

	// copy data
	mapped: rawptr
	dBuffer.Map(dBuffer, 0, nil, &mapped)
	mem.copy(mapped, &currentData, bufferSize)
	dBuffer.Unmap(dBuffer, 0, nil)

	// buffer view
	cbv_desc := d3d12.CONSTANT_BUFFER_VIEW_DESC {
		BufferLocation = dBuffer.GetGPUVirtualAddress(dBuffer),
		SizeInBytes    = u32(bufferSize),
	}

	cbvHeap.GetCPUDescriptorHandleForHeapStart(cbvHeap, &heapHandle)

	renderer.device.CreateConstantBufferView(renderer.device, &cbv_desc, heapHandle)
}

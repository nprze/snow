package renderer

import fmt "core:fmt"
import "core:math"
import "core:mem"
import d3d12 "vendor:directx/d3d12"

VertexBuffer :: struct {
	dBuffer:        ^d3d12.IResource, // short for directx12 buffer
	dBufferView:    d3d12.VERTEX_BUFFER_VIEW,
	mappedData:     rawptr,
	vertexCount:    int,
	maxVertexCount: int,
}

initialize_vbuffer :: proc(buffer: ^VertexBuffer, vertexCount: int, oneVertexSize: int) { 	// will round sizeBytes down to the nearest multiple of the vertex size
	hr: d3d12.HRESULT


	heap_props := d3d12.HEAP_PROPERTIES {
		Type = .UPLOAD,
	}

	buffer.maxVertexCount = vertexCount
	bufferSizeBytes: int = buffer.maxVertexCount * oneVertexSize

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
		(^rawptr)(&buffer.dBuffer),
	)
	check(hr, "Failed creating vertex buffer")

	map_vbuffer(buffer)

	buffer.dBufferView = d3d12.VERTEX_BUFFER_VIEW {
		BufferLocation = buffer.dBuffer->GetGPUVirtualAddress(),
		StrideInBytes  = u32(size_of(BasicVertex)),
		SizeInBytes    = u32(bufferSizeBytes),
	}
}

add_vertices :: proc(buffer: ^VertexBuffer, vertices: []BasicVertex) {
	write(buffer, vertices)
}
add_vertices_ui :: proc(buffer: ^VertexBuffer, vertices: []UiVertex) {
	write_ui(buffer, vertices)
}

write :: proc(buffer: ^VertexBuffer, vertices: []BasicVertex) {
	assert(buffer.vertexCount + len(vertices) <= buffer.maxVertexCount)
	mem.copy(buffer.mappedData, rawptr(&vertices[0]), size_of(BasicVertex) * len(vertices))
	buffer.vertexCount += len(vertices)
}
write_ui :: proc(buffer: ^VertexBuffer, vertices: []UiVertex) {
	assert(buffer.vertexCount + len(vertices) <= buffer.maxVertexCount)
	mem.copy(buffer.mappedData, rawptr(&vertices[0]), size_of(UiVertex) * len(vertices))
	buffer.vertexCount += len(vertices)
}

map_vbuffer :: proc(buffer: ^VertexBuffer) {
	hr: d3d12.HRESULT
	read_range: d3d12.RANGE

	hr = buffer.dBuffer->Map(0, &read_range, &buffer.mappedData)
	check(hr, "Failed to map vertex buffer")
}

unmap_vbuffer :: proc(buffer: ^VertexBuffer) {
	buffer.dBuffer->Unmap(0, nil)
	buffer.mappedData = nil
}

clean_vbuffer :: proc(buffer: ^VertexBuffer) {
	if (buffer.mappedData != nil) {
		unmap_vbuffer(buffer)
	}
	if buffer.dBuffer != nil {
		buffer.dBuffer->Release()
		buffer.dBuffer = nil
	}
	buffer.mappedData = nil
	buffer.vertexCount = 0
	buffer.maxVertexCount = 0
}
reset_vbuffer :: proc(buffer: ^VertexBuffer) {
	buffer.vertexCount = 0
}

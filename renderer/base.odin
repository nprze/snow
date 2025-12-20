package renderer

import "core:fmt"
import "core:mem"
import "core:sys/windows"
import d3d12 "vendor:directx/d3d12"
import d3dc "vendor:directx/d3d_compiler"
import dxgi "vendor:directx/dxgi"
import glfw "vendor:glfw"

RENDERTARGETS_COUNT :: 2

Renderer :: struct {
	displayWidth:       u32,
	displayHeight:      u32,
	windowHandle:       glfw.WindowHandle,
	factory:            ^dxgi.IFactory4,
	adapter:            ^dxgi.IAdapter1,
	device:             ^d3d12.IDevice,
	queue:              ^d3d12.ICommandQueue,
	swapchain:          ^dxgi.ISwapChain3,
	commandAllocator:   ^d3d12.ICommandAllocator,
	commandList:        ^d3d12.IGraphicsCommandList,
	pipeline:           ^d3d12.IPipelineState,
	rootSignature:      ^d3d12.IRootSignature,
	fenceValue:         u64,
	frameFinishedFence: ^d3d12.IFence,
	fenceEvent:         windows.HANDLE,
	renderTargets:      [RENDERTARGETS_COUNT]^d3d12.IResource,
	descriptorHeap:     ^d3d12.IDescriptorHeap,
	vertexBufferView:   d3d12.VERTEX_BUFFER_VIEW,
}

renderer: Renderer

create_renderer :: proc(width: u32, height: u32, window: glfw.WindowHandle) {
	renderer.windowHandle = window
	renderer.displayWidth = width
	renderer.displayHeight = height
	create_dxgi_factory()
	create_adapter()
	create_device()
	create_queue()
	create_swap_chain()
	// Descripors

	hr: d3d12.HRESULT

	{
		desc := d3d12.DESCRIPTOR_HEAP_DESC {
			NumDescriptors = RENDERTARGETS_COUNT,
			Type           = .RTV,
			Flags          = {},
		}

		hr = renderer.device->CreateDescriptorHeap(
			&desc,
			d3d12.IDescriptorHeap_UUID,
			(^rawptr)(&renderer.descriptorHeap),
		)
		check(hr, "Failed creating descriptor heap")
	}

	// Fetch render targets

	{
		rtv_descriptor_size: u32 = renderer.device->GetDescriptorHandleIncrementSize(.RTV)

		rtv_descriptor_handle: d3d12.CPU_DESCRIPTOR_HANDLE
		renderer.descriptorHeap->GetCPUDescriptorHandleForHeapStart(&rtv_descriptor_handle)

		for i: u32 = 0; i < RENDERTARGETS_COUNT; i += 1 {
			hr = renderer.swapchain->GetBuffer(
				i,
				d3d12.IResource_UUID,
				(^rawptr)(&renderer.renderTargets[i]),
			)
			check(hr, "Failed getting render target")
			renderer.device->CreateRenderTargetView(
				renderer.renderTargets[i],
				nil,
				rtv_descriptor_handle,
			)
			rtv_descriptor_handle.ptr += uint(rtv_descriptor_size)
		}
	}

	// The command allocator is used to create the commandlist that is used to tell the GPU what to draw
	hr = renderer.device->CreateCommandAllocator(
		.DIRECT,
		d3d12.ICommandAllocator_UUID,
		(^rawptr)(&renderer.commandAllocator),
	)
	check(hr, "Failed creating command allocator")

	create_root_signature()
	create_pipeline()

	// Create the commandlist that is reused further down.
	hr = renderer.device->CreateCommandList(
		0,
		.DIRECT,
		renderer.commandAllocator,
		renderer.pipeline,
		d3d12.ICommandList_UUID,
		(^rawptr)(&renderer.commandList),
	)
	check(hr, "Failed to create command list")
	hr = renderer.commandList->Close()
	check(hr, "Failed to close command list")

	vertex_buffer: ^d3d12.IResource

	{
		// The position and color data for the triangle's vertices go together per-vertex
		vertices := [?]f32 {
			// pos            color
			0.0,
			0.5,
			0.0,
			1,
			0,
			0,
			0,
			0.5,
			-0.5,
			0.0,
			0,
			1,
			0,
			0,
			-0.5,
			-0.5,
			0.0,
			0,
			0,
			1,
			0,
		}

		heap_props := d3d12.HEAP_PROPERTIES {
			Type = .UPLOAD,
		}

		vertex_buffer_size := len(vertices) * size_of(vertices[0])

		resource_desc := d3d12.RESOURCE_DESC {
			Dimension = .BUFFER,
			Alignment = 0,
			Width = u64(vertex_buffer_size),
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
			(^rawptr)(&vertex_buffer),
		)
		check(hr, "Failed creating vertex buffer")

		gpu_data: rawptr
		read_range: d3d12.RANGE

		hr = vertex_buffer->Map(0, &read_range, &gpu_data)
		check(hr, "Failed creating verex buffer resource")

		mem.copy(gpu_data, &vertices[0], vertex_buffer_size)
		vertex_buffer->Unmap(0, nil)

		renderer.vertexBufferView = d3d12.VERTEX_BUFFER_VIEW {
			BufferLocation = vertex_buffer->GetGPUVirtualAddress(),
			StrideInBytes  = u32(vertex_buffer_size / 3),
			SizeInBytes    = u32(vertex_buffer_size),
		}
	}

	{
		hr = renderer.device->CreateFence(
			renderer.fenceValue,
			{},
			d3d12.IFence_UUID,
			(^rawptr)(&renderer.frameFinishedFence),
		)
		check(hr, "Failed to create fence")
		renderer.fenceValue += 1
		manual_reset: windows.BOOL = false
		initial_state: windows.BOOL = false
		renderer.fenceEvent = windows.CreateEventW(nil, manual_reset, initial_state, nil)
		if renderer.fenceEvent == nil {
			fmt.println("Failed to create fence event")
			return
		}
	}
	main_loop(window)
}

main_loop :: proc(window: glfw.WindowHandle) {
	hr: d3d12.HRESULT
	frame_index := renderer.swapchain->GetCurrentBackBufferIndex()

	for !glfw.WindowShouldClose(window) {
		glfw.PollEvents()

		hr = renderer.commandAllocator->Reset()
		check(hr, "Failed resetting command allocator")

		hr = renderer.commandList->Reset(renderer.commandAllocator, renderer.pipeline)
		check(hr, "Failed to reset command list")

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

		// This state is reset everytime the cmd list is reset, so we need to rebind it
		renderer.commandList->SetGraphicsRootSignature(renderer.rootSignature)
		renderer.commandList->RSSetViewports(1, &viewport)
		renderer.commandList->RSSetScissorRects(1, &scissor_rect)

		to_render_target_barrier := d3d12.RESOURCE_BARRIER {
			Type  = .TRANSITION,
			Flags = {},
		}

		to_render_target_barrier.Transition = {
			pResource   = renderer.renderTargets[frame_index],
			StateBefore = d3d12.RESOURCE_STATE_PRESENT,
			StateAfter  = {.RENDER_TARGET},
			Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
		}

		renderer.commandList->ResourceBarrier(1, &to_render_target_barrier)

		rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
		renderer.descriptorHeap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)

		if (frame_index > 0) {
			s := renderer.device->GetDescriptorHandleIncrementSize(.RTV)
			rtv_handle.ptr += uint(frame_index * s)
		}

		renderer.commandList->OMSetRenderTargets(1, &rtv_handle, false, nil)

		// clear backbuffer
		clearcolor := [?]f32{0.05, 0.05, 0.05, 1.0}
		renderer.commandList->ClearRenderTargetView(rtv_handle, &clearcolor, 0, nil)

		// draw call
		renderer.commandList->IASetPrimitiveTopology(.TRIANGLELIST)
		renderer.commandList->IASetVertexBuffers(0, 1, &renderer.vertexBufferView)
		renderer.commandList->DrawInstanced(3, 1, 0, 0)

		to_present_barrier := to_render_target_barrier
		to_present_barrier.Transition.StateBefore = {.RENDER_TARGET}
		to_present_barrier.Transition.StateAfter = d3d12.RESOURCE_STATE_PRESENT

		renderer.commandList->ResourceBarrier(1, &to_present_barrier)

		hr = renderer.commandList->Close()
		check(hr, "Failed to close command list")

		// execute
		cmdlists := [?]^d3d12.IGraphicsCommandList{renderer.commandList}
		renderer.queue->ExecuteCommandLists(len(cmdlists), (^^d3d12.ICommandList)(&cmdlists[0]))

		// present
		{
			flags: dxgi.PRESENT
			params: dxgi.PRESENT_PARAMETERS
			hr = renderer.swapchain->Present1(1, flags, &params)
			check(hr, "Present failed")
		}

		// wait for frame to finish
		{
			current_fence_value := renderer.fenceValue

			hr = renderer.queue->Signal(renderer.frameFinishedFence, current_fence_value)
			check(hr, "Failed to signal fence")

			renderer.fenceValue += 1
			completed := renderer.frameFinishedFence->GetCompletedValue()

			if completed < current_fence_value {
				hr = renderer.frameFinishedFence->SetEventOnCompletion(
					current_fence_value,
					renderer.fenceEvent,
				)
				check(hr, "Failed to set event on completion flag")
				windows.WaitForSingleObject(renderer.fenceEvent, windows.INFINITE)
			}

			frame_index = renderer.swapchain->GetCurrentBackBufferIndex()
		}
	}
}

create_window :: proc(width: i32, height: i32) -> glfw.WindowHandle {
	if !glfw.Init() {
		panic("Failed to initialize GLFW")
	}

	glfw.WindowHint(glfw.CLIENT_API, glfw.NO_API)
	glfw.WindowHint(glfw.RESIZABLE, glfw.TRUE)

	renderer.windowHandle = glfw.CreateWindow(width, height, "animation example", nil, nil)
	if renderer.windowHandle == nil {
		panic("Failed to create GLFW window")
	}

	return renderer.windowHandle
}
delete_window :: proc(handle: glfw.WindowHandle) {
	glfw.DestroyWindow(handle)
	glfw.Terminate()
}
create_dxgi_factory :: proc() -> ^dxgi.IFactory4 {
	hr: d3d12.HRESULT

	flags: dxgi.CREATE_FACTORY

	when ODIN_DEBUG {
		flags += {.DEBUG}
	}

	hr = dxgi.CreateDXGIFactory2(flags, dxgi.IFactory4_UUID, cast(^rawptr)&renderer.factory)
	check(hr, "Failed creating factory")

	return renderer.factory
}
create_adapter :: proc() -> ^dxgi.IAdapter1 {
	error_not_found := dxgi.HRESULT(-142213123)

	for i: u32 = 0;
	    renderer.factory->EnumAdapters1(i, &renderer.adapter) != error_not_found;
	    i += 1 {
		desc: dxgi.ADAPTER_DESC1
		renderer.adapter->GetDesc1(&desc)
		if .SOFTWARE in desc.Flags {
			continue
		}

		if d3d12.CreateDevice(
			   (^dxgi.IUnknown)(renderer.adapter),
			   ._12_0,
			   dxgi.IDevice_UUID,
			   nil,
		   ) >=
		   0 {
			break
		} else {
			fmt.println("Failed to create device")
		}
	}

	if renderer.adapter == nil {
		check(-1, "Could not find hardware adapter")
	}
	return renderer.adapter
}
create_device :: proc() -> ^d3d12.IDevice {
	hr: d3d12.HRESULT
	hr = d3d12.CreateDevice(
		(^dxgi.IUnknown)(renderer.adapter),
		._12_0,
		d3d12.IDevice_UUID,
		(^rawptr)(&renderer.device),
	)
	check(hr, "Failed to create device")
	return renderer.device
}
create_queue :: proc() -> ^d3d12.ICommandQueue {
	hr: d3d12.HRESULT
	desc := d3d12.COMMAND_QUEUE_DESC {
		Type = .DIRECT,
	}
	hr = renderer.device->CreateCommandQueue(
		&desc,
		d3d12.ICommandQueue_UUID,
		(^rawptr)(&renderer.queue),
	)
	check(hr, "Failed creating command queue")
	return renderer.queue
}
create_swap_chain :: proc() -> ^dxgi.ISwapChain3 {
	hr: d3d12.HRESULT

	desc := dxgi.SWAP_CHAIN_DESC1 {
		Width = u32(renderer.displayWidth),
		Height = u32(renderer.displayHeight),
		Format = .R8G8B8A8_UNORM,
		SampleDesc = {Count = 1, Quality = 0},
		BufferUsage = {.RENDER_TARGET_OUTPUT},
		BufferCount = RENDERTARGETS_COUNT,
		Scaling = .NONE,
		SwapEffect = .FLIP_DISCARD,
		AlphaMode = .UNSPECIFIED,
	}

	window_handle := glfw.GetWin32Window(renderer.windowHandle)

	hr = renderer.factory->CreateSwapChainForHwnd(
		(^dxgi.IUnknown)(renderer.queue),
		d3d12.HWND(window_handle),
		&desc,
		nil,
		nil,
		(^^dxgi.ISwapChain1)(&renderer.swapchain),
	)
	check(hr, "Failed to create swap chain")

	return renderer.swapchain
}

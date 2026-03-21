package renderer

import "core:fmt"
import "core:sys/windows"
import snow "snow:bridge"
import d3d12 "vendor:directx/d3d12"
import d3dc "vendor:directx/d3d_compiler"
import dxgi "vendor:directx/dxgi"
import glfw "vendor:glfw"

RENDERTARGETS_COUNT :: 2

BasicVertex :: struct {
	// include allignment padding here.
	position:    Vec3,
	normal:      Vec3,
	color:       Vec3,
	uv:          Vec2,
	matrixIndex: u32,
}

Fence :: struct {
	fenceValue: u64,
	dFence:     ^d3d12.IFence,
	fenceEvent: windows.HANDLE,
}

Renderer :: struct {
	// utils
	displayWidth:         u32,
	displayHeight:        u32,
	oneOverDisplayWidth:  f32,
	oneOverDisplayHeight: f32,
	// general
	debug:                ^d3d12.IDebug,
	windowHandle:         glfw.WindowHandle,
	factory:              ^dxgi.IFactory4,
	adapter:              ^dxgi.IAdapter1,
	device:               ^d3d12.IDevice,
	queue:                ^d3d12.ICommandQueue,
	swapchain:            ^dxgi.ISwapChain3,
	commandAllocator:     ^d3d12.ICommandAllocator,
	commandList:          ^d3d12.IGraphicsCommandList,
	renderTargets:        [RENDERTARGETS_COUNT]^d3d12.IResource,
	renderFinishedFence:  Fence,
	frameIndex:           u32,
	rsvDescriptorHeap:    ^d3d12.IDescriptorHeap,
	// depth
	dsvDescriptorHeap:    ^d3d12.IDescriptorHeap,
	depthBuffer:          ^d3d12.IResource,
	// world
	worldPipeline:        ^d3d12.IPipelineState,
	rootSignature:        ^d3d12.IRootSignature,
	// ui
	uiPipeline:           ^d3d12.IPipelineState,
	uiRootSignature:      ^d3d12.IRootSignature,
	uiVertexBuffer:       VertexBuffer,
	consolasFont:         Font,
}

renderer: Renderer

create_renderer :: proc(width: u32, height: u32, window: glfw.WindowHandle) {
	// general
	renderer.windowHandle = window
	renderer.displayWidth = width
	renderer.displayHeight = height
	renderer.oneOverDisplayWidth = 1.0 / f32(width)
	renderer.oneOverDisplayHeight = 1.0 / f32(height)
	create_debug()
	create_dxgi_factory()
	create_adapter()
	create_device()
	create_queue()
	create_swap_chain()
	create_rtv_descriptor_heap()
	descHandle: d3d12.CPU_DESCRIPTOR_HANDLE = fetch_render_targets()
	create_command_allocator()
	create_fence(&renderer.renderFinishedFence)
	init_texture_loader()
	renderer.frameIndex = renderer.swapchain->GetCurrentBackBufferIndex()
	// world pipeline specific
	create_root_signature()
	create_depth_buffer()
	create_pipeline()
	create_camera()
	create_matrices_buffer()
	create_command_list(&renderer.commandList)
	initialize_vbuffer(&mainTrianangleleBuffer, 1000000, size_of(BasicVertex))
	create_UV_sphere({0, 0, 2}, 0.5, 20, 20, {0.8, 0.8, 0.9})
	create_rect({0, -2, 0}, {0, 1, 0}, {1, 1, 1}, 2)
	// ui specific
	ui_init()
	create_noise_tex()
	ugly_load_gltf("renderer/assets/bone/scene.gltf")
}
cleanup_renderer :: proc() {
	// wait
	renderer.renderFinishedFence.fenceValue += 1
	renderer.queue->Signal(
		renderer.renderFinishedFence.dFence,
		renderer.renderFinishedFence.fenceValue,
	)
	renderer.renderFinishedFence.dFence->SetEventOnCompletion(
		renderer.renderFinishedFence.fenceValue,
		renderer.renderFinishedFence.fenceEvent,
	)
	windows.WaitForSingleObject(renderer.renderFinishedFence.fenceEvent, windows.INFINITE)
	// cam
	cleanup_camera()
	// ui
	ui_cleanup()
	// main
	cleanup_vbuffer(&mainTrianangleleBuffer)
	renderer.worldPipeline->Release()
	renderer.rootSignature->Release()
	cleanup_texture(&noiseTexture)
	// depth
	renderer.depthBuffer->Release()
	renderer.dsvDescriptorHeap->Release()
	for i: u32 = 0; i < RENDERTARGETS_COUNT; i += 1 {
		renderer.renderTargets[i]->Release()
	}
	cleanup_fence(&renderer.renderFinishedFence)
	renderer.rsvDescriptorHeap->Release()
	renderer.commandList->Release()
	renderer.commandAllocator->Release()
	renderer.swapchain->Release()
	renderer.queue->Release()
	debugDevice: ^d3d12.IDebugDevice
	renderer.device->QueryInterface(d3d12.IDebugDevice_UUID, cast(^rawptr)&debugDevice)
	if (debugDevice != nil) {
		debugDevice->ReportLiveDeviceObjects({.DETAIL})
	}
	// for some reason, the device still has a ref after one Release() call, so calling twice
	renderer.device->Release()
	renderer.device->Release()
	renderer.adapter->Release()
	renderer.factory->Release()
	renderer.debug->Release()
}
before_update :: proc() {
	glfw.PollEvents()
	ui_begin()
}
post_update :: proc() {
	ui_end()
}
render_all :: proc(ctx: snow.UpdateContext) {
	hr: d3d12.HRESULT
	// update
	camera_update(ctx.dt)
	// render
	hr = renderer.commandAllocator->Reset()
	check(hr, "Failed resetting command allocator")

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

	hr = renderer.commandList->Reset(renderer.commandAllocator, renderer.worldPipeline)
	check(hr, "Failed to reset command list")

	renderer.commandList->SetGraphicsRootSignature(renderer.rootSignature)
	renderer.commandList->RSSetViewports(1, &viewport)
	renderer.commandList->RSSetScissorRects(1, &scissor_rect)

	to_render_target_barrier := d3d12.RESOURCE_BARRIER {
		Type  = .TRANSITION,
		Flags = {},
	}

	to_render_target_barrier.Transition = {
		pResource   = renderer.renderTargets[renderer.frameIndex],
		StateBefore = d3d12.RESOURCE_STATE_PRESENT,
		StateAfter  = {.RENDER_TARGET},
		Subresource = d3d12.RESOURCE_BARRIER_ALL_SUBRESOURCES,
	}

	renderer.commandList->ResourceBarrier(1, &to_render_target_barrier)

	rtv_handle: d3d12.CPU_DESCRIPTOR_HANDLE
	renderer.rsvDescriptorHeap->GetCPUDescriptorHandleForHeapStart(&rtv_handle)

	if (renderer.frameIndex > 0) {
		s := renderer.device->GetDescriptorHandleIncrementSize(.RTV)
		rtv_handle.ptr += uint(renderer.frameIndex * s)
	}
	depthHandle: d3d12.CPU_DESCRIPTOR_HANDLE
	renderer.dsvDescriptorHeap->GetCPUDescriptorHandleForHeapStart(&depthHandle)

	renderer.commandList->OMSetRenderTargets(1, &rtv_handle, false, &depthHandle)

	// clear backbuffer
	clearcolor := [?]f32{0.05, 0.05, 0.05, 1.0}
	renderer.commandList->ClearRenderTargetView(rtv_handle, &clearcolor, 0, nil)
	renderer.commandList->ClearDepthStencilView(
		depthHandle,
		d3d12.CLEAR_FLAGS{.DEPTH},
		1,
		0,
		0,
		nil,
	)

	// bind descriptors
	heaps := [?]^d3d12.IDescriptorHeap{textureHeap, samplerHeap}

	camera_gpu: d3d12.GPU_VIRTUAL_ADDRESS
	matrices_gpu: d3d12.GPU_VIRTUAL_ADDRESS
	base_sbv_gpu: d3d12.GPU_DESCRIPTOR_HANDLE
	base_sampler_gpu: d3d12.GPU_DESCRIPTOR_HANDLE

	camera_gpu = cameraData.dBuffer->GetGPUVirtualAddress()
	matrices_gpu = matrixBuffer->GetGPUVirtualAddress()
	textureHeap->GetGPUDescriptorHandleForHeapStart(&base_sbv_gpu)
	testure_gpu := base_sbv_gpu
	testure_gpu.ptr += u64(1) * u64(texViewSize)
	samplerHeap->GetGPUDescriptorHandleForHeapStart(&base_sampler_gpu)
	sampler_gpu := base_sampler_gpu
	sampler_gpu.ptr += u64(1) * u64(samplerSize)

	renderer.commandList->SetDescriptorHeaps(len(heaps), &heaps[0])
	renderer.commandList->SetGraphicsRootConstantBufferView(0, camera_gpu)
	renderer.commandList->SetGraphicsRootShaderResourceView(1, matrices_gpu)
	renderer.commandList->SetGraphicsRootDescriptorTable(2, testure_gpu)
	renderer.commandList->SetGraphicsRootDescriptorTable(3, sampler_gpu)

	// draw call
	renderer.commandList->IASetPrimitiveTopology(.TRIANGLELIST)
	renderer.commandList->IASetVertexBuffers(0, 1, &mainTrianangleleBuffer.dBufferView)
	renderer.commandList->DrawInstanced(u32(mainTrianangleleBuffer.vertexCount), 1, 0, 0)

	// draw ui
	ui_render()

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
		current_fence_value := renderer.renderFinishedFence.fenceValue

		hr = renderer.queue->Signal(renderer.renderFinishedFence.dFence, current_fence_value)
		check(hr, "Failed to signal fence")

		renderer.renderFinishedFence.fenceValue += 1
		completed := renderer.renderFinishedFence.dFence->GetCompletedValue()

		if completed < current_fence_value {
			hr = renderer.renderFinishedFence.dFence->SetEventOnCompletion(
				current_fence_value,
				renderer.renderFinishedFence.fenceEvent,
			)
			check(hr, "Failed to set event on completion flag")
			windows.WaitForSingleObject(renderer.renderFinishedFence.fenceEvent, windows.INFINITE)
		}

		renderer.frameIndex = renderer.swapchain->GetCurrentBackBufferIndex()
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
	error_not_found := dxgi.HRESULT(0x887A0002)
	found: bool = false
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
			found = true
			break
		}
	}
	if !found {
		check(-1, "Failed to find suitable adapter")
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
create_debug :: proc() {
	hr: d3d12.HRESULT

	hr = d3d12.GetDebugInterface(d3d12.IDebug_UUID, cast(^rawptr)&renderer.debug)
	if hr < 0 {
		return
	}
	renderer.debug->EnableDebugLayer()
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
create_rtv_descriptor_heap :: proc() -> ^d3d12.IDescriptorHeap {
	hr: d3d12.HRESULT
	desc := d3d12.DESCRIPTOR_HEAP_DESC {
		NumDescriptors = RENDERTARGETS_COUNT,
		Type           = .RTV,
		Flags          = {},
	}

	hr = renderer.device->CreateDescriptorHeap(
		&desc,
		d3d12.IDescriptorHeap_UUID,
		(^rawptr)(&renderer.rsvDescriptorHeap),
	)
	check(hr, "Failed creating descriptor heap")
	return renderer.rsvDescriptorHeap
}
create_command_list :: proc(
	commandListOut: ^^d3d12.IGraphicsCommandList,
) -> ^^d3d12.IGraphicsCommandList {
	hr: d3d12.HRESULT
	hr = renderer.device->CreateCommandList(
		0,
		.DIRECT,
		renderer.commandAllocator,
		renderer.worldPipeline,
		d3d12.ICommandList_UUID,
		(^rawptr)(commandListOut),
	)
	check(hr, "Failed to create command list")
	hr = (commandListOut^)->Close()
	check(hr, "Failed to close command list")
	return commandListOut
}
fetch_render_targets :: proc() -> d3d12.CPU_DESCRIPTOR_HANDLE {
	hr: d3d12.HRESULT
	rtv_descriptor_size: u32 = renderer.device->GetDescriptorHandleIncrementSize(.RTV)

	rtv_descriptor_handle: d3d12.CPU_DESCRIPTOR_HANDLE
	renderer.rsvDescriptorHeap->GetCPUDescriptorHandleForHeapStart(&rtv_descriptor_handle)

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
	return rtv_descriptor_handle
}
create_command_allocator :: proc() -> ^d3d12.ICommandAllocator {
	hr: d3d12.HRESULT
	hr = renderer.device->CreateCommandAllocator(
		.DIRECT,
		d3d12.ICommandAllocator_UUID,
		(^rawptr)(&renderer.commandAllocator),
	)
	check(hr, "Failed creating command allocator")
	return renderer.commandAllocator
}
create_fence :: proc(fenceOut: ^Fence) -> ^Fence {
	hr: d3d12.HRESULT
	hr = renderer.device->CreateFence(
		fenceOut.fenceValue,
		{},
		d3d12.IFence_UUID,
		(^rawptr)(&fenceOut.dFence),
	)
	check(hr, "Failed to create fence")
	fenceOut.fenceValue += 1
	manual_reset: windows.BOOL = false
	initial_state: windows.BOOL = false
	fenceOut.fenceEvent = windows.CreateEventW(nil, manual_reset, initial_state, nil)
	if fenceOut.fenceEvent == nil {
		panic("Failed to create fence event")
	}
	return fenceOut
}
cleanup_fence :: proc(fence: ^Fence) {
	windows.CloseHandle(fence.fenceEvent)
	fence.dFence->Release()
}
wait_for_fence :: proc(fence: ^Fence) {
	hr: d3d12.HRESULT
	if fence.dFence->GetCompletedValue() < fence.fenceValue {
		hr = fence.dFence->SetEventOnCompletion(fence.fenceValue, fence.fenceEvent)
		check(hr, "Failed to set event on completion flag")
		windows.WaitForSingleObject(fence.fenceEvent, windows.INFINITE)
	}
}

compile_shaders :: proc(path: string, vs: ^^d3d12.IBlob, ps: ^^d3d12.IBlob) { 	// don't forget to call release on blobs
	hr: d3d12.HRESULT

	// Compile vertex and pixel shaders
	data: cstring = read_file(fmt.tprintf("renderer/shaders/%s", path))

	data_size: uint = len(data)

	compile_flags: u32 = 0
	when ODIN_DEBUG {
		compile_flags |= u32(d3dc.D3DCOMPILE.DEBUG)
		compile_flags |= u32(d3dc.D3DCOMPILE.SKIP_OPTIMIZATION)
	}

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
		vs,
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
		ps,
		nil,
	)
	check(hr, "Failed to compile pixel shader")
}

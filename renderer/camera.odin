package renderer

import fmt "core:fmt"
import "core:math"
import "core:math/linalg"
import mem "core:mem"
import d3d12 "vendor:directx/d3d12"
import dxgi "vendor:directx/dxgi"
import glfw "vendor:glfw"

UniformData :: struct {
	camera: [16]f32,
}

Camera :: struct {
	position:            Vec3,
	direction:           Vec3,
	up:                  Vec3,
	fov:                 f32,
	aspect:              f32,
	near:                f32,
	far:                 f32,
	yaw:                 f32,
	pitch:               f32,
	movingSpeed:         f32,
	dragSpeed:           f32,
	currentCameraMatrix: UniformData,
	// dx12 stuff
	dBuffer:             ^d3d12.IResource,
	cbvHeap:             ^d3d12.IDescriptorHeap,
	heapHandle:          d3d12.CPU_DESCRIPTOR_HANDLE,
	bufferSize:          int,
}

cameraData: Camera
lastMouseX: f64 = 0
lastMouseY: f64 = 0
firstMouseClick: bool = true

create_camera :: proc() {
	hr: d3d12.HRESULT
	cameraData.bufferSize = int(math.ceil(f32(f32(size_of(UniformData)) / f32(256))) * 256)
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
		cast(^rawptr)&cameraData.cbvHeap,
	)
	check(hr, "Failed to create CBV heap")
	// resource create
	cam_buffer_desc := d3d12.RESOURCE_DESC {
		Dimension = .BUFFER,
		Alignment = 0,
		Width = u64(cameraData.bufferSize),
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
		cast(^rawptr)&cameraData.dBuffer,
	)
	check(hr, "Failed to create texture resource")

	// default values
	cameraData.position = {0, 0, -2}
	cameraData.direction = {0, 0, 1}
	cameraData.up = {0, 1, 0}
	cameraData.fov = math.to_radians_f32(45)
	cameraData.aspect = f32(renderer.displayWidth) / f32(renderer.displayHeight)
	cameraData.near = 0.01
	cameraData.far = 1000.0
	cameraData.yaw = 90

	cameraData.movingSpeed = 2.0
	cameraData.dragSpeed = 1.0

	recalculate_camera()
	copy_camera_data()

	// buffer view
	cbv_desc := d3d12.CONSTANT_BUFFER_VIEW_DESC {
		BufferLocation = cameraData.dBuffer.GetGPUVirtualAddress(cameraData.dBuffer),
		SizeInBytes    = u32(cameraData.bufferSize),
	}

	cameraData.cbvHeap.GetCPUDescriptorHandleForHeapStart(
		cameraData.cbvHeap,
		&cameraData.heapHandle,
	)

	renderer.device.CreateConstantBufferView(renderer.device, &cbv_desc, cameraData.heapHandle)
}
recalculate_camera :: proc() {
	cam := cameraData
	eye := cam.position
	center := cam.position + cam.direction
	up := cam.up
	view := linalg.matrix4_look_at_f32(eye, center, up)
	proj := linalg.matrix4_perspective_f32(cam.fov, cam.aspect, cam.near, cam.far)
	vp := linalg.transpose(proj * view)

	cameraData.currentCameraMatrix.camera = transmute([16]f32)vp
}

copy_camera_data :: proc() {
	mapped: rawptr
	cameraData.dBuffer.Map(cameraData.dBuffer, 0, nil, &mapped)
	mem.copy(mapped, &cameraData.currentCameraMatrix.camera, cameraData.bufferSize)
	cameraData.dBuffer.Unmap(cameraData.dBuffer, 0, nil)
}

camera_update :: proc(dt: f64) {
	// movement
	if ((glfw.GetKey(renderer.windowHandle, glfw.KEY_A) == glfw.PRESS) ||
		   (glfw.GetKey(renderer.windowHandle, glfw.KEY_D) == glfw.PRESS)) {
		moveDir := normalize(cross(cameraData.direction, cameraData.up))
		cameraData.position +=
			moveDir *
			f32(dt) *
			cameraData.movingSpeed *
			f32(
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_A)) -
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_D)),
			)
	}
	if ((glfw.GetKey(renderer.windowHandle, glfw.KEY_W) == glfw.PRESS) ||
		   (glfw.GetKey(renderer.windowHandle, glfw.KEY_S) == glfw.PRESS)) {
		moveDir := normalize(cameraData.direction)
		cameraData.position +=
			moveDir *
			f32(dt) *
			cameraData.movingSpeed *
			f32(
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_S)) -
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_W)),
			)
	}
	if ((glfw.GetKey(renderer.windowHandle, glfw.KEY_SPACE) == glfw.PRESS) ||
		   (glfw.GetKey(renderer.windowHandle, glfw.KEY_LEFT_SHIFT) == glfw.PRESS)) {
		moveDir := normalize(cameraData.up)
		cameraData.position +=
			moveDir *
			f32(dt) *
			cameraData.movingSpeed *
			f32(
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_LEFT_SHIFT)) -
				(glfw.GetKey(renderer.windowHandle, glfw.KEY_SPACE)),
			)
	}
	// camera direction
	if (glfw.GetMouseButton(renderer.windowHandle, glfw.MOUSE_BUTTON_1) == glfw.PRESS) {
		x, y := glfw.GetCursorPos(renderer.windowHandle)
		if (firstMouseClick) {
			firstMouseClick = false
			lastMouseX = x
			lastMouseY = y
		}

		dx := (x - lastMouseX) * 0.1 * f64(cameraData.dragSpeed)
		dy := -(y - lastMouseY) * 0.1 * f64(cameraData.dragSpeed)

		cameraData.yaw += f32(dx)
		cameraData.pitch += f32(dy)

		cameraData.pitch = clamp(cameraData.pitch, -89, 89)

		cameraData.direction = {
			math.cos(math.to_radians(cameraData.yaw)) *
			math.cos(math.to_radians(cameraData.pitch)),
			math.sin(math.to_radians(cameraData.pitch)),
			math.sin(math.to_radians(cameraData.yaw)) *
			math.cos(math.to_radians(cameraData.pitch)),
		}

		lastMouseX = x
		lastMouseY = y
	} else {
		firstMouseClick = true
	}
	recalculate_camera()
	copy_camera_data()
}

package learn_sdlgpu

import "core:mem"
import sdl "vendor:sdl3"

Texture :: struct {
	handle: ^sdl.GPUTexture,
	x, y:   u32,
	transfer_buf: ^sdl.GPUTransferBuffer,
	sampler: ^sdl.GPUSampler,
}

texture_load :: proc(
	device: ^sdl.GPUDevice,
	image_name: string,
) -> (texture: Texture) {
	img, ok := content_load_image(image_name)
	assert(ok)
	defer content_destroy_image(img)

	texture.x, texture.y = u32(img.width), u32(img.height)

	// copy to transfer buffer
	texture.transfer_buf = sdl.CreateGPUTransferBuffer(device, {
		usage = .UPLOAD,
		size  = cast(u32)len(img.pixels.buf),
	})
	tex_transfer_mem := sdl.MapGPUTransferBuffer(device, texture.transfer_buf, false)
	mem.copy(tex_transfer_mem, raw_data(img.pixels.buf), len(img.pixels.buf))

	// unmap
	sdl.UnmapGPUTransferBuffer(device, texture.transfer_buf)

	// create texture on GPU
	texture.handle = sdl.CreateGPUTexture(device, {
		type = .D2,
		format = .R8G8B8A8_UNORM_SRGB,
		usage = {.SAMPLER},
		width = cast(u32)img.width,
		height = cast(u32)img.height,
		layer_count_or_depth = 1,
		num_levels = 1,
	})

	// create sampler for shader access
	texture.sampler = sdl.CreateGPUSampler(device, {
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
		address_mode_u = .REPEAT,
		address_mode_v = .REPEAT,
		address_mode_w = .REPEAT,
	})

	return texture
}

texture_destroy :: proc(
	device: ^sdl.GPUDevice,
	texture: Texture,
) {
	sdl.ReleaseGPUTexture(device, texture.handle)
	sdl.ReleaseGPUSampler(device, texture.sampler)
}

texture_create_depth_stencil :: proc(
	device: ^sdl.GPUDevice,
	window: ^sdl.Window,
) -> ^sdl.GPUTexture {
	props := sdl.CreateProperties()
	sdl.SetFloatProperty(props, sdl.PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_DEPTH_FLOAT, 1.0)
	sdl.SetNumberProperty(props, sdl.PROP_GPU_TEXTURE_CREATE_D3D12_CLEAR_STENCIL_NUMBER, 0)
	defer sdl.DestroyProperties(props)

	win_w, win_h : i32
	sdl.GetWindowSize(window, &win_w, &win_h)
	depth_stencil_texture := sdl.CreateGPUTexture(device, {
		type = .D2,
		// universally supported format, check for others if required
		format = .D16_UNORM,
		usage = {.DEPTH_STENCIL_TARGET},
		width = cast(u32)win_w,
		height = cast(u32)win_h,
		layer_count_or_depth = 1,
		num_levels = 1,
		props = props,
	})

	return depth_stencil_texture
}

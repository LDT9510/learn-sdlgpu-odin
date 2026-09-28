package learn_sdlgpu

import im "extern:imgui"

import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:sys/windows"
import sdl "vendor:sdl3"

NUM_UNIFORM_BUFFERS :: 1

// must be aligned to 16 bytes as required by the std140 layout
UBO :: struct #max_field_align(16) {
	mvp: glm.mat4,
}
#assert(size_of(UBO) <= 128) // max recommended for uniforms

UI_bool :: struct {
	name:    cstring,
	value:   bool,
	toggled: bool,
}

Render_Data :: struct {
	target_texture: ^sdl.GPUTexture,
	depth_texture:  ^sdl.GPUTexture,
	command_buffer: ^sdl.GPUCommandBuffer,
	pipeline:       ^sdl.GPUGraphicsPipeline,
	vertex_buffer:  ^sdl.GPUBuffer,
	index_buffer:   ^sdl.GPUBuffer,
	texture:        ^sdl.GPUTexture,
	sampler:        ^sdl.GPUSampler,
	num_indices:    u32,
	ubo:            ^UBO,
}

Vertex_Data :: struct {
	positions: glm.vec3,
	uv:        glm.vec2,
}

g_should_close := false
g_is_capturing_mouse := false
g_vsync := UI_bool{"VSYNC", true, false}
g_camera := camera_create({0, 1, -3})

main :: proc() {
	context = context_setup()
	defer context_teardown()

	// windows specific fix
	when ODIN_OS == .Windows {
		windows.SetProcessDPIAware()
	}

	// window
	window, device := window_create_and_device()
	defer window_destroy(window, device)

	// developer UI
	devui_init(window, device)
	defer devui_shutdown(device)

	// create depth and stencil texture
	depth_stencil_texture := create_depth_stencil_texture(device, window)
	defer sdl.ReleaseGPUTexture(device, depth_stencil_texture)

	// create pipeline
	pipeline := create_pipeline(device, window)
	defer sdl.ReleaseGPUGraphicsPipeline(device, pipeline)

	// load model
	model := load_model(device, "tractor-police", "colormap.png")
	defer unload_model(device, model)

	// send to GPU
	upload_to_gpu(device, model)


	timings: Timings

	x_pos := f32(0.0)
	y_pos := f32(0.0)
	z_pos := f32(0.0)
	angle := f32(0.0)
	scale := f32(1.0)

	for !g_should_close {
		// ------------------ update ------------------
		timing_update(&timings)
		events_handle(process_key_input, process_events, window)
		camera_handle_input(&g_camera, timings.delta_time)

		proj_mat := glm.mat4Perspective(
			glm.radians_f32(g_camera.zoom),
			window_get_aspect_ratio(window),
			g_camera.frustrum_near,
			g_camera.frustrum_far,
		)

		model_mat := glm.mat4(1)
		time := timing_get_elapsed_seconds()

		x_trans_speed := f32(0.0)
		x_pos += glm.cos(time) * x_trans_speed * timings.delta_time
		model_mat *= glm.mat4Translate({x_pos, y_pos, z_pos})

		rot_speed := glm.radians_f32(90)
		angle += rot_speed * timings.delta_time
		model_mat *= glm.mat4Rotate({0, 1, 0}, angle)

		scaling_amplitude := f32(0.0)
		scale += glm.cos(time) * scaling_amplitude * timings.delta_time
		model_mat *= glm.mat4Scale(scale)

		model_view_projection := proj_mat * camera_get_view_matrix(g_camera) * model_mat

		// ------------------ rendering ------------------

		// create command buffer
		draw_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
		sdl_assert(draw_cmd_buf)

		if g_vsync.toggled {
			log.infof("%s %s", g_vsync.name, g_vsync.value ? "ON" : "OFF")
			sdl_assert(
				sdl.SetGPUSwapchainParameters(
					device,
					window,
					.SDR,
					g_vsync.value ? .VSYNC : .IMMEDIATE,
				),
			)
			g_vsync.toggled = false
		}

		// adquire swapchain texture
		swapchain_tex: ^sdl.GPUTexture
		sdl_assert(
			sdl.WaitAndAcquireGPUSwapchainTexture(draw_cmd_buf, window, &swapchain_tex, nil, nil),
		)

		if swapchain_tex != nil {
			render_data := Render_Data {
				target_texture = swapchain_tex,
				depth_texture = depth_stencil_texture,
				command_buffer = draw_cmd_buf,
				pipeline = pipeline,
				vertex_buffer = model.vertex_buf,
				index_buffer = model.index_buf,
				texture = model.texture.handle,
				sampler = model.texture.sampler,
				num_indices = model.num_indices,
				ubo = &{mvp = model_view_projection},
			}

			// render application
			render(render_data)

			// render ui
			devui_begin_frame()
			main_ui_window(timings, window, device)
			devui_render_frame(swapchain_tex, draw_cmd_buf)
		}

		sdl_assert(sdl.SubmitGPUCommandBuffer(draw_cmd_buf))

		free_all(context.temp_allocator)
	}
}

render :: proc(rd: Render_Data) {
	// describe the color target
	color_target_info := sdl.GPUColorTargetInfo {
		texture     = rd.target_texture,
		load_op     = .CLEAR,
		clear_color = {0, 0.2, 0.4, 1},
		store_op    = .STORE,
	}
	// describe the depth target
	depth_target_info := sdl.GPUDepthStencilTargetInfo {
		texture = rd.depth_texture,
		load_op = .CLEAR,
		clear_depth = 1.0,
		clear_stencil = 0,
		store_op = .DONT_CARE,
	}
	// render pass
	render_pass := sdl.BeginGPURenderPass(rd.command_buffer, &color_target_info, 1, &depth_target_info)
	// bind pipeline
	sdl.BindGPUGraphicsPipeline(render_pass, rd.pipeline)
	// push uniforms
	sdl.PushGPUVertexUniformData(rd.command_buffer, 0, rd.ubo, size_of(UBO))
	// bind index and vertex data, and samplers
	sdl.BindGPUIndexBuffer(render_pass, {buffer = rd.index_buffer}, ._16BIT)
	sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{buffer = rd.vertex_buffer}, 1)
	sdl.BindGPUFragmentSamplers(render_pass, 0, &sdl.GPUTextureSamplerBinding{rd.texture, rd.sampler}, 1)
	// draw calls
	sdl.DrawGPUIndexedPrimitives(render_pass, rd.num_indices, 1, 0, 0 ,0)
	// end drawing
	sdl.EndGPURenderPass(render_pass)
}

main_ui_window :: proc(t: Timings, w: ^sdl.Window, d: ^sdl.GPUDevice) {
	im.Begin("Learning SDL_GPU")

	im.Text("Current API: %s", SELECTED_GRAPHICS_API)
	im.Separator()

	g_vsync.toggled = im.RadioButtonIntPtr("VSYNC", cast(^i32)&g_vsync.value, 1)
	im.SameLine()
	g_vsync.toggled ||= im.RadioButtonIntPtr("IMMEDIATE", cast(^i32)&g_vsync.value, 0)

	if im.CollapsingHeader("Timings", {.DefaultOpen}) {
		im.Text("FPS: %d", t.fps)
		im.Text("Frame time: %.2f ms", t.frame_time_ms)
	}

	camera_dev_ui_frame(&g_camera)

	defer im.End()
}

process_key_input :: proc() {
	switch {
	case events_is_key_just_pressed(.ESCAPE):
		g_should_close = true
	}
}

process_events :: proc(event: sdl.Event, window: ^sdl.Window) {
	g_is_capturing_mouse = events_is_mouse_button_pressed({.RIGHT})
	_ = sdl.SetWindowRelativeMouseMode(window, g_is_capturing_mouse)

	#partial switch event.type {
	case .QUIT:
		toggle(&g_should_close)
	case .MOUSE_WHEEL:
		camera_on_mouse_wheel_scroll(&g_camera, event.wheel.y, g_is_capturing_mouse)
	case .MOUSE_MOTION:
		if g_is_capturing_mouse {
			camera_on_mouse_move(&g_camera, event.motion.xrel, -event.motion.yrel)
		}
	}
}

create_pipeline :: proc(
	device: ^sdl.GPUDevice,
	window: ^sdl.Window,
) -> ^sdl.GPUGraphicsPipeline {
	// load shaders
	vertex_shader := create_shader(device, "shader.vert", 0)
	defer sdl.ReleaseGPUShader(device, vertex_shader)

	fragment_shader := create_shader(device, "shader.frag", 1)
	defer sdl.ReleaseGPUShader(device, fragment_shader)

	// describe vertex attributes
	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = 0}, // position
		{location = 1, format = .FLOAT2, offset = cast(u32)offset_of(Vertex_Data, uv)}, // texture coords
	}

	// create the pipeline
	pipeline := sdl.CreateGPUGraphicsPipeline(device,
	{
		primitive_type = .TRIANGLELIST,
		vertex_shader = vertex_shader,
		fragment_shader = fragment_shader,
		target_info = {
			num_color_targets         = 1,
			color_target_descriptions = &sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(device, window),
			},
			has_depth_stencil_target = true,
			depth_stencil_format = .D16_UNORM,
		},
		vertex_input_state = {
			num_vertex_buffers         = 1,
			vertex_buffer_descriptions = &sdl.GPUVertexBufferDescription {
				slot  = 0,
				pitch = size_of(Vertex_Data), // this is the stride
			},
			num_vertex_attributes = cast(u32)len(vertex_attrs),
			vertex_attributes     = raw_data(vertex_attrs),
		},
		depth_stencil_state = {
			enable_depth_test = true,
			enable_depth_write = true,
			compare_op = .LESS,
		},
		rasterizer_state = {
			cull_mode = .BACK,
		},
	})

	return pipeline
}

create_shader :: proc(
	device: ^sdl.GPUDevice,
	shader_file: string,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	shader, ok := content_load_shader(shader_file)
	assert(ok)
	defer content_destroy_shader(shader)

	format: sdl.GPUShaderFormat
	entrypoint: cstring
	switch CURRENT_GRAPHICS_API {
	case .Vulkan:
		format = {.SPIRV}
		entrypoint = "main"
	case .DirectX12:
		format = {.DXIL}
		entrypoint = "main"
	case .Metal:
		format = {.MSL}
		// "main" is a reserved keyword in MSL, shadercross will create this entrypoint
		entrypoint = "main0"
	}

	return sdl.CreateGPUShader(device, {
		code_size 			= len(shader.code),
		code                = raw_data(shader.code),
		entrypoint          = entrypoint,
		format              = format,
		stage               = shader.stage,
		num_uniform_buffers = NUM_UNIFORM_BUFFERS,
		num_samplers        = num_samplers,
	})
}

Model :: struct {
	vertex_buf, index_buf: ^sdl.GPUBuffer,
	vertex_size, index_size, num_indices: u32,
	texture: Texture,
	transfer_buf: ^sdl.GPUTransferBuffer,
}

load_model :: proc(
	device: ^sdl.GPUDevice,
	model_name: string,
	image_name: string,
) -> (model: Model) {
	car_model, model_ok := content_load_obj_model("tractor-police")
	assert(model_ok)

	// create vertex and index data from the model
	vertices := make([]Vertex_Data, len(car_model.faces))
	defer delete(vertices)
	indices := make([]u16, len(car_model.faces))
	defer delete(indices)

	for face, i in car_model.faces {
		vertices[i] = {
			positions = car_model.positions[face.pos],
			uv = car_model.uvs[face.uv],
		}
		indices[i] = u16(i)
	}

	// the model is safe to delete now
	content_destroy_obj_model(car_model)

	model.vertex_size = u32(len(vertices) * size_of(vertices[0]))
	model.index_size = u32(len(indices) * size_of(indices[0]))
	model.num_indices = u32(len(indices))

	// create vertex buffers
	model.vertex_buf = sdl.CreateGPUBuffer(device, {
		usage = {.VERTEX},
		size  = model.vertex_size,
	})

	// create index buffers
	model.index_buf = sdl.CreateGPUBuffer(device, {
		usage = {.INDEX},
		size  = model.index_size,
	})

	// create a transfer buffer (GPU memory mapped to CPU memory) and copy
	model.transfer_buf = sdl.CreateGPUTransferBuffer(device, {
		usage = .UPLOAD,
		size  = model.vertex_size + model.index_size,
	})
	transfer_mem := cast([^]byte)sdl.MapGPUTransferBuffer(device, model.transfer_buf, false)
	mem.copy(transfer_mem, raw_data(vertices), cast(int)model.vertex_size)
	mem.copy(transfer_mem[model.vertex_size:], raw_data(indices), cast(int)model.index_size)

	// unmap the buffer (must be done before unload)
	sdl.UnmapGPUTransferBuffer(device, model.transfer_buf)

	// load the corresponding texture
	model.texture = load_texture(device, "colormap.png")

	return model
}

unload_model :: proc(
	device: ^sdl.GPUDevice,
	model: Model,
) {
	sdl.ReleaseGPUBuffer(device, model.vertex_buf)
	sdl.ReleaseGPUBuffer(device, model.index_buf)
	unload_texture(device, model.texture)
}

Texture :: struct {
	handle: ^sdl.GPUTexture,
	x, y:   u32,
	transfer_buf: ^sdl.GPUTransferBuffer,
	sampler: ^sdl.GPUSampler,
}

load_texture :: proc(
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
		format = .R8G8B8A8_UNORM,
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

unload_texture :: proc(
	device: ^sdl.GPUDevice,
	texture: Texture,
) {
	sdl.ReleaseGPUTexture(device, texture.handle)
	sdl.ReleaseGPUSampler(device, texture.sampler)
}

create_depth_stencil_texture :: proc(
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

upload_to_gpu :: proc(
	device: ^sdl.GPUDevice,
	model: Model,
) {
	// begin a copy pass
	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

	// invoke upload command
	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = model.transfer_buf},
		{buffer = model.vertex_buf, size = model.vertex_size},
		false)

	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = model.transfer_buf, offset = model.vertex_size},
		{buffer = model.index_buf, size = model.index_size},
		false)

	sdl.UploadToGPUTexture(copy_pass,
		{transfer_buffer = model.texture.transfer_buf},
		{texture = model.texture.handle, w = model.texture.x, h = model.texture.y, d = 1},
		false)

	// end copy pass and submit
	sdl.EndGPUCopyPass(copy_pass)
	sdl_assert(sdl.SubmitGPUCommandBuffer(copy_cmd_buf))

	// after submit is safe to release the transfer buffers
	sdl.ReleaseGPUTransferBuffer(device, model.transfer_buf)
	sdl.ReleaseGPUTransferBuffer(device, model.texture.transfer_buf)
}

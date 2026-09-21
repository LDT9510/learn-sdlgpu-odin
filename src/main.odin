package learn_sdlgpu

import im "extern:imgui"

import "base:runtime"
import "core:log"
import glm "core:math/linalg/glsl"
import "core:mem"
import "core:sys/windows"
import sdl "vendor:sdl3"

g_state: struct {
	default_context: runtime.Context,
	should_close:    bool,
}

g_vertex := #load("shader.vert.spv")
g_fragment := #load("shader.frag.spv")

// must be aligned to 16 bytes as required by the std140 layout
UBO :: struct #max_field_align(16) {
	mvp: glm.mat4,
}

UI_bool :: struct {
	name:    cstring,
	value:   bool,
	toggled: bool,
}
g_vsync := UI_bool{"VSYNC", true, false}

main :: proc() {
	// windows specific fix
	when ODIN_OS == .Windows {
		windows.SetProcessDPIAware()
	}

	// setup logging (NOTE: no allocation tracking)
	cl := log.create_console_logger(opt = {.Level})
	defer log.destroy_console_logger(cl)
	context.logger = cl

	// setup allocation
	when ODIN_DEBUG {
		debug_mode := true
		tracking_allocator := create_tracking_allocator(context.allocator)
		defer destroy_tracking_allocator(tracking_allocator)
		context.allocator = tracking_allocator

		tracking_temp_allocator := create_tracking_allocator(context.temp_allocator)
		defer destroy_tracking_allocator(tracking_temp_allocator, temp = true)
		context.temp_allocator = tracking_temp_allocator

		sdl_log_priority: sdl.LogPriority = .VERBOSE
	} else {
		debug_mode := false
		sdl_log_priority: sdl.LogPriority = .INFO
	}

	g_state.default_context = context

	sdl.SetLogPriorities(sdl_log_priority)
	sdl.SetLogOutputFunction(sdl_log_adapter, nil)

	log.info("Initializing program")

	if debug_mode {
		log.debug("-------- Debug mode --------")
	}

	// window
	window, device := window_create_and_device()
	defer window_destroy(window, device)

	// developer UI
	devui_init(window, device)
	defer devui_shutdown(device)

	// ------------------ load images ------------------
	// load image data
	img, ok := content_load_image("marble.jpg")
	assert(ok)
	defer content_destroy_image(img)
	// create texture on GPU
	texture := sdl.CreateGPUTexture(device, {
		type = .D2,
		format = .R8G8B8A8_UNORM,
		usage = {.SAMPLER},
		width = cast(u32)img.width,
		height = cast(u32)img.height,
		layer_count_or_depth = 1,
		num_levels = 1,
	})
	defer sdl.ReleaseGPUTexture(device, texture)
	// upload pixels to texture
	tex_transfer_buf := sdl.CreateGPUTransferBuffer(device, {
		usage = .UPLOAD,
		size  = cast(u32)len(img.pixels.buf),
	})
	tex_transfer_mem := sdl.MapGPUTransferBuffer(device, tex_transfer_buf, false)
	mem.copy(tex_transfer_mem, raw_data(img.pixels.buf), len(img.pixels.buf))
	sdl.UnmapGPUTransferBuffer(device, tex_transfer_buf)
	// upload is done in the copy pass bellow
	// assign texture coords to vertices (vertex attribute below)
	// create shader sampler
	sampler := sdl.CreateGPUSampler(device, {
		min_filter = .NEAREST,
		mag_filter = .NEAREST,
		address_mode_u = .REPEAT,
		address_mode_v = .REPEAT,
		address_mode_w = .REPEAT,
	})
	defer sdl.ReleaseGPUSampler(device, sampler)

	// ------------------ load models ------------------
	car_model, model_ok := content_load_obj_model("sedan-sports")
	assert(model_ok)

	// ------------------ load shaders ------------------

	vertex_shader := sdl.CreateGPUShader(device, {
		code_size 			= len(g_vertex),
		code                = raw_data(g_vertex),
		entrypoint          = "main",
		format              = {.SPIRV},
		stage               = .VERTEX,
		num_uniform_buffers = UNIFORM_BUFFERS,
	})
	defer sdl.ReleaseGPUShader(device, vertex_shader)

	UNIFORM_BUFFERS :: 1

	fragment_shader := sdl.CreateGPUShader(device, {
		code_size           = len(g_fragment),
		code                = raw_data(g_fragment),
		entrypoint          = "main",
		format              = {.SPIRV},
		stage               = .FRAGMENT,
		num_uniform_buffers = UNIFORM_BUFFERS,
		num_samplers        = 1,
	})
	defer sdl.ReleaseGPUShader(device, fragment_shader)


	// ------------------ create vertex data ------------------

	Vertex_Data :: struct {
		positions: glm.vec3,
		uv:        glm.vec2,
	}

	// create vertex and index data from the model
	vertices := make([]Vertex_Data, len(car_model.faces))
	indices := make([]u16, len(car_model.faces))

	for face, i in car_model.faces {
		vertices[i] = {
			positions = car_model.positions[face.pos],
			uv = car_model.uvs[face.uv],
		}
		indices[i] = u16(i)
	}

	// the model is safe to delete now
	content_destroy_obj_model(car_model)

	vertex_data_size := u32(len(vertices) * size_of(vertices[0]))
	index_data_size := u32(len(indices) * size_of(indices[0]))

	// create vertex buffers
	vertex_buf := sdl.CreateGPUBuffer(device, {
		usage = {.VERTEX},
		size  = vertex_data_size,
	})
	defer sdl.ReleaseGPUBuffer(device, vertex_buf)

	// create index buffers
	index_buf := sdl.CreateGPUBuffer(device, {
		usage = {.INDEX},
		size  = index_data_size,
	})
	defer sdl.ReleaseGPUBuffer(device, index_buf)

	// ------------------ upload vertex data to the buffer ------------------

	// create a transfer buffer (GPU memory mapped to CPU memory)
	transfer_buf := sdl.CreateGPUTransferBuffer(device, {
		usage = .UPLOAD,
		size  = vertex_data_size + index_data_size,
	})

	// map the buffer to the GPU memory and copy
	transfer_mem := cast([^]byte)sdl.MapGPUTransferBuffer(device, transfer_buf, false)
	mem.copy(transfer_mem, raw_data(vertices), cast(int)vertex_data_size)
	mem.copy(transfer_mem[vertex_data_size:], raw_data(indices), cast(int)index_data_size)
	// unmap the buffer (must be done before unload)
	sdl.UnmapGPUTransferBuffer(device, transfer_buf)
	// after unmapping we can safely delete the data
	delete(vertices)
	delete(indices)

	// begin a copy pass
	copy_cmd_buf := sdl.AcquireGPUCommandBuffer(device)
	copy_pass := sdl.BeginGPUCopyPass(copy_cmd_buf)

	// invoke upload command
	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = transfer_buf},
		{buffer = vertex_buf, size = vertex_data_size},
		false)

	sdl.UploadToGPUBuffer(copy_pass,
		{transfer_buffer = transfer_buf, offset = vertex_data_size},
		{buffer = index_buf, size = index_data_size},
		false)

	sdl.UploadToGPUTexture(copy_pass,
		{transfer_buffer = tex_transfer_buf},
		{texture = texture, w = cast(u32)img.width, h = cast(u32)img.height, d = 1},
		false)

	// end copy pass and submit
	sdl.EndGPUCopyPass(copy_pass)
	sdl_assert(sdl.SubmitGPUCommandBuffer(copy_cmd_buf))

	// after submit is safe to release the transfer buffer
	sdl.ReleaseGPUTransferBuffer(device, transfer_buf)
	sdl.ReleaseGPUTransferBuffer(device, tex_transfer_buf)

	// ------------------ describe vertex data and create the pipeline ------------------

	// describe vertex attributes
	vertex_attrs := []sdl.GPUVertexAttribute {
		{location = 0, format = .FLOAT3, offset = 0}, // position
		{location = 1, format = .FLOAT2, offset = cast(u32)offset_of(Vertex_Data, uv)}, // texture coords
	}

	// create the pipeline
	pipeline := sdl.CreateGPUGraphicsPipeline(device,
	{
		vertex_shader = vertex_shader,
		fragment_shader = fragment_shader,
		primitive_type = .TRIANGLELIST,
		vertex_input_state = {
			num_vertex_buffers         = 1,
			vertex_buffer_descriptions = &sdl.GPUVertexBufferDescription {
				slot  = 0,
				pitch = size_of(Vertex_Data), // this is the stride
			},
			num_vertex_attributes = cast(u32)len(vertex_attrs),
			vertex_attributes     = raw_data(vertex_attrs),
		},
		target_info = {
			num_color_targets         = 1,
			color_target_descriptions = &sdl.GPUColorTargetDescription {
				format = sdl.GetGPUSwapchainTextureFormat(device, window),
			},
		},
	})
	defer sdl.ReleaseGPUGraphicsPipeline(device, pipeline)

	proj_mat := glm.mat4Perspective(
		glm.radians_f32(70),
		window_get_aspect_ratio(window),
		0.0001,
		1000.0,
	)

	timings: Timings

	x_pos := f32(0.0)
	y_pos := f32(-1.5)
	angle := f32(0.0)
	scale := f32(2.0)

	for !g_state.should_close {
		events_handle(process_key_input, process_events)
		timing_update(&timings)

		model_mat := glm.mat4(1)
		time := timing_get_elapsed_seconds()

		x_trans_speed := f32(0.0)
		x_pos += glm.cos(time) * x_trans_speed * timings.delta_time
		model_mat *= glm.mat4Translate({x_pos, y_pos, -5})

		rot_speed := glm.radians_f32(90)
		angle += rot_speed * timings.delta_time
		model_mat *= glm.mat4Rotate({0, 1, 0}, angle)

		scaling_amplitude := f32(0.0)
		scale += glm.cos(time) * scaling_amplitude * timings.delta_time
		model_mat *= glm.mat4Scale({scale, scale, 1.0})

		model_view_projection := proj_mat * model_mat

		// create command buffer
		cmd_buf := sdl.AcquireGPUCommandBuffer(device)

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
			sdl.WaitAndAcquireGPUSwapchainTexture(cmd_buf, window, &swapchain_tex, nil, nil),
		)

		if swapchain_tex != nil {
			// render application
			render(
				swapchain_tex,
				cmd_buf,
				pipeline,
				vertex_buf,
				index_buf,
				texture,
				sampler,
				cast(u32)len(indices),
				&{mvp = model_view_projection})

			// render ui
			devui_begin_frame()
			main_ui_window(timings, window, device)
			devui_render_frame(swapchain_tex, cmd_buf)
		}

		sdl_assert(sdl.SubmitGPUCommandBuffer(cmd_buf))

		free_all(context.temp_allocator)
	}
}

render :: proc(
	target_texture: ^sdl.GPUTexture,
	cmd_buf: ^sdl.GPUCommandBuffer,
	pipeline: ^sdl.GPUGraphicsPipeline,
	vertex_buffer: ^sdl.GPUBuffer,
	index_buffer: ^sdl.GPUBuffer,
	texture: ^sdl.GPUTexture,
	sampler: ^sdl.GPUSampler,
	num_indices: u32,
	ubo: ^UBO,
) {
	// ------------------ drawing ------------------

	// describe the color target
	color_target := sdl.GPUColorTargetInfo {
		texture     = target_texture,
		load_op     = .CLEAR,
		clear_color = {0, 0.2, 0.4, 1},
		store_op    = .STORE,
	}
	// render pass
	render_pass := sdl.BeginGPURenderPass(cmd_buf, &color_target, 1, nil)
	// bind pipeline
	sdl.BindGPUGraphicsPipeline(render_pass, pipeline)
	// bind uniforms
	sdl.PushGPUVertexUniformData(cmd_buf, 0, ubo, size_of(UBO))
	// bind vertex and index data, and samplers
	sdl.BindGPUVertexBuffers(render_pass, 0, &sdl.GPUBufferBinding{buffer = vertex_buffer}, 1)
	sdl.BindGPUIndexBuffer(render_pass, {buffer = index_buffer}, ._16BIT)
	sdl.BindGPUFragmentSamplers(render_pass, 0, &sdl.GPUTextureSamplerBinding{texture, sampler}, 1)
	// draw calls
	sdl.DrawGPUIndexedPrimitives(render_pass, num_indices, 1, 0, 0 ,0)
	// end drawing
	sdl.EndGPURenderPass(render_pass)
}

main_ui_window :: proc(t: Timings, w: ^sdl.Window, d: ^sdl.GPUDevice) {
	im.Begin("Learning SDL_GPU")

	g_vsync.toggled = im.RadioButtonIntPtr("VSYNC", cast(^i32)&g_vsync.value, 1)
	im.SameLine()
	g_vsync.toggled ||= im.RadioButtonIntPtr("IMMEDIATE", cast(^i32)&g_vsync.value, 0)

	if im.CollapsingHeader("Timings", {.DefaultOpen}) {
		im.Text("FPS: %d", t.fps)
		im.Text("Frame time: %.2f ms", t.frame_time_ms)
	}

	defer im.End()
}

process_key_input :: proc() {
	switch {
	case events_is_key_just_pressed(.ESCAPE):
		g_state.should_close = true
	}
}

process_events :: proc(event: sdl.Event) {
	#partial switch event.type {
	case .QUIT:
		toggle(&g_state.should_close)
	}
}

sdl_log_adapter :: proc "c" (
	_userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = g_state.default_context

	switch priority {
	case .INVALID:
		fallthrough
	case .TRACE:
		fallthrough
	case .VERBOSE:
		fallthrough
	case .DEBUG:
		log.debugf("[SDL %s] %s", category, message)
	case .INFO:
		log.infof("[SDL %s] %s", category, message)
	case .WARN:
		log.warnf("[SDL %s] %s", category, message)
	case .ERROR:
		log.errorf("[SDL %s] %s", category, message)
	case .CRITICAL:
		log.fatalf("[SDL %s] %s", category, message)
	}
}

MAX_ALLOCATION_ERROR_MESSAGES :: 20

create_tracking_allocator :: proc(allocator: mem.Allocator) -> mem.Allocator {
	tracking_allocator := new(mem.Tracking_Allocator)
	mem.tracking_allocator_init(tracking_allocator, allocator)
	return mem.tracking_allocator(tracking_allocator)
}

destroy_tracking_allocator :: proc(allocator: mem.Allocator, temp := false) -> bool {
	a := cast(^mem.Tracking_Allocator)allocator.data
	err := false
	remaining_allocations := len(a.allocation_map)

	if remaining_allocations > 0 {
		prefix := temp ? "Temp Allocator" : "Heap Allocator"
		log.errorf("(%s) Leaked allocation count: %v", prefix, len(a.allocation_map))
	}

	allocations_noticed := 0
	for _, v in a.allocation_map {
		log.errorf("%v: Leaked %v bytes", v.location, v.size)
		err = true
		allocations_noticed += 1

		if allocations_noticed > MAX_ALLOCATION_ERROR_MESSAGES {
			log.errorf(
				"(... +%d leaked allocations)",
				remaining_allocations - allocations_noticed + 1,
			)
			break
		}
	}

	mem.tracking_allocator_destroy(a)
	free(a)

	return err
}

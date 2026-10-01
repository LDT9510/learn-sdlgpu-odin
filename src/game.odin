package learn_sdlgpu

import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

Transform :: struct {
	pos: glm.vec3,
	angle: f32,
	scale: f32,
}

Entity :: struct {
	model: Model,
	trans: Transform,
}

Game :: struct {
	entities: [dynamic]Entity,
}

game_init :: proc() -> (game: Game){
	entity := Entity{
		model = model_load(g.device, "tractor-police", "colormap.png"),
		trans = { scale = 1.0 },
	}

	renderer_upload_to_gpu(g.device, entity.model)

	append(&game.entities, entity)

	return game
}

game_update :: proc(game: ^Game, timings: Timings) {
	events_handle(_process_key_input, _process_events, g.window)
	camera_handle_input(&g.camera, timings.delta_time)

	time := timing_get_elapsed_seconds()

	x_trans_speed := f32(0.0)
	rot_speed := glm.radians_f32(90)
	scaling_amplitude := f32(0.0)

	for &entt in game.entities {
		entt.trans.pos.x += glm.cos(time) * x_trans_speed * timings.delta_time
		entt.trans.angle += rot_speed * timings.delta_time
		entt.trans.scale += glm.cos(time) * scaling_amplitude * timings.delta_time
	}
}

game_render :: proc(
	game: Game,
	rd: Render_State,
) {
	projection_mat := glm.mat4Perspective(
					glm.radians_f32(g.camera.zoom),
					window_get_aspect_ratio(g.window),
					g.camera.frustrum_near,
					g.camera.frustrum_far)

	// describe the color target
	color_target_info := sdl.GPUColorTargetInfo {
		texture     = rd.target_texture,
		load_op     = .CLEAR,
		clear_color = sdl.FColor(glm.pow(g.clear_color,  2.2)),
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

	for entt in game.entities {
		model_m := _get_model_mat(entt.trans)
		view_m  := camera_get_view_matrix(g.camera)
		mvp     := projection_mat * view_m * model_m

		// push uniforms
		sdl.PushGPUVertexUniformData(
			rd.command_buffer, 0, &UBO{mvp = mvp }, size_of(UBO),
		)
		// bind index and vertex data, and samplers
		sdl.BindGPUIndexBuffer(render_pass, {buffer = entt.model.index_buf}, ._16BIT)
		sdl.BindGPUVertexBuffers(
			render_pass, 0, &sdl.GPUBufferBinding{buffer = entt.model.vertex_buf}, 1,
		)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&sdl.GPUTextureSamplerBinding{entt.model.texture.handle, entt.model.texture.sampler},
			1,
		)
		// draw calls
		sdl.DrawGPUIndexedPrimitives(render_pass, entt.model.num_indices, 1, 0, 0 ,0)

	}
	// end drawing
	sdl.EndGPURenderPass(render_pass)
}

game_destroy :: proc(game: Game) {
	for entt in game.entities {
		model_destroy(g.device, entt.model)
	}

	delete(game.entities)
}

_get_model_mat :: proc(transform: Transform) -> glm.mat4 {
	model := glm.mat4Translate(transform.pos)
	model *= glm.mat4Rotate({0, 1, 0}, transform.angle)
	model *= glm.mat4Scale(transform.scale)

	return model
}

_process_key_input :: proc() {
	switch {
	case events_is_key_just_pressed(.ESCAPE):
		g.should_close = true
	}
}

_process_events :: proc(event: sdl.Event, window: ^sdl.Window) {
	g.is_capturing_mouse = events_is_mouse_button_pressed({.RIGHT})
	_ = sdl.SetWindowRelativeMouseMode(window, g.is_capturing_mouse)

	#partial switch event.type {
	case .QUIT:
		toggle(&g.should_close)
	case .MOUSE_WHEEL:
		camera_on_mouse_wheel_scroll(&g.camera, event.wheel.y, g.is_capturing_mouse)
	case .MOUSE_MOTION:
		if g.is_capturing_mouse {
			camera_on_mouse_move(&g.camera, event.motion.xrel, -event.motion.yrel)
		}
	}
}

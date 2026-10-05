package learn_sdlgpu

import im "extern:imgui"

import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

Transform :: struct {
	pos: glm.vec3,
	rot: quaternion128,
	scale: f32,
}

transform :: proc(
	pos: glm.vec3 = 0,
	rot: quaternion128 = 1,
	scale: f32 = 1.0,
) -> Transform {
	return {pos, rot, scale}
}

Entity_Id :: enum {
	Tractor,
	Ambulance,
	Sedan,
}

Entity :: struct {
	id: Entity_Id,
	name: cstring,
	model: ^Model,
	trans: Transform,
}

// need proper assets system and entity management
Game :: struct {
	entities: [dynamic]Entity,
	textures: [dynamic]Texture,
	models  : [dynamic]Model,
}

game_init :: proc() -> (game: Game){
	append(&game.textures, texture_load(g.device, "colormap.png"))

	rough_material := Material {
		diffuse = &game.textures[0],
		specular = 0,
		shininess = 1,
	}
	shinny_material := Material {
		diffuse = &game.textures[0],
		specular = 1,
		shininess = 160,
	}
	reddish_material := Material {
		diffuse = &game.textures[0],
		specular = {1, 0, 0},
		shininess = 80,
	}

	append(&game.models,   model_load(g.device,   "tractor-police", rough_material))
	append(&game.models,   model_load(g.device,   "ambulance",      reddish_material))
	append(&game.models,   model_load(g.device,   "sedan-sports",   shinny_material))

	append(&game.entities, Entity{
		id = .Tractor,
		name = "tractor",
		model = &game.models[0],
		trans = transform(),
	})
	append(&game.entities, Entity{
		id = .Ambulance,
		name = "ambulance",
		model = &game.models[1],
		trans = transform({6.0, 0.0, 0.0}, scale = 2.0),
	})
	append(&game.entities, Entity{
		id = .Sedan,
		name = "sedan",
		model = &game.models[2],
		trans = transform({-4.0, 0.0, 0.0}, scale = 1.5),
	})

	renderer_upload_game_data(game)

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
		switch entt.id {
		case .Tractor:
			entt.trans.rot *= glm.quatAxisAngle({0, 1, 0}, rot_speed * timings.delta_time)
		case .Ambulance:
			// entt.trans.rot *= glm.quatAxisAngle({0, 1, 0}, rot_speed * timings.delta_time)
		case .Sedan:
			// entt.trans.rot *= glm.quatAxisAngle({0, 0, 1}, rot_speed * timings.delta_time)
		}
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

	view_m  := camera_get_view_matrix(g.camera)
	global_ubo := Global_UBO {
		view_projection_mat = projection_mat * view_m,
	}

	global_frag_ubo := Global_Frag_UBO {
		light_position  = g.light.position,
		light_color     = g.light.color,
		light_intensity = g.light.intensity,
		view_position   = g.camera.position,
		ambient_light   = g.light.ambient,
	}

	for entt in game.entities {
		model_m := _get_model_mat(entt.trans)

		local_ubo := Local_UBO {
			model_mat = model_m,
			normal_mat = glm.inverse_transpose(model_m),
		}

		local_frag_ubo := Local_Frag_UBO {
			specular_color = entt.model.material.specular,
			shininess = entt.model.material.shininess,
		}

		// push uniforms
		sdl.PushGPUVertexUniformData(rd.command_buffer, 0, &global_ubo, size_of(Global_UBO))
		sdl.PushGPUVertexUniformData(rd.command_buffer, 1, &local_ubo, size_of(Local_UBO))
		sdl.PushGPUFragmentUniformData(rd.command_buffer, 0, &global_frag_ubo, size_of(Global_Frag_UBO))
		sdl.PushGPUFragmentUniformData(rd.command_buffer, 1, &local_frag_ubo, size_of(Local_Frag_UBO))

		// bind index and vertex data, and samplers
		sdl.BindGPUIndexBuffer(render_pass, {buffer = entt.model.index_buf}, ._16BIT)
		sdl.BindGPUVertexBuffers(
			render_pass, 0, &sdl.GPUBufferBinding{buffer = entt.model.vertex_buf}, 1,
		)
		sdl.BindGPUFragmentSamplers(
			render_pass,
			0,
			&sdl.GPUTextureSamplerBinding{entt.model.material.diffuse.handle, entt.model.material.diffuse.sampler},
			1,
		)
		// draw calls
		sdl.DrawGPUIndexedPrimitives(render_pass, entt.model.num_indices, 1, 0, 0 ,0)

	}
	// end drawing
	sdl.EndGPURenderPass(render_pass)
}

game_devui_frame :: proc(game: ^Game) {
	if im.CollapsingHeader("Game", {.DefaultOpen}) {
		for entt in game.entities {
			im.PushID(entt.name)
			defer im.PopID()

			im.SeparatorText(entt.name)
			im.ColorEdit3("Specular color", &entt.model.material.specular)
			im.DragFloat("Shininess", &entt.model.material.shininess)
		}
	}
}

game_destroy :: proc(game: Game) {
	for model in game.models {
		model_destroy(g.device, model)
	}

	for tex in game.textures {
		texture_destroy(g.device, tex)
	}

	delete(game.entities)
	delete(game.models)
	delete(game.textures)
}

_get_model_mat :: proc(transform: Transform) -> glm.mat4 {
	model := glm.mat4Translate(transform.pos)
	model *= glm.mat4FromQuat(transform.rot)
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

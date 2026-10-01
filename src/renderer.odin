package learn_sdlgpu

import glm "core:math/linalg/glsl"
import sdl "vendor:sdl3"

Vertex_Data :: struct {
	positions: glm.vec3,
	uv:        glm.vec2,
}

Render_State :: struct {
	target_texture: ^sdl.GPUTexture,
	depth_texture:  ^sdl.GPUTexture,
	command_buffer: ^sdl.GPUCommandBuffer,
	pipeline:       ^sdl.GPUGraphicsPipeline,
}

// must be aligned to 16 bytes as required by the std140 layout
UBO :: struct #max_field_align(16) {
	mvp: glm.mat4,
}
#assert(size_of(UBO) <= 128) // max recommended for uniforms

renderer_create_pipeline :: proc(
	device: ^sdl.GPUDevice,
	window: ^sdl.Window,
) -> ^sdl.GPUGraphicsPipeline {
	// load shaders
	vertex_shader := renderer_create_shader(device, "shader.vert", 0)
	defer sdl.ReleaseGPUShader(device, vertex_shader)

	fragment_shader := renderer_create_shader(device, "shader.frag", 1)
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

renderer_create_shader :: proc(
	device: ^sdl.GPUDevice,
	shader_file: string,
	num_samplers: u32,
) -> ^sdl.GPUShader {
	shader, ok := content_load_shader(shader_file)
	assert(ok)

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

	reflect_info := content_load_shader_reflect(shader_file)

	return sdl.CreateGPUShader(device, {
		code_size 			 = len(shader.code),
		code                 = raw_data(shader.code),
		entrypoint           = entrypoint,
		format               = format,
		stage                = shader.stage,
		num_uniform_buffers  = reflect_info.uniform_buffers,
		num_samplers         = reflect_info.samplers,
		num_storage_buffers  = reflect_info.storage_buffers,
		num_storage_textures = reflect_info.storage_textures,
	})
}

renderer_upload_to_gpu :: proc(
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

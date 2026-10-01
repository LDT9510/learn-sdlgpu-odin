package learn_sdlgpu

import "core:mem"
import sdl "vendor:sdl3"

Model :: struct {
	vertex_buf, index_buf: ^sdl.GPUBuffer,
	vertex_size, index_size, num_indices: u32,
	texture: Texture,
	transfer_buf: ^sdl.GPUTransferBuffer,
}

model_load :: proc(
	device: ^sdl.GPUDevice,
	model_name: string,
	image_name: string,
) -> (model: Model) {
	car_model, model_ok := content_load_obj_model("tractor-police")
	assert(model_ok)

	// create vertex and index data from the model
	vertices := make([]Vertex_Data, len(car_model.faces), context.temp_allocator)
	indices := make([]u16, len(car_model.faces), context.temp_allocator)

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
	model.texture = texture_load(device, "colormap.png")

	return model
}

model_destroy :: proc(
	device: ^sdl.GPUDevice,
	model: Model,
) {
	sdl.ReleaseGPUBuffer(device, model.vertex_buf)
	sdl.ReleaseGPUBuffer(device, model.index_buf)
	texture_destroy(device, model.texture)
}

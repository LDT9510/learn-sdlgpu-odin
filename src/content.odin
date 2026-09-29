package learn_sdlgpu

@(require) import "core:image/png"
@(require) import "core:image/jpeg"
import "core:image"
import "core:strings"
import "core:log"
import "core:mem"
import "core:os"
import "core:encoding/json"
import "core:path/filepath"
import sdl "vendor:sdl3"

CONTENT_ROOT     ::       #config(CONTENT_ROOT, ".")
SHADERS_OUT_PATH :: "/" + #config(SHADERS_OUT_PATH, "shaders_out")

CONTENT_BASE_PATH   :: CONTENT_ROOT      + "/content"
CONTENT_IMAGE_PATH  :: CONTENT_BASE_PATH + "/images"
CONTENT_MODEL_PATH  :: CONTENT_BASE_PATH + "/models"
CONTENT_SHADER_PATH :: CONTENT_BASE_PATH + SHADERS_OUT_PATH

Content_Image :: image.Image
Content_Shader :: struct {
	code: []byte,
	stage: sdl.GPUShaderStage,
}
Content_Shader_Reflect :: struct {
	samplers: u32,
	storage_textures: u32,
	storage_buffers: u32,
	uniform_buffers: u32,
}


content_load_image :: proc(image_name: string) -> (image_data: ^image.Image, ok: bool) {
	image_path, fp_err := filepath.join(
		{CONTENT_IMAGE_PATH, image_name},
		context.temp_allocator,
	)
	assert(fp_err == .None)

	// we always want RGBA
	data, err := image.load(image_path, {.alpha_add_if_missing})
	if err != nil {
		log.errorf("Failed to load image '%s': %v", image_path, err)
		return
	}

	_flip_image_vertically_inplace(data)

	return data, true
}

content_destroy_image :: proc(image_data: ^Content_Image) {
	image.destroy(image_data)
}

content_load_obj_model :: proc(model_name: string) -> (obj: Obj_Data, ok: bool) {
	model_path_base, err := filepath.join(
		{CONTENT_MODEL_PATH, model_name},
		context.temp_allocator,
	)
	assert(err == .None)

	model_path := strings.concatenate({model_path_base, ".obj"}, context.temp_allocator)

	data, data_ok := _read_file_bytes(model_path, context.temp_allocator)
	if !data_ok {
		log.errorf("Failed to load model at '%s'", model_path)
		return
	}

	obj = obj_load(data)

	return obj, true
}

content_destroy_obj_model :: proc(obj: Obj_Data) {
	obj_destroy(obj)
}

content_load_shader :: proc(shader_file: string) -> (shader: Content_Shader, ok: bool) {
	format_name := SHADER_OUT_FORMATS[CURRENT_GRAPHICS_API]

	file_path_base, err := filepath.join(
		{CONTENT_SHADER_PATH, format_name, shader_file},
		context.temp_allocator,
	)
	assert(err == .None)

	file_name := strings.concatenate(
		{file_path_base, ".", format_name},
		context.temp_allocator)

	code, read_ok := _read_file_bytes(file_name, context.temp_allocator)

	stage: sdl.GPUShaderStage
	switch filepath.ext(shader_file) {
	case ".vert":
		stage = .VERTEX
	case ".frag":
		stage = .FRAGMENT
	case:
		panic("Unrecognized shader stage")
	}

	return {code, stage}, read_ok
}

content_load_shader_reflect :: proc(shader_file: string) -> (res: Content_Shader_Reflect) {
	format := SHADER_OUT_FORMATS[CURRENT_GRAPHICS_API]
	json_filename := strings.concatenate(
		{CONTENT_SHADER_PATH, "/", format, "/", shader_file, ".json"},
		context.temp_allocator,
	)
	json_content, ok := _read_file_bytes(
		json_filename,
		context.temp_allocator,
	)
	assert(ok)

	json.unmarshal(json_content, &res)

	return res
}

// user is responsible for data deletion
@(private)
_read_file_bytes :: proc(
	path: string, allocator: mem.Allocator,
) -> (file_content: []byte, ok: bool) {
	content, error := os.read_entire_file(path, context.temp_allocator)

	if error != nil {
		log.errorf("Failed to load content '%s': %v", path, error)
		return
	}

	return content, true
}


_with_ext :: proc(name: string, ext: string) -> string {
	return strings.concatenate({name, ext})
}

@private
_flip_image_vertically_inplace :: proc(image_data: ^image.Image) {
	row_size_in_bytes := (image_data.depth / 8) * image_data.width * image_data.channels
	num_rows := image_data.height
	temp_row := make([]byte, row_size_in_bytes, context.temp_allocator)

	for i := 0; i < num_rows / 2; i += 1 {
		top_row := image_data.pixels.buf[i * row_size_in_bytes:][:row_size_in_bytes]
		bottom_row := image_data.pixels.buf[(num_rows - i - 1) *
		row_size_in_bytes:][:row_size_in_bytes]
		copy(temp_row[:], top_row[:])
		copy(top_row[:], bottom_row[:])
		copy(bottom_row[:], temp_row[:])
	}
}

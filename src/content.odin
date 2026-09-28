package learn_sdlgpu

@(require) import "core:image/png"
@(require) import "core:image/jpeg"
import "core:image"
import "core:strings"
import "core:log"
import "core:os"
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

content_load_image :: proc(image_name: string) -> (image_data: ^image.Image, ok: bool) {
	image_path, fp_err := filepath.join({CONTENT_IMAGE_PATH, image_name})
	assert(fp_err == .None)
	defer delete(image_path)

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
	model_path_base, err := filepath.join({CONTENT_MODEL_PATH, model_name})
	assert(err == .None)
	defer delete(model_path_base)

	model_path := strings.concatenate({model_path_base, ".obj"})
	defer delete(model_path)

	data, data_ok := _read_file_bytes(model_path)
	if !data_ok {
		log.errorf("Failed to load model at '%s'", model_path)
		return
	}

	obj = obj_load(data)
	delete(data)

	return obj, true
}

content_destroy_obj_model :: proc(obj: Obj_Data) {
	obj_destroy(obj)
}

content_load_shader :: proc(shader_file: string) -> (shader: Content_Shader, ok: bool) {
	format_name := SHADER_OUT_FORMATS[CURRENT_GRAPHICS_API]

	file_path_base, err := filepath.join({CONTENT_SHADER_PATH, format_name, shader_file})
	assert(err == .None)
	defer delete(file_path_base)

	file_name := strings.concatenate({file_path_base, ".", format_name})
	defer delete(file_name)

	code, read_ok := _read_file_bytes(file_name)

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

content_destroy_shader :: proc(shader: Content_Shader) {
	delete(shader.code)
}

// user is responsible for data deletion
@(private)
_read_file_bytes :: proc(path: string) -> (file_content: []byte, ok: bool) {
	content, error := os.read_entire_file(path, context.allocator)

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
	temp_row := make([]byte, row_size_in_bytes)
	defer delete(temp_row)

	for i := 0; i < num_rows / 2; i += 1 {
		top_row := image_data.pixels.buf[i * row_size_in_bytes:][:row_size_in_bytes]
		bottom_row := image_data.pixels.buf[(num_rows - i - 1) *
		row_size_in_bytes:][:row_size_in_bytes]
		copy(temp_row[:], top_row[:])
		copy(top_row[:], bottom_row[:])
		copy(bottom_row[:], temp_row[:])
	}
}

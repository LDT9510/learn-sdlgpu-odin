package learn_sdlgpu

@(require) import "core:image/png"
@(require) import "core:image/jpeg"
import "core:image"
import "core:log"
import "core:os"
import "core:strings"

CONTENT_ROOT :: #config(CONTENT_ROOT, "./")

CONTENT_BASE_PATH :: CONTENT_ROOT + "content/"
CONTENT_IMAGE_PATH :: CONTENT_BASE_PATH + "images/"
CONTENT_MODEL_PATH :: CONTENT_BASE_PATH + "models/"

Content_Image :: image.Image

content_load_image :: proc(image_name: string) -> (image_data: ^image.Image, ok: bool) {
	image_path := strings.concatenate({CONTENT_IMAGE_PATH, image_name})
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

content_load_obj_model :: proc(model_name: string) -> (obj: Obj_Data, ok: bool) {
	model_path := strings.concatenate({CONTENT_MODEL_PATH, model_name, ".obj"})
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

content_destroy_image :: proc(image_data: ^Content_Image) {
	image.destroy(image_data)
}

content_destroy_obj_model :: proc(obj: Obj_Data) {
	obj_destroy(obj)
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

package learn_sdlgpu

import "core:strings"
import "core:strconv"
import glm "core:math/linalg/glsl"

Obj_Data :: struct {
	positions: []glm.vec3,
	normals: []glm.vec3,
	uvs: []glm.vec2,
	faces: []Obj_FaceIndex,
}

Obj_FaceIndex :: struct {
	pos: uint,
	normal: uint,
	uv: uint,
}

obj_load :: proc(model_data: []byte) -> Obj_Data {
	input_string := string(model_data)

	positions := make([dynamic]glm.vec3)
	normals := make([dynamic]glm.vec3)
	uvs := make([dynamic]glm.vec2)
	faces := make([dynamic]Obj_FaceIndex)

	for line in strings.split_lines_iterator(&input_string) {
		if len(line) == 0 do continue

		switch line[0] {
		case 'v':
			switch line[1] {
			case ' ':
				pos := parse_vec3(line[2:])
				append(&positions, pos)
			case 'n':
				normal := parse_vec3(line[3:])
				append(&normals, normal)
			case 't':
				uv := parse_uv(line[3:])
				append(&uvs, uv)
			}
		case 'f':
			indices := parse_face(line[2:])
			append_elems(&faces, indices[0], indices[1], indices[2])
		}
	}

	return {
		positions = positions[:],
		normals = normals[:],
		uvs = uvs[:],
		faces = faces[:],
	}
}

obj_destroy :: proc(obj: Obj_Data) {
	delete(obj.positions)
	delete(obj.normals)
	delete(obj.uvs)
	delete(obj.faces)
}

@private
extract_separated :: proc(s: ^string, sep: byte) -> string {
	sub, ok := strings.split_by_byte_iterator(s, sep)
	assert(ok)
	return sub
}

@private
parse_f32 :: proc(s: string) -> f32 {
	res, ok := strconv.parse_f32(s)
	assert(ok)
	return res
}

@private
parse_uint :: proc(s: string) -> uint {
	res, ok := strconv.parse_uint(s)
	assert(ok)
	return res
}

@private
parse_vec3 :: proc(s: string) -> glm.vec3 {
	s := s
	x := parse_f32(extract_separated(&s, ' '))
	y := parse_f32(extract_separated(&s, ' '))
	z := parse_f32(extract_separated(&s, ' '))
	return {x,y,z}
}

@private
parse_uv :: proc(s: string) -> glm.vec2 {
	s := s
	u := parse_f32(extract_separated(&s, ' '))
	v := parse_f32(extract_separated(&s, ' '))
	return {u,v}
}

@private
parse_face :: proc(s: string) -> [3]Obj_FaceIndex {
	s := s
	return {
		parse_face_index(extract_separated(&s, ' ')),
		parse_face_index(extract_separated(&s, ' ')),
		parse_face_index(extract_separated(&s, ' ')),
	}
}

@private
parse_face_index :: proc(s: string) -> Obj_FaceIndex {
	s := s
	return {
		pos = parse_uint(extract_separated(&s, '/')) - 1,
		uv = parse_uint(extract_separated(&s, '/')) - 1,
		normal = parse_uint(extract_separated(&s, '/')) - 1,
	}
}

package learn_sdlgpu

import "core:log"
import sdl "vendor:sdl3"

toggle :: proc(value: ^bool) {
	value^ = !value^
}

@(disabled = ODIN_DISABLE_ASSERT)
sdl_assert_ptr :: proc(ptr: rawptr, msg := "Error") {
	if ptr == nil {
		log.panicf("[SDL] %s: %s", msg, sdl.GetError())
	}
}

@(disabled = ODIN_DISABLE_ASSERT)
sdl_assert :: proc(value: bool, msg := "Error") {
	if !value {
		log.panicf("[SDL] %s: %s", msg, sdl.GetError())
	}
}

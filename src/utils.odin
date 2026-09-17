package learn_sdlgpu

import "core:log"
import sdl "vendor:sdl3"

_ :: log
_ :: sdl

toggle :: proc(value: ^bool) {
	value^ = !value^
}

sdl_assert :: proc {
	sdl_assert_ptr,
	sdl_assert_bool,
}

sdl_assert_ptr :: proc(ptr: rawptr, msg := "Error") {
	when !ODIN_DISABLE_ASSERT {
		if ptr == nil {
			log.panicf("[SDL] %s: %s", msg, sdl.GetError())
		}
	}
}

sdl_assert_bool :: proc(value: bool, msg := "Error") {
	when !ODIN_DISABLE_ASSERT {
		if !value {
			log.panicf("[SDL] %s: %s", msg, sdl.GetError())
		}
	}
}

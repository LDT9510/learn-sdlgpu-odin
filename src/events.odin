package learn_sdlgpu

import "core:c"
import "core:mem"
import sdl "vendor:sdl3"

Key_Input_Handler_Proc :: #type proc()
Events_Handler_Proc :: #type proc(event: sdl.Event, window: ^sdl.Window)

MAX_SDL_SCANCODES :: 512 // this is missing from the bindings
_g_previous_keyboard_state: [MAX_SDL_SCANCODES]bool

events_is_key_pressed :: proc(key: sdl.Scancode) -> bool {
	return sdl.GetKeyboardState(nil)[key]
}

events_is_key_just_pressed :: proc(key: sdl.Scancode) -> bool {
	return sdl.GetKeyboardState(nil)[key] && !_g_previous_keyboard_state[key]
}

events_is_mouse_button_pressed :: proc(button: sdl.MouseButtonFlags) -> bool {
	button_flag := sdl.GetMouseState(nil, nil)
	return button_flag == button
}

events_handle :: proc(kih: Key_Input_Handler_Proc,
	eh: Events_Handler_Proc,
	window: ^sdl.Window,
) {
	e: sdl.Event
	for sdl.PollEvent(&e) {
		devui_process_event(&e)

		if !devui_wants_mouse_input() {
			eh(e, window)
		}
	}

	if !devui_wants_keyboard_input() {
		sdl.PumpEvents()
		kih()
		num_keys: c.int
		keyboard_state := sdl.GetKeyboardState(&num_keys)
		mem.copy(&_g_previous_keyboard_state, keyboard_state, cast(int)num_keys)
	}
}

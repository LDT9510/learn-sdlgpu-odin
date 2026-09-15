package learn_sdlgpu

import sdl "vendor:sdl3"

Timings :: struct {
	delta_time:       f32,
	frame_time_ms:    f32,
	fps:              i32,

	// helper counters
	_frame_acc:       i32,
	_last_frame_time: u64,
	_last_mark_ms:    u64,
}

timing_get_elapsed_seconds :: proc() -> f32 {
	return cast(f32)timing_get_elapsed_ms() / 1000
}

timing_get_elapsed_ms :: proc() -> u64 {
	return sdl.GetTicks()
}

timing_update :: proc(t: ^Timings) {
	curr_frame_time := timing_get_elapsed_ms()
	t.delta_time = f32(curr_frame_time - t._last_frame_time) / 1000
	t._last_frame_time = curr_frame_time

	if curr_frame_time - t._last_mark_ms > 1000 {
		t.fps = t._frame_acc
		t.frame_time_ms = 1000 / cast(f32)t.fps
		t._last_mark_ms = timing_get_elapsed_ms()
		t._frame_acc = 0
	} else {
		t._frame_acc += 1
	}
}

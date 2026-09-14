package learn_sdlgpu

import sdl "vendor:sdl3"

WINDOW_WIDTH :: 1200
WINDOW_HEIGHT :: 960

window_create_and_device :: proc() -> (^sdl.Window, ^sdl.GPUDevice) {
	sdl_assert(sdl.Init({.VIDEO}))

	window := sdl.CreateWindow("Learning SDL_GPU", WINDOW_WIDTH, WINDOW_HEIGHT, {.RESIZABLE})
	sdl_assert_ptr(window, "Could not create window")

	device := sdl.CreateGPUDevice({.SPIRV, .DXIL}, ODIN_DEBUG, "vulkan")
	sdl_assert_ptr(device, "Could not create GPU device")

	sdl_assert(sdl.ClaimWindowForGPUDevice(device, window))
	sdl_assert(sdl.SetGPUSwapchainParameters(device, window, .SDR, .VSYNC))

	return window, device
}

window_destroy :: proc(window: ^sdl.Window, device: ^sdl.GPUDevice) {
	sdl.ReleaseWindowFromGPUDevice(device, window)
	sdl.DestroyGPUDevice(device)
	sdl.DestroyWindow(window)
	sdl.Quit()
}

window_get_resolution :: proc(window: ^sdl.Window) -> (f32, f32) {
	x, y: i32
	sdl.GetWindowSize(window, &x, &y)
	return cast(f32)x, cast(f32)y
}

window_get_aspect_ratio :: proc(window: ^sdl.Window) -> f32 {
	x, y := window_get_resolution(window)
	return x / y
}

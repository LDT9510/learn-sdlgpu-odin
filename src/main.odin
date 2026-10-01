package learn_sdlgpu

import glm "core:math/linalg/glsl"
import "core:sys/windows"
import sdl "vendor:sdl3"
import "core:log"

UI_bool :: struct {
	name:    cstring,
	value:   bool,
	toggled: bool,
}

g: struct {
	window           : ^sdl.Window,
	device           : ^sdl.GPUDevice,
	should_close       : bool,
	is_capturing_mouse : bool,
	vsync              : UI_bool,
	camera             : Camera,
	clear_color        : glm.vec4,
} = {
	should_close       = false,
	is_capturing_mouse = false,
	vsync              = {"VSYNC",true, false},
	camera             = camera_create({0, 1, -3}),
	clear_color        = {0, 0.2, 0.4, 1},
}

main :: proc() {
	context = context_setup()
	defer context_teardown()

	// windows specific fix
	when ODIN_OS == .Windows {
		windows.SetProcessDPIAware()
	}

	// window
	g.window, g.device = window_create_and_device()
	defer window_destroy(g.window, g.device)

	// developer UI
	devui_init(g.window, g.device)
	defer devui_shutdown(g.device)

	// create depth and stencil texture
	depth_stencil_texture := texture_create_depth_stencil(g.device, g.window)
	defer sdl.ReleaseGPUTexture(g.device, depth_stencil_texture)

	// create pipeline
	pipeline := renderer_create_pipeline(g.device, g.window)
	defer sdl.ReleaseGPUGraphicsPipeline(g.device, pipeline)

	timings: Timings

	game := game_init()
	defer game_destroy(game)

	for !g.should_close {
		// ------------------ update ------------------
		timing_update(&timings)
		game_update(&game, timings)

		cmd_buf := sdl.AcquireGPUCommandBuffer(g.device)
		sdl_assert(cmd_buf)

		if g.vsync.toggled {
			log.infof("%s %s", g.vsync.name, g.vsync.value ? "ON" : "OFF")
			sdl_assert(
				sdl.SetGPUSwapchainParameters(
					g.device,
					g.window,
					.SDR_LINEAR,
					g.vsync.value ? .VSYNC : .IMMEDIATE,
				),
			)
			g.vsync.toggled = false
		}

		swapchain_tex: ^sdl.GPUTexture
		sdl_assert(
			sdl.WaitAndAcquireGPUSwapchainTexture(
				cmd_buf, g.window, &swapchain_tex, nil, nil,
			),
		)

		if swapchain_tex != nil {
			render_data := Render_State {
				target_texture = swapchain_tex,
				depth_texture = depth_stencil_texture,
				command_buffer = cmd_buf,
				pipeline = pipeline,
			}

			game_render(game, render_data)

			// render ui
			devui_begin_frame()
			window_main_ui(timings, g.window, g.device)
			devui_render_frame(swapchain_tex, cmd_buf)
		}

		sdl_assert(sdl.SubmitGPUCommandBuffer(cmd_buf))

		free_all(context.temp_allocator)
	}
}


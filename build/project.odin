package build_tool

import "core:os"
import "core:log"

// NOTE: executables in "OUTPUT_DIR" are not portable

PROJECT_NAME :: "learn_sdlgpu"
SOURCE_DIR   :: "src"

DEFINITIONS := [?]Named_Prop{
	{"CONTENT_ROOT", ".."},
}

VETTABLE_PACKAGES := [?]string {
	PROJECT_NAME,
}

WARNING_FLAGS := [?]string {
	"vet",
	"vet-semicolon",
	"vet-style",
	"vet-tabs",
	"warnings-as-errors",
	"strict-style",
}

COLLECTIONS := [?]Named_Prop {
	{"extern", "extern"},
	{"main",   "src"},
}

// make multiplatform
RUNTIME_DEPS := [?]string {
	make_path(MISC_DIR,     "imgui.ini"),
	make_path(BINARIES_DIR, "win32", "SDL3.dll"),
	make_path(BINARIES_DIR, "win32", "WinPixEventRuntime.dll"),
}

build_dev :: proc() -> string {
	return odin_build("dev",{"microarch:native", "linker:radlink"})
}

build_debug :: proc(options: []string) -> string {
	executable_name := odin_build("debug", {"debug", "linker:radlink"})

	if has_option(options, .Launch) {
		raddbg := declare_tool_requirement("Debug '-attach' (RadDebbugger)", "raddbg")
		raddbg_config := make_path("--project:..", MISC_DIR, "project.raddbg")
		log.info("Running RadDebbugger")
		run(
			{raddbg, executable_name, raddbg_config},
			cd = OUTPUT_DIR,
			wait = false,
		)
	}

	if has_option(options, .Render) {
		rd_ui := declare_tool_requirement("Debug '-render' (RenderDoc)", "renderdocui")
		log.info("Running Renderdoc")
		run(
			{rd_ui, "capture", executable_name},
			cd = OUTPUT_DIR,
			wait = false,
		)
	}

	return executable_name
}

build_release :: proc(options: []string) -> string {
	suffix := ""
	flags: [dynamic]string

	if has_option(options, .Size) {
		suffix = "min"
		append(&flags, "o:size")
	} else {
		append(&flags, "o:speed")
	}

	append(&flags, "subsystem:windows")
	append(&flags, "disable-assert")
	append(&flags, "no-type-assert")

	return odin_build(suffix, flags[:])
}

// no cleanup
main :: proc() {
	context.allocator = context.temp_allocator

	command, options, logger := parse_command_line()

	if command == .Help {
		show_help_message()
		os.exit(0)
	}

	context.logger = logger

	log.infof("Build type: %v", command)

	copy_runtime_dependencies_to_output()

	parse_graphics_api_override(options)

	if !has_option(options, .Skip_Shaders) {
		compile_shaders(options, command == .Debug)
	}

	is_debug := false
	executable_name: string
	switch command {
	case .Dev:
		executable_name = build_dev()
	case .Debug:
		executable_name = build_debug(options)
		is_debug = true
	case .Release:
		executable_name = build_release(options)
	case .Help:
		// handled above
	}

	log.info("Build finished")

	if has_option(options, .Run) {
		exe := out_path(executable_name)
		log.infof("Running '%s'", exe)
		run({exe}, OUTPUT_DIR)
	}
}

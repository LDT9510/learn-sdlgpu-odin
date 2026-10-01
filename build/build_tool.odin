package build_tool

import "core:os"
import "core:log"
import "core:slice"
import "core:strings"
import "core:path/filepath"
import "core:reflect"

OUTPUT_DIR         :: #config(OUTPUT_DIR, ".out")

MISC_DIR              :: "misc"
BINARIES_DIR          :: "binaries"
EXE_EXTENSION         :: ".exe" when ODIN_OS == .Windows else ""
CONTENT_PATH          :: "content"
SHADERS_OUT_DIR       :: "shaders_out"
SHADERS_OUT_DIR_DEBUG :: "shaders_out_debug"
SHADERS_SOURCE_DIR    := make_path(SOURCE_DIR, "shaders")

// dynamic definitions TODO: generate source with #config
SELECTED_GRAPHICS_API_DEFINE :: "SELECTED_GRAPHICS_API"
SHADERS_OUT_PATH_DEFINE :: "SHADERS_OUT_PATH"

Graphics_API :: enum {
	Vulkan,
	DirectX12,
	Metal,
}
SHADER_OUT_FORMATS := [Graphics_API]string {
	.Vulkan = "spv",
	.DirectX12 = "dxil",
	.Metal = "msl",
}
G_API_SDL_DRIVER_NAME := [Graphics_API]string {
	.Vulkan = "vulkan",
	.DirectX12 = "direct3d12",
	.Metal = "metal",
}
G_API_SHORT_NAME := [Graphics_API]string {
	.Vulkan = "vk",
	.DirectX12 = "dx12",
	.Metal = "mtl",
}

Command :: enum {
	Dev,
	Debug,
	Release,
	Help,
}
COMMANDS_HELP := [Command]string {
	.Dev = "Fast compilation with minimal optimizations. For development.",
	.Debug = "Retains debug information and disable optimizations. For debugging.",
	.Release = "Can be optimized for speed or size. For distribution.",
	.Help = "Show help message",
}

Option :: enum {
	Verbose,
	Launch,
	Render,
	Size,
	Vulkan,
	Skip_Shaders,
	Run,
}
OPTIONS_HELP := [Option]string {
	.Verbose = "Make logging more verbose (all)",
	.Launch = "Launch RadDebugger with the executable being built as target ('debug')" ,
	.Render = "Launch Renderdoc with the executable being built as target ('debug')",
	.Size = "Release build optimized for size ('release')",
	.Vulkan = "Use Vulkan as the SDL_GPU backend (all)",
	.Skip_Shaders = "Do not build shaders. (all)",
	.Run = "Run the executable being build. (all)",
}

Named_Prop :: struct {
	name: string,
	value: string,
}

// TODO: consider target platform, not host
when ODIN_OS == .Windows {
	g_selected_graphics_api: Graphics_API = .DirectX12
} else when ODIN_OS == .Linux {
	g_selected_graphics_api: Graphics_API = .Vulkan
} else when ODIN_OS == .Darwin {
	g_selected_graphics_api: Graphics_API = .Metal
} else {
	#panic("Unsupported platform")
}
g_graphics_api_overriden := false

g_shaders_out_path: string

odin_build :: proc(target_suffix: string, extra_flags: []string) -> string {
	log.infof("Building project '%s'", PROJECT_NAME)

	target_name := PROJECT_NAME
	if target_suffix != "" {
		target_name = strings.concatenate({target_name, "_", target_suffix})
	}
	if g_graphics_api_overriden {
		target_name = strings.concatenate({target_name, "_", G_API_SHORT_NAME[g_selected_graphics_api]})
	}
	executable_name := strings.concatenate({target_name, EXE_EXTENSION})

	sb := strings.builder_make()
	strings.write_string(&sb, "odin build ")
	strings.write_string(&sb, SOURCE_DIR + " ")
	strings.write_string(&sb, "-out:")
	strings.write_string(&sb, out_path(executable_name))

	for warning in WARNING_FLAGS {
		strings.write_string(&sb, " -")
		strings.write_string(&sb, warning)
	}

	strings.write_string(&sb, " -vet-packages:")
	for pack in VETTABLE_PACKAGES {
		strings.write_string(&sb, pack)
		strings.write_byte(&sb, ',')
	}

	for collection in COLLECTIONS {
		strings.write_string(&sb, " -collection:")
		strings.write_string(&sb, collection.name)
		strings.write_byte(&sb, '=')
		strings.write_string(&sb, collection.value)
	}

	for define in DEFINITIONS {
		strings.write_string(&sb, " -define:")
		strings.write_string(&sb, define.name)
		strings.write_byte(&sb, '=')
		strings.write_string(&sb, define.value)
	}

	strings.write_string(&sb, " -define:" + SELECTED_GRAPHICS_API_DEFINE + "=")
	strings.write_string(&sb, G_API_SDL_DRIVER_NAME[g_selected_graphics_api])

	strings.write_string(&sb, " -define:" + SHADERS_OUT_PATH_DEFINE + "=")
	strings.write_string(&sb, g_shaders_out_path)

	for extra in extra_flags {
		strings.write_string(&sb, " -")
		strings.write_string(&sb, extra)
	}

	run_str(strings.to_string(sb))

	return executable_name
}

parse_command_line :: proc() -> (command: Command, options: []string, logger: log.Logger) {
	// for any errors during parsing
	temp_logger := log.create_console_logger(
		opt = {} , ident = "BUILD",
	)
	defer log.destroy_console_logger(temp_logger)
	context.logger = temp_logger

	if len(os.args) > 1 {
		if os.args[1][0] == '-' {
			options = os.args[1:]
		} else {
			command = parse_command(os.args[1])

			if len(os.args) > 2 {
				options = os.args[2:]
			}
		}
	}
	validate_options(options)

	if has_option(options, .Verbose) {
		logger = log.create_console_logger(
			opt = {.Level} , ident = "BUILD",
		)
	} else {
		logger = log.create_console_logger(
			lowest = .Info, opt = {} , ident = "BUILD",
		)
	}

	return command, options, logger
}

parse_command :: proc(cmd: string) -> Command {
	normalized_cmd := strings.to_ada_case(cmd)
	build_command, ok := reflect.enum_from_name(Command, normalized_cmd)

	if ok {
		return build_command
	}

	valid_commands := make([]string, len(Command))
	for name, i in reflect.enum_field_names(Command) {
		valid_commands[i] = strings.to_lower(name)
	}
	error("Unknown command: '%s'\n\t\tValid commands: %v", cmd, valid_commands)
}

validate_options :: proc(options: []string) {
	unknown_list: [dynamic]string

	for opt in options {
		if opt[0] != '-' {
			append(&unknown_list, opt)
			continue
		}

		normalized_option := strings.to_ada_case(opt[1:])
		_, ok := reflect.enum_from_name(Option, normalized_option)
		if !ok {
			append(&unknown_list, opt)
		}
	}

	if len(unknown_list) > 0 {
		error("Unknown options: %v\nUse 'build help' for valid options.",
			 strings.join(unknown_list[:], sep = " "),
		)
	}
}

has_option:: proc(options: []string, option: Option) -> bool {
	name, ok := reflect.enum_name_from_value(option)
	if ok {
		name_normalized := strings.concatenate({"-", strings.to_lower(name)})
		return slice.contains(options, name_normalized)
	}

	return false
}

parse_graphics_api_override :: proc(options: []string) {
	if has_option(options, .Vulkan) {
		g_selected_graphics_api = .Vulkan
		g_graphics_api_overriden = true
	}
}

compile_shaders :: proc(options: []string, debug: bool) {
	log.infof("Compiling shaders for %v", g_selected_graphics_api)

	flags := ""
	g_shaders_out_path = SHADERS_OUT_DIR
	if debug {
		flags = "-g"
		g_shaders_out_path = SHADERS_OUT_DIR_DEBUG
	}

	shaders_output_dir := make_path({CONTENT_PATH, g_shaders_out_path})
	if !os.exists(shaders_output_dir) {
		os.make_directory(shaders_output_dir)
	}

	format := SHADER_OUT_FORMATS[g_selected_graphics_api]
	sc := declare_tool_requirement("Compiling shaders", "shadercross")

	files, err := os.read_all_directory_by_path(SHADERS_SOURCE_DIR, context.allocator)
	if err != nil {
		error("Cannot read shader sources: %v", os.error_string(err))
	}

	inner_out_dir := make_path({shaders_output_dir, format})
	if !os.exists(inner_out_dir) {
		os.make_directory(inner_out_dir)
	}

	count: int
	for file in files {
		count += 1
		shader_in := file.fullpath
		basename := filepath.stem(file.name)
		output_name := strings.concatenate({basename, ".", format})
		shader_out := make_path({inner_out_dir, output_name})
		reflect_output_name := strings.concatenate({basename, ".", "json"})
		reflect_out := make_path({inner_out_dir, reflect_output_name})

		run({sc, shader_in, "-o", shader_out, flags})
		run({sc, shader_in, "-o", reflect_out, flags})
	}

	log.infof("%d shaders compiled.", count)
}

show_help_message :: proc() {
	context.logger = log.create_console_logger(opt = {})

	message := """
	This is a helper tool to build and launch programs.
	Options apply for specific commands only or all (except 'help')

	Usage:
		build <command> [-option1][-option2][...]
	Commands:%s
	Options:%s
	"""

	sb := strings.builder_make()

	descriptions :: proc(desc_map: [$T]string, sb: ^strings.Builder, prefix := "") -> string {
		strings.builder_reset(sb)

		for field in reflect.enum_fields_zipped(T) {
			strings.write_string(sb, "\n\t")
			strings.write_string(sb, prefix)
			strings.write_string(sb, strings.to_lower(field.name))
			name_size := len(prefix) + len(field.name)
			for _ in 0..<(15 - name_size) {
				strings.write_string(sb, " ")
			}
			strings.write_string(sb, desc_map[cast(T)field.value])
		}

		return strings.clone(strings.to_string(sb^))
	}

	log.infof(
		message,
		descriptions(COMMANDS_HELP, &sb),
		descriptions(OPTIONS_HELP, &sb, "-"),
	)
}

copy_runtime_dependencies_to_output :: proc() {
	if !os.exists(OUTPUT_DIR) {
		os.make_directory(OUTPUT_DIR)
	}

	copied: int

	for dep in RUNTIME_DEPS {
		file_name := filepath.base(dep)
		path := make_path({OUTPUT_DIR, file_name})

		if !os.exists(path) {
			copied += 1
			log.debugf("Copying '%s' to '%s'", dep, path)
			err := os.copy_file(path, dep)
			if err != nil {
				error("Copy problem: %v", os.error_string(err))
			}
		}
	}

	if copied > 0 {
		log.infof("Copied %d runtime dependencies to ouput folder", copied)
	} else {
		log.info("Runtime dependencies up to date")
	}
}

declare_tool_requirement :: proc(what: string, tool: string) -> string {
	log.debugf("%s requires executable '%s' to be in PATH.", what, tool)
	return tool
}

run_str :: proc(cmd: string, cd := "") {
	run(strings.split(cmd, " "), cd)
}

run :: proc(cmd: []string, cd := "", wait := true) {
	log.debugf("Running Command:\n\t%v", strings.join(cmd, sep = " "))

	code, err := exec(cmd, cd, wait)
	if err != nil {
		general_err, ok := err.(os.General_Error)
		if ok && general_err == .Not_Exist {
			error("Program '%s' was not found in PATH", cmd[0])
		} else {
			error("Error executing process: %s", os.error_string(err))
		}
	}
	if code != 0 {
		error("Process exited with non-zero code %v", code)
	}

	exec :: proc(cmd: []string, cd :string, wait: bool) -> (code: int, error: os.Error) {
		process := os.process_start({
			working_dir = cd,
			command = cmd,
			stdin = os.stdin,
			stdout = os.stdout,
			stderr = os.stderr,
		}) or_return

		if wait {
			state := os.process_wait(process) or_return
			code = state.exit_code
			os.process_terminate(process) or_return
		} else {
			code = 0
		}
		return code, nil
	}
}

error :: proc(msg: string, args: ..any) -> ! {
	log.errorf(msg, ..args)
	os.exit(1)
}

out_path :: proc(path: string) -> string {
	return make_path({OUTPUT_DIR, path})
}

make_path :: proc {
	runtime_make_path,
	make_path2,
	make_path3,
}

runtime_make_path :: proc(paths: []string) -> string {
	joined, err := filepath.join(paths)
	if err != nil {
		error("Error joining paths: %v (%v)", paths, err)
	}

	return joined
}

PS :: os.Path_Separator_String

make_path2 :: #force_inline proc "contextless" ($p1, $p2: string) -> string {
	return p1 + PS + p2
}

make_path3 :: #force_inline proc "contextless" ($p1, $p2, $p3: string) -> string {
	return p1 + PS + p2 + PS + p3
}

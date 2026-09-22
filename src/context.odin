package learn_sdlgpu

import "base:runtime"
import "core:log"
import "core:mem"
import sdl "vendor:sdl3"

MAX_ALLOCATION_ERROR_MESSAGES :: 20

@(private="file")
_g_context_internal : struct {
	custom_context: runtime.Context,
	tracking_allocator: mem.Tracking_Allocator,
	temp_tracking_allocator: mem.Tracking_Allocator,
	console_logger: log.Logger,
}

context_setup :: proc() -> runtime.Context {
	default_allocator := runtime.default_allocator()

	// setup logging (no allocation tracking)
	_g_context_internal.console_logger = log.create_console_logger(
		opt = {.Level},
		allocator = default_allocator,
	)
	context.logger = _g_context_internal.console_logger

	// setup allocation
	when ODIN_DEBUG {
		context.allocator = _create_tracking_allocator(
			&_g_context_internal.tracking_allocator,
			context.allocator,
			default_allocator,
		)
		context.temp_allocator = _create_tracking_allocator(
			&_g_context_internal.temp_tracking_allocator,
			context.temp_allocator,
			default_allocator,
		)

		debug_mode := true
		sdl_log_priority: sdl.LogPriority = .VERBOSE
	} else {
		debug_mode := false
		sdl_log_priority: sdl.LogPriority = .INFO
	}

	_g_context_internal.custom_context = context

	sdl.SetLogPriorities(sdl_log_priority)
	sdl.SetLogOutputFunction(_sdl_log_adapter, nil)

	log.info("Initializing program")

	if debug_mode {
		log.debug("-------- Debug mode --------")
	}

	return context
}

context_teardown :: proc() {
	when ODIN_DEBUG {
		_destroy_tracking_allocator(&_g_context_internal.tracking_allocator)
		_destroy_tracking_allocator(&_g_context_internal.temp_tracking_allocator, temp = true)
	}

	log.destroy_console_logger(
		_g_context_internal.console_logger,
		runtime.default_allocator(),
	)
}

_create_tracking_allocator :: proc(tracking: ^mem.Tracking_Allocator ,backing, internal: mem.Allocator) -> mem.Allocator {
	mem.tracking_allocator_init(tracking, backing, internal)
	return mem.tracking_allocator(tracking)
}

_destroy_tracking_allocator :: proc(tracking_allocator: ^mem.Tracking_Allocator, temp := false) -> bool {
	err := false
	remaining_allocations := len(tracking_allocator.allocation_map)

	if remaining_allocations > 0 {
		prefix := temp ? "Temp Allocator" : "Heap Allocator"
		log.errorf("(%s) Leaked allocation count: %v", prefix, len(tracking_allocator.allocation_map))
	}

	allocations_noticed := 0
	for _, v in tracking_allocator.allocation_map {
		log.errorf("%v: Leaked %v bytes", v.location, v.size)
		err = true
		allocations_noticed += 1

		if allocations_noticed > MAX_ALLOCATION_ERROR_MESSAGES {
			log.errorf(
				"(... +%d leaked allocations)",
				remaining_allocations - allocations_noticed + 1,
			)
			break
		}
	}

	mem.tracking_allocator_destroy(tracking_allocator)

	return err
}

_sdl_log_adapter :: proc "c" (
	_userdata: rawptr,
	category: sdl.LogCategory,
	priority: sdl.LogPriority,
	message: cstring,
) {
	context = _g_context_internal.custom_context

	switch priority {
	case .INVALID:
		fallthrough
	case .TRACE:
		fallthrough
	case .VERBOSE:
		fallthrough
	case .DEBUG:
		log.debugf("[SDL %s] %s", category, message)
	case .INFO:
		log.infof("[SDL %s] %s", category, message)
	case .WARN:
		log.warnf("[SDL %s] %s", category, message)
	case .ERROR:
		log.errorf("[SDL %s] %s", category, message)
	case .CRITICAL:
		log.fatalf("[SDL %s] %s", category, message)
	}
}

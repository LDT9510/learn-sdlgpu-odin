@echo off
setlocal EnableDelayedExpansion

rem NOTE: executables in "output_dir" are not portable

set project_name=learn_sdlgpu

set command="%~1"
set output_dir=.bin
set input=src
set executable=%project_name%_dev.exe

set vettable_packages=%project_name%

set warnings_flags=^
	-vet^
	-vet-packages:%vettable_packages%^
	-vet-semicolon^
	-vet-style^
	-vet-tabs^
	-warnings-as-errors^
	-strict-style

set collections_flags=^
	-collection:extern=extern^
	-collection:main=src

set opt_flags=^
	-linker:radlink^
	-microarch:native

set defines_flags=^
	-define:CONTENT_ROOT=../

set is_command_known=no
set build_all=no
set is_debug=no
set attach_debugger=no
set run_renderdoc=no
set just_compile_shaders=no

if %command%=="" (
	set is_command_known=yes
)
if %command%=="format" (
	set is_command_known=yes
	odinfmt src -w
	exit /b 0
)
if %command%=="debug" (
	set executable=%project_name%_debug.exe
	set is_command_known=yes
	set is_debug=yes
	set opt_flags=^
		-debug

	if "%~2"=="attach" (
		set attach_debugger=yes
	)

	if "%~2"=="render" (
		set run_renderdoc=yes
	)
)
if %command%=="release" (
	set executable=%project_name%.exe
	set is_command_known=yes

	if "%~2"=="" (
		set opt_flags=^
			-o:speed
	)
	if "%~2"=="size" (
		set executable=%project_name%_min.exe
		set opt_flags=^
			-o:size
	)
	set extra_flags=^
		-subsystem:windows^
		-disable-assert^
		-no-type-assert
)
if %command%=="shader" (
	set is_command_known=yes
	set just_compile_shaders=yes
)

if %is_command_known%==no (
	echo Unknown command %command%
	exit /b 1
)

set build_flags=^
	%collections_flags%^
	%warnings_flags%^
	%opt_flags%^
	%extra_flags%^
	%defines_flags%

set final_build_command=odin build %input% -out:%output_dir%\%executable% %build_flags%

if not exist %output_dir% md %output_dir%

echo Building shaders
glslc src/shader.vert -g -o src/shader.vert.spv
if %ERRORLEVEL% neq 0 exit /b 1
echo Vertex OK
glslc src/shader.frag -g -o src/shader.frag.spv
if %ERRORLEVEL% neq 0 exit /b 1
echo Fragment OK
if %just_compile_shaders%==yes exit /b 0

echo Running: %final_build_command%
%final_build_command%

if %ERRORLEVEL%==0 (
	cd %output_dir%

	if %attach_debugger%==yes (
		set misc_dir=..\misc
		if not exist !misc_dir! mkdir !misc_dir!
		start raddbg.exe %executable% --project:!misc_dir!\project.raddbg
		exit /b 0
	)

	if %run_renderdoc%==yes (
		start renderdocui.exe capture %executable%
		exit /b 0
	)

	.\%executable%
)

exit /b %ERRORLEVEL%

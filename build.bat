@echo off

:: Set to "yes" for development of the build tool
:: Delete %out_dir% after disabling development mode
set DEV=yes

:: Output directory for temporary files, safe to delete
set out_dir=.out

set tool_name=build_tool
set tool_out_path=%out_dir%\%tool_name%.exe
set tool_source_path=build

set warning_flags=^
	-vet^
	-vet-packages:%tool_name%^
	-vet-semicolon^
	-vet-style^
	-vet-tabs^
	-warnings-as-errors^
	-strict-style

set defines=^
	-define:OUTPUT_DIR=%out_dir%

set base_command=odin build %tool_source_path% %warning_flags% %defines%

if not exist %out_dir% mkdir %out_dir%

if %DEV%==yes (
	echo [BOOTSTRAP] Building '%tool_out_path%' DEV MODE
    %base_command% -linker:radlink -microarch:native -debug -out:%tool_out_path%
)

if %DEV%==no (
	if not exist %tool_out_path% (
		echo [BOOTSTRAP] Building '%tool_out_path%'
		%base_command% -o:speed -out:%tool_out_path%
	)
)

if %ERRORLEVEL% neq 0 exit /b 1
%tool_out_path% %*

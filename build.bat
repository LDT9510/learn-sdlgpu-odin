@echo off

:: Bootstrap script for this project, it builds a "build tool" that takes care of calling
:: the Odin compiler with the correct arguments and doing other build time tasks.
:: Run "build help" for options

:: Output directory for temporary files, safe to delete
set out_dir=.out

:: Use -boot or -bootdev to force a recompile of the build tool
set BOOT=no
echo %*|find "-boot" >nul
if %ERRORLEVEL% neq 1 set BOOT=yes
set BOOT_DEBUG=no
echo %*|find "-bootdev" >nul
if %ERRORLEVEL% neq 1 (
	set BOOT=yes
	set BOOT_DEBUG=yes
)

:: Build tool build parameters
set tool_base_name=build_tool
if %BOOT_DEBUG%==no  set tool_name=%tool_base_name%
if %BOOT_DEBUG%==yes set tool_name=%tool_base_name%_debug
set tool_out_path=%out_dir%\%tool_name%.exe
set tool_source_path=build
set warning_flags=^
	-vet^
	-vet-packages:%tool_base_name%^
	-vet-semicolon^
	-vet-style^
	-vet-tabs^
	-warnings-as-errors^
	-strict-style
set defines=^
	-define:OUTPUT_DIR=%out_dir%
set base_command=odin build %tool_source_path% %warning_flags% %defines%

:: Compile always if it does not exists
if not exist %tool_out_path% set BOOT=yes

:: Create the ouput directory
if not exist %out_dir% mkdir %out_dir%

:: Build the build tool
if %BOOT%==yes if %BOOT_DEBUG%==yes (
	echo [BOOTSTRAP] Building '%tool_out_path%' DEBUG MODE
	%base_command% -debug -out:%tool_out_path%
)
if %BOOT%==yes if %BOOT_DEBUG%==no (
	echo [BOOTSTRAP] Building '%tool_out_path%'
	%base_command% -o:speed -out:%tool_out_path%
)
if %BOOT%==yes if %ERRORLEVEL% neq 0 (
	echo Build tool build command failed
	exit /b 1
)

:: Run the build tool with the provided arguments
%tool_out_path% %*

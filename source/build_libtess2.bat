@echo off
setlocal

set SRC=libtess2-master\Source
set INC=libtess2-master\Include
set BIN=bin
set OUT=..\%BIN%\libtess2.lib

if not exist %BIN% mkdir %BIN%

echo Building libtess2 for Windows...

git submodule update --init
if %ERRORLEVEL% neq 0 (
    echo Failed to initialize submodules.
    exit /b 1
)

call patch_libtess2.bat

cl.exe /nologo /O2 /DTESS_USE_DOUBLE /I%INC% /c ^
    %SRC%\tess.c ^
    %SRC%\mesh.c ^
    %SRC%\sweep.c ^
    %SRC%\geom.c ^
    %SRC%\dict.c ^
    %SRC%\priorityq.c ^
    %SRC%\bucketalloc.c

if %ERRORLEVEL% neq 0 (
    echo Compilation failed.
    exit /b 1
)

lib.exe /nologo /OUT:%OUT% ^
    tess.obj mesh.obj sweep.obj geom.obj dict.obj priorityq.obj bucketalloc.obj

if %ERRORLEVEL% neq 0 (
    echo Linking failed.
    exit /b 1
)

del *.obj
echo Done. Output: %OUT%
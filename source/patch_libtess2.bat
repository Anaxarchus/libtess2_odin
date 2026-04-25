@echo off
setlocal enabledelayedexpansion

set HEADER=libtess2-master\Include\tesselator.h
set TMP=%TEMP%\tesselator_patched.h
set TARGET=typedef float TESSreal;
set FOUND=0

if not exist "%HEADER%" (
    echo Could not find %HEADER%
    exit /b 1
)

:: Check if patch is needed
findstr /c:"typedef float TESSreal;" "%HEADER%" >nul 2>&1
if %ERRORLEVEL% neq 0 (
    echo Patch already applied or target string not found in %HEADER%, skipping.
    exit /b 0
)

:: Write patched file line by line
(for /f "usebackq delims=" %%L in ("%HEADER%") do (
    set "LINE=%%L"
    if "!LINE!" == "        %TARGET%" (
        echo #ifdef TESS_USE_DOUBLE
        echo   typedef double TESSreal;
        echo #else
        echo   typedef float TESSreal;
        echo #endif
    ) else (
        echo !LINE!
    )
)) > "%TMP%"

move /y "%TMP%" "%HEADER%" >nul
echo Patched %HEADER% successfully.
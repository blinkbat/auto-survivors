@echo off
REM run.cmd - build (incremental) and launch.
setlocal
call "%~dp0_zig.cmd" || exit /b 1
taskkill /IM auto-survivors.exe /F >nul 2>&1
"%ZIG%" build run -Doptimize=ReleaseFast

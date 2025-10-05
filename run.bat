@echo off
setlocal ENABLEDELAYEDEXPANSION

REM Robust launcher: tries multiple ports, Python or npx, verifies server, opens browser
set PORTS=5501 8081 3000 5173
set CHOSEN=

for %%P in (%PORTS%) do (
  call :TRYPORT %%P
  if defined CHOSEN goto :LAUNCH
)

echo Could not start a local server (Python/Node not found). Opening file directly.
start "LoveMessage" index.html
goto :END

:TRYPORT
set PORT=%1
REM Try Python first
where python >nul 2>nul
if %ERRORLEVEL%==0 (
  echo [run] Starting Python HTTP server on port %PORT% ...
  start "LoveMessage-Server" cmd /c "python -m http.server %PORT% --bind 127.0.0.1"
  call :WAITUP %PORT%
  if !ERRORLEVEL! EQU 0 ( set CHOSEN=%PORT% & goto :eof )
)

REM Try npx http-server
where npx >nul 2>nul
if %ERRORLEVEL%==0 (
  echo [run] Starting npx http-server on port %PORT% ...
  start "LoveMessage-Server" cmd /c "npx http-server -a 127.0.0.1 -p %PORT% --silent"
  call :WAITUP %PORT%
  if !ERRORLEVEL! EQU 0 ( set CHOSEN=%PORT% & goto :eof )
)

echo [run] Skipping port %PORT% (no runtime or server not reachable).
exit /b 1

:WAITUP
REM Wait until http://127.0.0.1:%1 responds (max ~6s)
set WPORT=%1
for /L %%i in (1,1,12) do (
  powershell -NoProfile -Command "try { $null = Invoke-WebRequest -UseBasicParsing -Uri 'http://127.0.0.1:%WPORT%/' -Method Head -TimeoutSec 1; exit 0 } catch { exit 1 }"
  if !ERRORLEVEL! EQU 0 ( exit /b 0 )
  >nul timeout /t 0 >nul & >nul ping -n 2 127.0.0.1
)
exit /b 1

:LAUNCH
set URL=http://127.0.0.1:%CHOSEN%/index.html
echo [run] Opening %URL%
start "LoveMessage" %URL%

:END
endlocal

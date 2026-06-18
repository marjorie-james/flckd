@echo off
rem ===========================================================================
rem  flckd - double-click launcher for Windows (no WSL required).
rem
rem  A non-technical user can double-click this file. It needs two things, both
rem  one-click installers (NOT the heavy WSL2 setup):
rem
rem    1. Docker Desktop        https://docs.docker.com/get-docker/
rem    2. Git for Windows       https://git-scm.com/download/win
rem       (this provides "Git Bash", which runs the setup wizard - flckd's
rem        scripts are written in bash. This is far lighter than WSL2.)
rem
rem  This launcher checks for both, starts Docker if it is installed but not
rem  running, then hands off to the same setup wizard the Mac/Linux paths use.
rem ===========================================================================
setlocal enableextensions
cd /d "%~dp0"

echo.
echo   Starting flckd setup...
echo.

rem --- 1. Docker installed? ------------------------------------------------
where docker >nul 2>&1
if errorlevel 1 (
  echo   [X] Docker isn't installed yet - it's required.
  echo       Opening the Docker Desktop download page...
  start "" "https://docs.docker.com/get-docker/"
  echo       Install Docker Desktop, start it, then run this again.
  goto :pause_exit
)

rem --- 2. Docker running? If not, try to start Docker Desktop. -------------
docker info >nul 2>&1
if errorlevel 1 (
  echo   [..] Docker is installed but not running - starting it for you...
  if exist "%ProgramFiles%\Docker\Docker\Docker Desktop.exe" (
    start "" "%ProgramFiles%\Docker\Docker\Docker Desktop.exe"
  )
  echo       Waiting for Docker to be ready (this can take a minute)...
  set /a _tries=0
:waitdocker
  docker info >nul 2>&1
  if not errorlevel 1 goto dockerready
  set /a _tries+=1
  if %_tries% geq 60 (
    echo   [X] Docker didn't finish starting in time.
    echo       Open Docker Desktop yourself, wait until it says it's running,
    echo       then run this again.
    goto :pause_exit
  )
  timeout /t 2 /nobreak >nul
  goto waitdocker
:dockerready
  echo   [OK] Docker is running.
)

rem --- 3. Locate Git Bash (provides bash; not WSL). ------------------------
set "BASH_EXE="
for %%P in (
  "%ProgramFiles%\Git\bin\bash.exe"
  "%ProgramFiles(x86)%\Git\bin\bash.exe"
  "%LocalAppData%\Programs\Git\bin\bash.exe"
) do if exist "%%~P" set "BASH_EXE=%%~P"

if not defined BASH_EXE (
  rem Fall back to a bash already on PATH (e.g. a custom Git install).
  for /f "delims=" %%B in ('where bash 2^>nul') do if not defined BASH_EXE set "BASH_EXE=%%B"
)

if not defined BASH_EXE (
  echo   [X] Git Bash wasn't found - it runs the setup wizard.
  echo       Opening the Git for Windows download page...
  echo       (This is a small one-click installer - NOT WSL2.)
  start "" "https://git-scm.com/download/win"
  echo       Install Git for Windows ^(default options are fine^), then run this again.
  goto :pause_exit
)

rem --- 4. Hand off to the shared setup wizard via Git Bash. ----------------
echo   Launching the setup wizard...
echo.
"%BASH_EXE%" -lc "./infra/scripts/setup.sh"

:pause_exit
echo.
pause
endlocal

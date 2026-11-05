@echo off
setlocal
if "%~1"=="" (
  echo Usage: run_ferric ^<run^|check^|ast^|tokens^> ^<file.ferric^>
  exit /b 2
)
py -3 "%~dp0tools\ferric.py" %*
exit /b %errorlevel%

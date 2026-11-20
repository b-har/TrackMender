@echo off
rem Command-line build (Win64).  Usage: build [Debug|Release]
setlocal
set CFG=%1
if "%CFG%"=="" set CFG=Release
call "C:\Program Files (x86)\Embarcadero\Studio\37.0\bin\rsvars.bat"
msbuild "%~dp0TrackMender.dproj" /t:Build /p:Config=%CFG% /p:Platform=Win64 /nologo /v:minimal

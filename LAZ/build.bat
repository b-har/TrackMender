@echo off
rem Command-line build.  Usage: build [Debug|Release]
rem Needs Lazarus with the BGRABitmap package installed (Package > Online Package Manager).
setlocal
set CFG=%1
if "%CFG%"=="" set CFG=Release
set LAZBUILD=lazbuild
if exist "D:\lazarus\lazbuild.exe" set LAZBUILD=D:\lazarus\lazbuild.exe
if exist "C:\lazarus\lazbuild.exe" set LAZBUILD=C:\lazarus\lazbuild.exe
"%LAZBUILD%" --build-mode=%CFG% "%~dp0TrackMender.lpi"

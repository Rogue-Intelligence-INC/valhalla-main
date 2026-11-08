@echo off
setlocal
call "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\VC\Auxiliary\Build\vcvars64.bat" || exit /b 1
set "CMAKE=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\Common7\IDE\CommonExtensions\Microsoft\CMake\CMake\bin\cmake.exe"
set "QT=C:\Ai\Qt\6.8.3\msvc2022_64"
cd /d "%~dp0"
"%CMAKE%" -S . -B build -G "Visual Studio 17 2022" -A x64 -DCMAKE_PREFIX_PATH=%QT% || exit /b 1
"%CMAKE%" --build build --config Release || exit /b 1
if not exist dist mkdir dist
copy /y build\Release\ValhallaSetup.exe dist\ >nul || exit /b 1
"%QT%\bin\windeployqt.exe" --release --no-translations dist\ValhallaSetup.exe || exit /b 1
del /q dist\*.pdb 2>nul
echo Built dist\ValhallaSetup.exe. Next: assemble_packages.ps1 all, then make_single_exe.ps1 all.

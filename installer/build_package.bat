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

set "PKG=%~dp0..\release\VAL-DAL_A测版_安装包"
if exist "%PKG%" rmdir /s /q "%PKG%"
mkdir "%PKG%\payload\app" "%PKG%\payload\models" || exit /b 1
copy /y dist\ValhallaSetup.exe "%PKG%\瓦序VAL-DAL安装.exe" >nul || exit /b 1
xcopy /e /i /y dist\Qt6*.dll "%PKG%\" >nul || exit /b 1
if exist dist\platforms xcopy /e /i /y dist\platforms "%PKG%\platforms" >nul || exit /b 1
xcopy /e /i /y "..\qt\dist\*" "%PKG%\payload\app\" >nul || exit /b 1
copy /y "C:\Ai\Valhalla-main\target\release\valhalla_base.exe" "%PKG%\payload\app\" >nul || exit /b 1
mkdir "%PKG%\payload\models\Qwen2.5-0.5B-Instruct" || exit /b 1
xcopy /y "C:\Ai\models\Qwen2.5-0.5B-Instruct\*" "%PKG%\payload\models\Qwen2.5-0.5B-Instruct\" >nul || exit /b 1
echo 瓦序 VAL-DAL A测版安装包> "%PKG%\安装说明.txt"
echo 双击 瓦序VAL-DAL安装.exe 开始安装（不需要联网，不需要管理员）。>> "%PKG%\安装说明.txt"
echo 装到 C:\Ai\VAL-DAL，模型装到 C:\Ai\models，会自动建桌面快捷方式。>> "%PKG%\安装说明.txt"
echo Rogue Intelligence Inc. (Delaware, USA)>> "%PKG%\安装说明.txt"
echo Packaged: %PKG%

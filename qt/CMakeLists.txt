cmake_minimum_required(VERSION 3.21)
project(ValhallaQt LANGUAGES C CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Quick QuickControls2)
qt_standard_project_setup(REQUIRES 6.5)
qt_policy(SET QTP0004 NEW)

get_filename_component(VALHALLA_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/.." ABSOLUTE)
set(NATIVE_SRC "${VALHALLA_ROOT}/native/src")
set(NATIVE_TP "${VALHALLA_ROOT}/native/third_party")

# C++/WinRT headers for the OCR module, same kit the native build used.
file(GLOB WINRT_INCLUDE LIST_DIRECTORIES true "C:/Program Files (x86)/Windows Kits/10/Include/*/cppwinrt")
list(SORT WINRT_INCLUDE)
list(GET WINRT_INCLUDE -1 WINRT_INCLUDE)

qt_add_executable(Valhalla
    src/main.cpp
    src/app.rc
    src/Bridge.cpp
    src/Bridge.h
    src/tts.cpp
    src/tts.h
    "${NATIVE_SRC}/engine.cpp"
    "${NATIVE_SRC}/knowledge.cpp"
    "${NATIVE_SRC}/sessions.cpp"
    "${NATIVE_SRC}/desktop.cpp"
    "${NATIVE_SRC}/ocr.cpp"
    "${NATIVE_TP}/puff/puff.c"
)

set_source_files_properties("${VALHALLA_ROOT}/brand/valdal-black.png" PROPERTIES QT_RESOURCE_ALIAS logo-black.png)
set_source_files_properties("${VALHALLA_ROOT}/brand/valdal-white.png" PROPERTIES QT_RESOURCE_ALIAS logo-white.png)
qt_add_qml_module(Valhalla
    URI Valhalla
    VERSION 1.0
    QML_FILES qml/Main.qml
    RESOURCES "${VALHALLA_ROOT}/brand/valdal-black.png" "${VALHALLA_ROOT}/brand/valdal-white.png"
)

target_include_directories(Valhalla PRIVATE
    src
    "${NATIVE_SRC}"
    "${NATIVE_TP}"
    "${WINRT_INCLUDE}"
)

target_compile_definitions(Valhalla PRIVATE UNICODE _UNICODE NOMINMAX _CRT_SECURE_NO_WARNINGS)

target_link_libraries(Valhalla PRIVATE
    Qt6::Quick
    Qt6::QuickControls2
    user32 gdi32 advapi32 kernel32 dwmapi gdiplus comctl32 winhttp uxtheme shlwapi
    ole32 oleaut32 shell32 comdlg32 uuid UIAutomationCore windowsapp bcrypt
)

# Release hardening: no debug info in shipped binaries, ASLR/NX/CFG on.
if (MSVC)
    target_compile_options(Valhalla PRIVATE /GS /sdl /guard:cf)
    target_link_options(Valhalla PRIVATE /DEBUG:NONE /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /GUARD:CF /OPT:REF /OPT:ICF)
endif()

set_target_properties(Valhalla PROPERTIES WIN32_EXECUTABLE ON)

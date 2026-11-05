cmake_minimum_required(VERSION 3.21)
project(ValhallaSetup LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_AUTOMOC ON)

find_package(Qt6 6.5 REQUIRED COMPONENTS Widgets)
qt_standard_project_setup(REQUIRES 6.5)

qt_add_executable(ValhallaSetup
    src/main.cpp
    src/app.rc
)

target_compile_definitions(ValhallaSetup PRIVATE UNICODE _UNICODE NOMINMAX _CRT_SECURE_NO_WARNINGS)

target_link_libraries(ValhallaSetup PRIVATE
    Qt6::Widgets
    ole32 oleaut32 uuid shell32 user32
)

if (MSVC)
    target_compile_options(ValhallaSetup PRIVATE /GS /sdl /guard:cf)
    target_link_options(ValhallaSetup PRIVATE /DEBUG:NONE /DYNAMICBASE /NXCOMPAT /HIGHENTROPYVA /GUARD:CF /OPT:REF /OPT:ICF)
endif()

set_target_properties(ValhallaSetup PROPERTIES WIN32_EXECUTABLE ON)

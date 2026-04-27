cmake_minimum_required(VERSION 3.15)
project(libtess2 C)

if(NOT EXISTS ${CMAKE_SOURCE_DIR}/libtess2/Source)
    execute_process(
        COMMAND git clone https://github.com/Anaxarchus/libtess2.git
        WORKING_DIRECTORY ${CMAKE_SOURCE_DIR}
        RESULT_VARIABLE GIT_RESULT
    )
    if(NOT GIT_RESULT EQUAL 0)
        message(FATAL_ERROR "Failed to clone libtess2")
    endif()
endif()

set(SRC ${CMAKE_SOURCE_DIR}/libtess2/Source)
set(INC ${CMAKE_SOURCE_DIR}/libtess2/Include)

if(EMSCRIPTEN)
    set(PLATFORM_DIR "emscripten")
elseif(CMAKE_C_COMPILER_TARGET STREQUAL "wasm32")
    set(PLATFORM_DIR "wasm32")
elseif(WIN32)
    set(PLATFORM_DIR "windows")
elseif(APPLE)
    set(PLATFORM_DIR "macos")
else()
    set(PLATFORM_DIR "linux")
endif()

set(CMAKE_ARCHIVE_OUTPUT_DIRECTORY ${CMAKE_SOURCE_DIR}/../bin/${PLATFORM_DIR})

add_library(libtess2 STATIC
    ${SRC}/tess.c
    ${SRC}/mesh.c
    ${SRC}/sweep.c
    ${SRC}/geom.c
    ${SRC}/dict.c
    ${SRC}/priorityq.c
    ${SRC}/bucketalloc.c
)

target_compile_definitions(libtess2 PRIVATE TESS_USE_DOUBLE)
target_include_directories(libtess2 PUBLIC ${INC})
target_compile_options(libtess2 PRIVATE -O2)
cmake_minimum_required(VERSION 3.16)
project(cyxchat_android C)

set(CMAKE_C_STANDARD 11)

# ---- libsodium (from source) ----
set(SODIUM_SRC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../libsodium-src/src/libsodium")
set(SODIUM_INCLUDE_DIR "${SODIUM_SRC_DIR}/include")

# Collect all libsodium .c files
file(GLOB_RECURSE SODIUM_SOURCES "${SODIUM_SRC_DIR}/*.c")

# Remove files that don't compile on Android/ARM (x86 asm, etc.)
list(FILTER SODIUM_SOURCES EXCLUDE REGEX ".*aesni.*")
list(FILTER SODIUM_SOURCES EXCLUDE REGEX ".*avx.*")
list(FILTER SODIUM_SOURCES EXCLUDE REGEX ".*sse.*")
list(FILTER SODIUM_SOURCES EXCLUDE REGEX ".*ssse3.*")

add_library(sodium_static STATIC ${SODIUM_SOURCES})
target_include_directories(sodium_static PUBLIC
    "${SODIUM_INCLUDE_DIR}"
    "${SODIUM_INCLUDE_DIR}/sodium"
    "${SODIUM_SRC_DIR}/include/sodium"
)
target_compile_definitions(sodium_static PRIVATE
    CONFIGURED=1
    NATIVE_LITTLE_ENDIAN=1
    HAVE_INLINE_ASM=1
    HAVE_TI_MODE=1
    HAVE_WEAK_SYMBOLS=1
)

# ---- libcyxwiz (from source) ----
set(CYXWIZ_ROOT "${CMAKE_CURRENT_SOURCE_DIR}/../..")
set(CYXWIZ_INCLUDE_DIR "${CYXWIZ_ROOT}/include")
set(CYXWIZ_SRC_DIR "${CYXWIZ_ROOT}/src")

file(GLOB CYXWIZ_SOURCES
    "${CYXWIZ_SRC_DIR}/core/*.c"
    "${CYXWIZ_SRC_DIR}/crypto/*.c"
    "${CYXWIZ_SRC_DIR}/transport/transport.c"
    "${CYXWIZ_SRC_DIR}/transport/udp.c"
    "${CYXWIZ_SRC_DIR}/util/*.c"
)

add_library(cyxwiz_static STATIC ${CYXWIZ_SOURCES})
target_include_directories(cyxwiz_static PUBLIC "${CYXWIZ_INCLUDE_DIR}")
target_include_directories(cyxwiz_static PRIVATE "${SODIUM_INCLUDE_DIR}")
target_compile_definitions(cyxwiz_static PRIVATE CYXWIZ_HAS_CRYPTO)
target_link_libraries(cyxwiz_static PRIVATE sodium_static)

# ---- libcyxchat (shared library for FFI) ----
set(CYXCHAT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../lib")

file(GLOB CYXCHAT_SOURCES "${CYXCHAT_DIR}/src/*.c")

add_library(cyxchat SHARED ${CYXCHAT_SOURCES})
target_include_directories(cyxchat PUBLIC "${CYXCHAT_DIR}/include")
target_include_directories(cyxchat PRIVATE "${CYXWIZ_INCLUDE_DIR}" "${SODIUM_INCLUDE_DIR}")
target_compile_definitions(cyxchat PRIVATE CYXCHAT_EXPORTS CYXWIZ_HAS_CRYPTO)
target_link_libraries(cyxchat PRIVATE cyxwiz_static sodium_static log)

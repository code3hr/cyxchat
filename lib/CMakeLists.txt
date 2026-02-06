# CyxChat Library - CMake Build Configuration
cmake_minimum_required(VERSION 3.16)
project(cyxchat VERSION 0.1.0 LANGUAGES C)

# Options
option(CYXCHAT_BUILD_TESTS "Build tests" ON)
option(CYXCHAT_BUILD_SHARED "Build shared library" ON)
option(CYXCHAT_BUILD_STATIC "Build static library" ON)

# C Standard
set(CMAKE_C_STANDARD 11)
set(CMAKE_C_STANDARD_REQUIRED ON)

# Find dependencies
find_package(PkgConfig QUIET)

# Find libcyxwiz (parent project)
if(NOT TARGET cyxwiz)
    # Check for CYXWIZ_ROOT (from CI or command line)
    if(DEFINED CYXWIZ_ROOT AND EXISTS "${CYXWIZ_ROOT}/include/cyxwiz")
        set(CYXWIZ_INCLUDE_DIR "${CYXWIZ_ROOT}/include")
        # Use CYXWIZ_BUILD_DIR if specified (for cross-compilation), otherwise default to /build
        if(DEFINED CYXWIZ_BUILD_DIR AND EXISTS "${CYXWIZ_BUILD_DIR}")
            set(CYXWIZ_LIBRARY_DIR "${CYXWIZ_BUILD_DIR}")
        else()
            set(CYXWIZ_LIBRARY_DIR "${CYXWIZ_ROOT}/build")
        endif()
    # Try to find in parent directory
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../include/cyxwiz")
        set(CYXWIZ_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../include")
        if(DEFINED CYXWIZ_BUILD_DIR AND EXISTS "${CYXWIZ_BUILD_DIR}")
            set(CYXWIZ_LIBRARY_DIR "${CYXWIZ_BUILD_DIR}")
        else()
            set(CYXWIZ_LIBRARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build")
        endif()
    endif()

    if(CYXWIZ_LIBRARY_DIR)
        # Find the library
        if(WIN32)
            find_library(CYXWIZ_LIBRARY
                NAMES cyxwiz_static cyxwiz
                PATHS
                    "${CYXWIZ_LIBRARY_DIR}/Debug"
                    "${CYXWIZ_LIBRARY_DIR}/Release"
                    "${CYXWIZ_LIBRARY_DIR}"
            )
        elseif(CMAKE_CROSSCOMPILING)
            # When cross-compiling (Android/iOS), find_library doesn't work correctly
            # because NDK toolchain restricts search to sysroot. Set path directly.
            if(EXISTS "${CYXWIZ_LIBRARY_DIR}/libcyxwiz.a")
                set(CYXWIZ_LIBRARY "${CYXWIZ_LIBRARY_DIR}/libcyxwiz.a")
            elseif(EXISTS "${CYXWIZ_LIBRARY_DIR}/libcyxwiz_static.a")
                set(CYXWIZ_LIBRARY "${CYXWIZ_LIBRARY_DIR}/libcyxwiz_static.a")
            endif()
        else()
            find_library(CYXWIZ_LIBRARY
                NAMES cyxwiz libcyxwiz cyxwiz_static libcyxwiz_static
                PATHS "${CYXWIZ_LIBRARY_DIR}"
                NO_DEFAULT_PATH
            )
        endif()
    else()
        message(STATUS "Looking for installed cyxwiz...")
        find_path(CYXWIZ_INCLUDE_DIR cyxwiz/types.h
            PATHS /usr/local/include /usr/include
        )
        find_library(CYXWIZ_LIBRARY cyxwiz
            PATHS /usr/local/lib /usr/lib
        )
    endif()
endif()

message(STATUS "CYXWIZ_INCLUDE_DIR: ${CYXWIZ_INCLUDE_DIR}")
message(STATUS "CYXWIZ_LIBRARY_DIR: ${CYXWIZ_LIBRARY_DIR}")
message(STATUS "CYXWIZ_LIBRARY: ${CYXWIZ_LIBRARY}")
message(STATUS "CMAKE_CROSSCOMPILING: ${CMAKE_CROSSCOMPILING}")

# Find libsodium
# Try vcpkg's CMake config first (when using vcpkg toolchain)
find_package(unofficial-sodium CONFIG QUIET)
if(unofficial-sodium_FOUND)
    set(SODIUM_FOUND TRUE)
    set(SODIUM_TARGET unofficial-sodium::sodium)
    message(STATUS "Found libsodium via vcpkg CMake config")
endif()

# Skip pkg-config when cross-compiling (it finds host libraries, not target)
if(NOT SODIUM_FOUND AND PKG_CONFIG_FOUND AND NOT CMAKE_CROSSCOMPILING)
    pkg_check_modules(SODIUM libsodium)
endif()

# If pkg-config found sodium but paths are empty, consider it not found
if(SODIUM_FOUND AND (NOT SODIUM_INCLUDE_DIRS OR NOT SODIUM_LIBRARIES))
    set(SODIUM_FOUND FALSE)
endif()

# Find miniupnpc (for UPnP support - needed when linking with cyxwiz that has UPnP)
option(CYXCHAT_ENABLE_UPNP "Enable UPnP support (must match cyxwiz build)" ON)
if(CYXCHAT_ENABLE_UPNP)
    # Try vcpkg config first
    find_package(miniupnpc CONFIG QUIET)
    if(miniupnpc_FOUND)
        set(UPNP_FOUND TRUE)
        set(UPNP_TARGET miniupnpc::miniupnpc)
        message(STATUS "Found miniupnpc via vcpkg")
    endif()

    # Manual fallback
    if(NOT UPNP_FOUND)
        find_path(UPNP_INCLUDE_DIR miniupnpc/miniupnpc.h
            PATHS
                "$ENV{MINIUPNPC_ROOT}/include"
                "${CMAKE_CURRENT_SOURCE_DIR}/../vcpkg/packages/miniupnpc_x64-windows/include"
                "${CMAKE_CURRENT_SOURCE_DIR}/../vcpkg/installed/x64-windows/include"
                "C:/vcpkg/installed/x64-windows/include"
                "/usr/local/include"
                "/usr/include"
        )
        find_library(UPNP_LIBRARY
            NAMES miniupnpc
            PATHS
                "$ENV{MINIUPNPC_ROOT}/lib"
                "${CMAKE_CURRENT_SOURCE_DIR}/../vcpkg/packages/miniupnpc_x64-windows/lib"
                "${CMAKE_CURRENT_SOURCE_DIR}/../vcpkg/installed/x64-windows/lib"
                "C:/vcpkg/installed/x64-windows/lib"
                "/usr/local/lib"
                "/usr/lib"
        )
        if(UPNP_INCLUDE_DIR AND UPNP_LIBRARY)
            set(UPNP_FOUND TRUE)
            message(STATUS "Found miniupnpc: ${UPNP_LIBRARY}")
        endif()
    endif()

    if(NOT UPNP_FOUND)
        message(STATUS "miniupnpc not found - UPnP linking disabled")
    else()
        add_compile_definitions(CYXWIZ_HAS_UPNP=1)
        message(STATUS "UPnP support enabled (CYXWIZ_HAS_UPNP=1)")
    endif()
endif()

# Check if explicit paths were provided on command line
if(SODIUM_INCLUDE_DIR AND SODIUM_LIBRARY)
    set(SODIUM_FOUND TRUE)
    set(SODIUM_INCLUDE_DIRS ${SODIUM_INCLUDE_DIR})
    set(SODIUM_LIBRARIES ${SODIUM_LIBRARY})
    # Use include_directories globally
    include_directories(${SODIUM_INCLUDE_DIR})
    if(WIN32)
        # Also add via add_compile_options for MSVC
        add_compile_options("/I${SODIUM_INCLUDE_DIR}")
    endif()
    message(STATUS "Using explicitly provided libsodium paths")
elseif(NOT SODIUM_FOUND)
    # Check parent project's libsodium path first
    if(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../libsodium")
        set(SODIUM_ROOT_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../libsodium")
        find_path(SODIUM_INCLUDE_DIR sodium.h
            PATHS
                "${SODIUM_ROOT_DIR}/libsodium/include"
                "${SODIUM_ROOT_DIR}/include"
        )
        if(WIN32)
            find_library(SODIUM_LIBRARY
                NAMES libsodium sodium
                PATHS
                    "${SODIUM_ROOT_DIR}/libsodium/x64/Release/v143/static"
                    "${SODIUM_ROOT_DIR}/libsodium/x64/Debug/v143/static"
                    "${SODIUM_ROOT_DIR}/x64/Release/v143/static"
                    "${SODIUM_ROOT_DIR}/x64/Debug/v143/static"
            )
        endif()
    endif()

    # Fallback to standard paths
    if(NOT SODIUM_LIBRARY)
        find_path(SODIUM_INCLUDE_DIR sodium.h
            PATHS
                /usr/local/include
                /usr/include
                $ENV{SODIUM_ROOT}/include
                ${CMAKE_SOURCE_DIR}/deps/libsodium/include
        )
        find_library(SODIUM_LIBRARY sodium
            PATHS
                /usr/local/lib
                /usr/lib
                $ENV{SODIUM_ROOT}/lib
                ${CMAKE_SOURCE_DIR}/deps/libsodium/lib
        )
    endif()

    if(SODIUM_INCLUDE_DIR AND SODIUM_LIBRARY)
        set(SODIUM_FOUND TRUE)
        set(SODIUM_INCLUDE_DIRS ${SODIUM_INCLUDE_DIR})
        set(SODIUM_LIBRARIES ${SODIUM_LIBRARY})
    endif()
endif()

# Ensure SODIUM_INCLUDE_DIRS and SODIUM_LIBRARIES are set correctly
# Prefer explicit paths from command line over pkg-config results
if(SODIUM_INCLUDE_DIR)
    set(SODIUM_INCLUDE_DIRS ${SODIUM_INCLUDE_DIR})
endif()
if(SODIUM_LIBRARY)
    set(SODIUM_LIBRARIES ${SODIUM_LIBRARY})
    set(SODIUM_FOUND TRUE)
endif()

message(STATUS "SODIUM_INCLUDE_DIR: ${SODIUM_INCLUDE_DIR}")
message(STATUS "SODIUM_INCLUDE_DIRS: ${SODIUM_INCLUDE_DIRS}")
message(STATUS "SODIUM_LIBRARY: ${SODIUM_LIBRARY}")

# Source files
set(CYXCHAT_SOURCES
    src/cyxchat.c
    src/chat.c
    src/contact.c
    src/group.c
    src/file.c
    src/presence.c
    src/connection.c
    src/relay.c
    src/dns.c
    src/server_registry.c
)

# Header files
set(CYXCHAT_HEADERS
    include/cyxchat/cyxchat.h
    include/cyxchat/types.h
    include/cyxchat/chat.h
    include/cyxchat/contact.h
    include/cyxchat/group.h
    include/cyxchat/file.h
    include/cyxchat/presence.h
    include/cyxchat/connection.h
    include/cyxchat/relay.h
    include/cyxchat/dns.h
    include/cyxchat/server_registry.h
)

# Shared library
if(CYXCHAT_BUILD_SHARED)
    add_library(cyxchat SHARED ${CYXCHAT_SOURCES})
    target_include_directories(cyxchat
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
        PRIVATE
            ${CYXWIZ_INCLUDE_DIR}
            ${SODIUM_INCLUDE_DIRS} ${SODIUM_INCLUDE_DIR}
    )
    target_compile_definitions(cyxchat PRIVATE CYXCHAT_EXPORTS CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(cyxchat PRIVATE _CRT_SECURE_NO_WARNINGS SODIUM_STATIC)
    else()
        target_compile_options(cyxchat PRIVATE -Wall -Wextra -Werror)
    endif()

    if(SODIUM_TARGET)
        target_link_libraries(cyxchat PRIVATE ${SODIUM_TARGET})
    else()
        target_link_libraries(cyxchat PRIVATE ${SODIUM_LIBRARIES})
    endif()

    # Link cyxwiz if available
    if(TARGET cyxwiz)
        target_link_libraries(cyxchat PRIVATE cyxwiz)
    elseif(CYXWIZ_LIBRARY)
        target_link_libraries(cyxchat PRIVATE ${CYXWIZ_LIBRARY})
    endif()

    # Link miniupnpc if UPnP is enabled (needed for cyxwiz UPnP support)
    if(UPNP_FOUND)
        if(UPNP_TARGET)
            target_link_libraries(cyxchat PRIVATE ${UPNP_TARGET})
        else()
            target_link_libraries(cyxchat PRIVATE ${UPNP_LIBRARY})
        endif()
        if(WIN32)
            target_link_libraries(cyxchat PRIVATE iphlpapi)
        endif()
    endif()

    set_target_properties(cyxchat PROPERTIES
        VERSION ${PROJECT_VERSION}
        SOVERSION 0
        PUBLIC_HEADER "${CYXCHAT_HEADERS}"
    )
endif()

# Static library
if(CYXCHAT_BUILD_STATIC)
    add_library(cyxchat_static STATIC ${CYXCHAT_SOURCES})
    target_include_directories(cyxchat_static
        PUBLIC
            $<BUILD_INTERFACE:${CMAKE_CURRENT_SOURCE_DIR}/include>
            $<INSTALL_INTERFACE:include>
        PRIVATE
            ${CYXWIZ_INCLUDE_DIR}
            ${SODIUM_INCLUDE_DIRS} ${SODIUM_INCLUDE_DIR}
    )

    target_compile_definitions(cyxchat_static PRIVATE CYXCHAT_STATIC CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(cyxchat_static PRIVATE _CRT_SECURE_NO_WARNINGS SODIUM_STATIC)
    else()
        target_compile_options(cyxchat_static PRIVATE -Wall -Wextra -Werror)
    endif()

    # Link cyxwiz for static library
    if(TARGET cyxwiz_static)
        target_link_libraries(cyxchat_static PUBLIC cyxwiz_static)
    elseif(CYXWIZ_LIBRARY)
        target_link_libraries(cyxchat_static PUBLIC ${CYXWIZ_LIBRARY})
    endif()

    if(SODIUM_TARGET)
        target_link_libraries(cyxchat_static PUBLIC ${SODIUM_TARGET})
    elseif(SODIUM_LIBRARIES)
        target_link_libraries(cyxchat_static PUBLIC ${SODIUM_LIBRARIES})
    endif()

    # Link miniupnpc if UPnP is enabled
    if(UPNP_FOUND)
        if(UPNP_TARGET)
            target_link_libraries(cyxchat_static PUBLIC ${UPNP_TARGET})
        else()
            target_link_libraries(cyxchat_static PUBLIC ${UPNP_LIBRARY})
        endif()
        if(WIN32)
            target_link_libraries(cyxchat_static PUBLIC iphlpapi)
        endif()
    endif()

    set_target_properties(cyxchat_static PROPERTIES
        OUTPUT_NAME cyxchat_static
    )
endif()

# Tests
if(CYXCHAT_BUILD_TESTS)
    enable_testing()

    add_executable(test_cyxchat
        tests/test_main.c
        tests/test_chat.c
        tests/test_contact.c
        tests/test_group.c
        tests/test_dns.c
    )

    target_include_directories(test_cyxchat PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CYXWIZ_INCLUDE_DIR}
        ${SODIUM_INCLUDE_DIRS} ${SODIUM_INCLUDE_DIR}
    )
    target_compile_definitions(test_cyxchat PRIVATE CYXCHAT_STATIC CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(test_cyxchat PRIVATE _CRT_SECURE_NO_WARNINGS SODIUM_STATIC)
    endif()

    # Always link static for tests
    target_link_libraries(test_cyxchat PRIVATE cyxchat_static)
    if(CYXWIZ_LIBRARY)
        target_link_libraries(test_cyxchat PRIVATE ${CYXWIZ_LIBRARY})
    endif()
    if(SODIUM_TARGET)
        target_link_libraries(test_cyxchat PRIVATE ${SODIUM_TARGET})
    elseif(SODIUM_LIBRARIES)
        target_link_libraries(test_cyxchat PRIVATE ${SODIUM_LIBRARIES})
    endif()
    # Link miniupnpc if UPnP is enabled
    if(UPNP_FOUND)
        if(UPNP_TARGET)
            target_link_libraries(test_cyxchat PRIVATE ${UPNP_TARGET})
        else()
            target_link_libraries(test_cyxchat PRIVATE ${UPNP_LIBRARY})
        endif()
        if(WIN32)
            target_link_libraries(test_cyxchat PRIVATE iphlpapi)
        endif()
    endif()

    add_test(NAME test_cyxchat COMMAND test_cyxchat)
endif()

# Installation
include(GNUInstallDirs)

if(CYXCHAT_BUILD_SHARED)
    install(TARGETS cyxchat
        EXPORT cyxchatTargets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
        RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
        PUBLIC_HEADER DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}/cyxchat
    )
endif()

if(CYXCHAT_BUILD_STATIC)
    install(TARGETS cyxchat_static
        EXPORT cyxchatTargets
        LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
        ARCHIVE DESTINATION ${CMAKE_INSTALL_LIBDIR}
    )
endif()

install(DIRECTORY include/cyxchat
    DESTINATION ${CMAKE_INSTALL_INCLUDEDIR}
)

# CMake package config
install(EXPORT cyxchatTargets
    FILE cyxchatTargets.cmake
    NAMESPACE cyxchat::
    DESTINATION ${CMAKE_INSTALL_LIBDIR}/cmake/cyxchat
)

# Status message
message(STATUS "")
message(STATUS "=== CyxChat Configuration ===")
message(STATUS "Version:        ${PROJECT_VERSION}")
message(STATUS "Build shared:   ${CYXCHAT_BUILD_SHARED}")
message(STATUS "Build static:   ${CYXCHAT_BUILD_STATIC}")
message(STATUS "Build tests:    ${CYXCHAT_BUILD_TESTS}")
message(STATUS "libsodium:      ${SODIUM_FOUND}")
message(STATUS "")

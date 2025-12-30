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
        set(CYXWIZ_LIBRARY_DIR "${CYXWIZ_ROOT}/build")
    # Try to find in parent directory
    elseif(EXISTS "${CMAKE_CURRENT_SOURCE_DIR}/../../include/cyxwiz")
        set(CYXWIZ_INCLUDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../include")
        set(CYXWIZ_LIBRARY_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../../build")
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
        else()
            find_library(CYXWIZ_LIBRARY
                NAMES cyxwiz libcyxwiz cyxwiz_static
                PATHS "${CYXWIZ_LIBRARY_DIR}"
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
message(STATUS "CYXWIZ_LIBRARY: ${CYXWIZ_LIBRARY}")

# Find libsodium
if(PKG_CONFIG_FOUND)
    pkg_check_modules(SODIUM libsodium)
endif()

if(NOT SODIUM_FOUND)
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

message(STATUS "SODIUM_INCLUDE_DIR: ${SODIUM_INCLUDE_DIR}")
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
    src/mail.c
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
    include/cyxchat/mail.h
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
            ${SODIUM_INCLUDE_DIRS}
    )
    target_compile_definitions(cyxchat PRIVATE CYXCHAT_EXPORTS CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(cyxchat PRIVATE _CRT_SECURE_NO_WARNINGS SODIUM_STATIC)
    else()
        target_compile_options(cyxchat PRIVATE -Wall -Wextra -Werror)
    endif()

    target_link_libraries(cyxchat
        PRIVATE
            ${SODIUM_LIBRARIES}
    )

    # Link cyxwiz if available
    if(TARGET cyxwiz)
        target_link_libraries(cyxchat PRIVATE cyxwiz)
    elseif(CYXWIZ_LIBRARY)
        target_link_libraries(cyxchat PRIVATE ${CYXWIZ_LIBRARY})
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
            ${SODIUM_INCLUDE_DIRS}
    )

    target_compile_definitions(cyxchat_static PRIVATE CYXCHAT_STATIC CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(cyxchat_static PRIVATE _CRT_SECURE_NO_WARNINGS)
    else()
        target_compile_options(cyxchat_static PRIVATE -Wall -Wextra -Werror)
    endif()

    # Link cyxwiz for static library
    if(TARGET cyxwiz_static)
        target_link_libraries(cyxchat_static PUBLIC cyxwiz_static)
    elseif(CYXWIZ_LIBRARY)
        target_link_libraries(cyxchat_static PUBLIC ${CYXWIZ_LIBRARY})
    endif()

    if(SODIUM_LIBRARIES)
        target_link_libraries(cyxchat_static PUBLIC ${SODIUM_LIBRARIES})
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
    )

    target_include_directories(test_cyxchat PRIVATE
        ${CMAKE_CURRENT_SOURCE_DIR}/include
        ${CYXWIZ_INCLUDE_DIR}
        ${SODIUM_INCLUDE_DIRS}
    )
    target_compile_definitions(test_cyxchat PRIVATE CYXCHAT_STATIC CYXWIZ_HAS_CRYPTO)

    if(WIN32)
        target_compile_definitions(test_cyxchat PRIVATE _CRT_SECURE_NO_WARNINGS)
    endif()

    # Always link static for tests
    target_link_libraries(test_cyxchat PRIVATE cyxchat_static)
    if(CYXWIZ_LIBRARY)
        target_link_libraries(test_cyxchat PRIVATE ${CYXWIZ_LIBRARY})
    endif()
    if(SODIUM_LIBRARIES)
        target_link_libraries(test_cyxchat PRIVATE ${SODIUM_LIBRARIES})
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

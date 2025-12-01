cmake_minimum_required(VERSION 3.20)

# ------- project -------
set(PROJECT_NAME_VAR "Program")
set(EXECUTABLE_NAME_VAR "program")
project(${PROJECT_NAME_VAR} LANGUAGES C CXX ASM_NASM)

# ------- standards -------
set(CMAKE_C_STANDARD 11)
set(CMAKE_CXX_STANDARD 17)

# ------- output dir -------
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY ${CMAKE_BINARY_DIR}/bin)

set_property(GLOBAL PROPERTY USE_FOLDERS ON)

# ------- options -------
option(DEV_MODE "Do not ignore lib/ content in .gitignore" OFF)

# ------- configs & build type -------
if(CMAKE_CONFIGURATION_TYPES)
    message(STATUS "Generator: ${CMAKE_GENERATOR} (multi-config)")
    message(STATUS "Available configs: ${CMAKE_CONFIGURATION_TYPES}")
else()
    if(NOT CMAKE_BUILD_TYPE)
        set(CMAKE_BUILD_TYPE Debug CACHE STRING "Build type" FORCE)
    endif()

    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
        "Debug" "Release" "RelWithDebInfo" "MinSizeRel"
    )

    message(STATUS "Generator: ${CMAKE_GENERATOR} (single-config)")
    message(STATUS "CMAKE_BUILD_TYPE: ${CMAKE_BUILD_TYPE}")
endif()

set(LIB_DIR ${CMAKE_SOURCE_DIR}/lib)
set(SRC_DIR ${CMAKE_SOURCE_DIR}/src)
set(VIRTUAL_INC_DIR ${CMAKE_BINARY_DIR}/nasm_includes)
file(MAKE_DIRECTORY "${VIRTUAL_INC_DIR}")

# ------- dependency search -------
function(find_dependency_file dir result)
    set(allowed_variants
        dependencies.list
        DEPENDENCIES.list
        Dependencies.list
    )

    file(GLOB all_files "${dir}/*")
    set(match "")

    foreach(variant ${allowed_variants})
        foreach(f ${all_files})
            get_filename_component(name "${f}" NAME)

            if("${name}" STREQUAL "${variant}")
                if(NOT "${match}" STREQUAL "")
                    message(FATAL_ERROR "Multiple dependency files found in '${dir}': '${match}' and '${variant}'")
                endif()

                set(match "${variant}")
            endif()
        endforeach()
    endforeach()

    if("${match}" STREQUAL "")
        set(${result} "" PARENT_SCOPE)
    else()
        set(${result} "${dir}/${match}" PARENT_SCOPE)
    endif()
endfunction()

# ------- dependency parser -------
function(parse_dependency_file depfile out_deplist)
    if(NOT EXISTS "${depfile}")
        set(${out_deplist} "" PARENT_SCOPE)
        return()
    endif()

    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${depfile}")
    set(parsed "")

    file(READ "${depfile}" contents)
    string(REPLACE ";" "#" contents "${contents}")
    string(REPLACE "\n" ";" lines "${contents}")

    foreach(line IN LISTS lines)
        string(REGEX REPLACE "( |\\t|^)(#|//|--).*" "" line "${line}")
        string(STRIP "${line}" line)

        if(NOT line STREQUAL "" AND NOT line MATCHES "^\\[.*\\]$")
            list(APPEND parsed "${line}")
        endif()
    endforeach()

    set(${out_deplist} ${parsed} PARENT_SCOPE)
endfunction()

# ------- transitive dependency resolver -------
function(resolve_dependencies result out_configure_deps)
    set(visited "")
    set(to_visit ${ARGN})
    set(dep_files "")

    while(to_visit)
        list(POP_FRONT to_visit current)

        if(NOT "${current}" MATCHES "^[0-9A-Za-z_-]+$")
            message(FATAL_ERROR "Invalid dependency name: ${current}")
        endif()

        if(NOT IS_DIRECTORY "${LIB_DIR}/${current}")
            message(FATAL_ERROR "Dependency is missing: ${current}")
        endif()

        if(NOT current IN_LIST visited)
            list(APPEND visited ${current})
            find_dependency_file("${LIB_DIR}/${current}" depfile)

            if(depfile)
                parse_dependency_file("${depfile}" inner_list)
                list(APPEND dep_files "${depfile}")
                list(APPEND to_visit ${inner_list})
            endif()
        endif()
    endwhile()

    set(${result} ${visited} PARENT_SCOPE)
    set(${out_configure_deps} ${dep_files} PARENT_SCOPE)
endfunction()

# ------- parse project dependency files -------
set(ROOT_DEPS "")
find_dependency_file("${SRC_DIR}" root_depfile)

if(root_depfile)
    parse_dependency_file("${root_depfile}" deps)
    list(APPEND ROOT_DEPS ${deps})
endif()

# ------- resolve transitive dependencies -------
if(ROOT_DEPS)
    resolve_dependencies(FINAL_DEP_LIST CONFIGURE_DEP_FILES ${ROOT_DEPS})
else()
    set(FINAL_DEP_LIST "")
    set(CONFIGURE_DEP_FILES "")
endif()

list(LENGTH FINAL_DEP_LIST _dep_count)

if(_dep_count GREATER 0)
    string(JOIN ", " _deps_csv ${FINAL_DEP_LIST})
    message(STATUS "Active dependencies (${_dep_count}): ${_deps_csv}")
else()
    message(STATUS "Active dependencies (0)")
endif()

# ------- collect headers -------
set(LIB_IFACE_PATTERNS "*.inc" "*.h" "*.hpp" "*.h++" "*.txt")
set(LIB_IFACE_FILES "")

foreach(dep ${FINAL_DEP_LIST})
    foreach(_pat ${LIB_IFACE_PATTERNS})
        file(GLOB_RECURSE _files CONFIGURE_DEPENDS "${LIB_DIR}/${dep}/${_pat}")
        list(APPEND LIB_IFACE_FILES ${_files})
    endforeach()

    if(EXISTS "${LIB_DIR}/${dep}/all")
        list(APPEND LIB_IFACE_FILES "${LIB_DIR}/${dep}/all")
    endif()
endforeach()

list(LENGTH LIB_IFACE_FILES _iface_count)
message(STATUS "Tracking ${_iface_count} interface files from lib/ for mirroring")

# ------- manifests for build-time tools -------
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/final_deps.txt"      CONTENT "$<JOIN:${FINAL_DEP_LIST},\n>")
file(GENERATE OUTPUT "${CMAKE_BINARY_DIR}/lib_iface_files.txt" CONTENT "$<JOIN:${LIB_IFACE_FILES},\n>")

# ------- mirroring target -------
set(MIRROR_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/MirrorIncludes.cmake")
set(MIRROR_STAMP  "${CMAKE_BINARY_DIR}/mirror_includes.stamp")

add_custom_command(
    OUTPUT "${MIRROR_STAMP}"
    COMMAND "${CMAKE_COMMAND}"
        -DDEPS_FILE:FILEPATH=${CMAKE_BINARY_DIR}/final_deps.txt
        -DLIB_DIR:PATH=${LIB_DIR}
        -DOUT_DIR:PATH=${VIRTUAL_INC_DIR}
        -P "${MIRROR_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}"
        -E touch "${MIRROR_STAMP}"
    DEPENDS ${CONFIGURE_DEP_FILES} ${LIB_IFACE_FILES}
    VERBATIM
)

add_custom_target(sync_nasm_includes DEPENDS "${MIRROR_STAMP}")

# ------- generate lib/.gitignore -------
set(GI_SCRIPT "${CMAKE_SOURCE_DIR}/cmake/GenGitignore.cmake")
set(GI_PATH   "${LIB_DIR}/.gitignore")
set(GI_STAMP  "${CMAKE_BINARY_DIR}/gitignore.stamp")

file(GLOB DEV_MARKER_MATCH CONFIGURE_DEPENDS "${LIB_DIR}/.dev-mode")

if(DEV_MODE OR DEV_MARKER_MATCH)
  set(DEV_ACTIVE ON)
else()
  set(DEV_ACTIVE OFF)
endif()

string(TIMESTAMP _ts "%s")
file(WRITE "${CMAKE_BINARY_DIR}/cmake_regen.stamp" "${_ts}\n")

add_custom_command(
    OUTPUT "${GI_PATH}" "${GI_STAMP}"
    COMMAND "${CMAKE_COMMAND}"
        -DDEPS_FILE:FILEPATH=${CMAKE_BINARY_DIR}/final_deps.txt
        -DOUT:FILEPATH=${GI_PATH}
        -DLIB_DIR:PATH=${LIB_DIR}
        -DDEV_ACTIVE:BOOL=${DEV_ACTIVE}
        -DREPO_ROOT:PATH=${CMAKE_SOURCE_DIR}
        -P "${GI_SCRIPT}"
    COMMAND "${CMAKE_COMMAND}" -E touch "${GI_STAMP}"
    DEPENDS ${CONFIGURE_DEP_FILES}
            "${CMAKE_BINARY_DIR}/final_deps.txt"
            "${CMAKE_BINARY_DIR}/cmake_regen.stamp"
    VERBATIM
)

add_custom_target(update_gitignore DEPENDS "${GI_STAMP}")

# ------- add include paths -------
set(NASM_INCLUDE_DIRS ${SRC_DIR} ${SRC_DIR}/include ${VIRTUAL_INC_DIR})
include_directories(${SRC_DIR})

# ------- collect source files -------
file(GLOB_RECURSE C_SOURCES   CONFIGURE_DEPENDS "${SRC_DIR}/*.c")
file(GLOB_RECURSE CPP_SOURCES CONFIGURE_DEPENDS "${SRC_DIR}/*.cpp")
file(GLOB_RECURSE ASM_SOURCES CONFIGURE_DEPENDS "${SRC_DIR}/*.nasm")

foreach(dep ${FINAL_DEP_LIST})
    file(GLOB_RECURSE LIB_C   CONFIGURE_DEPENDS "${LIB_DIR}/${dep}/*.c")
    file(GLOB_RECURSE LIB_CPP CONFIGURE_DEPENDS "${LIB_DIR}/${dep}/*.cpp")
    file(GLOB_RECURSE LIB_ASM CONFIGURE_DEPENDS "${LIB_DIR}/${dep}/*.nasm")

    list(APPEND C_SOURCES   ${LIB_C})
    list(APPEND CPP_SOURCES ${LIB_CPP})
    list(APPEND ASM_SOURCES ${LIB_ASM})
endforeach()

list(LENGTH C_SOURCES   _c_count)
list(LENGTH CPP_SOURCES _cpp_count)
list(LENGTH ASM_SOURCES _asm_count)
message(STATUS "Sources — NASM: ${_asm_count}, C: ${_c_count}, C++: ${_cpp_count}")

# ------- NASM include graph -------
function(nasm_resolve_path from_path inc out_abs)
    if(IS_ABSOLUTE "${inc}" AND EXISTS "${inc}")
        file(TO_CMAKE_PATH "${inc}" _abs)
        set(${out_abs} "${_abs}" PARENT_SCOPE)
        return()
    endif()

    get_filename_component(_from_dir "${from_path}" DIRECTORY)

    if(EXISTS "${_from_dir}/${inc}")
        file(TO_CMAKE_PATH "${_from_dir}/${inc}" _abs)
        set(${out_abs} "${_abs}" PARENT_SCOPE)
        return()
    endif()

    foreach(base ${NASM_INCLUDE_DIRS})
        if(EXISTS "${base}/${inc}")
            file(TO_CMAKE_PATH "${base}/${inc}" _abs)
            set(${out_abs} "${_abs}" PARENT_SCOPE)
            return()
        endif()
    endforeach()

    set(${out_abs} "" PARENT_SCOPE)
endfunction()

function(nasm_collect_includes src out_list)
    set(_stack "${src}")
    set(_seen "")
    set(_deps "")

    while(_stack)
        list(POP_BACK _stack _cur)
        if(_cur IN_LIST _seen)
            continue()
        endif()

        list(APPEND _seen "${_cur}")
        if(NOT EXISTS "${_cur}")
            continue()
        endif()

        file(STRINGS "${_cur}" _lines)
        foreach(_ln IN LISTS _lines)
            string(REGEX REPLACE ";.*$" "" _ln "${_ln}")
            string(STRIP "${_ln}" _ln)

            if(_ln MATCHES "^[ \t]*%include[ \t]+[\"']([^\"']+)[\"']")
                set(_inc "${CMAKE_MATCH_1}")
                file(TO_CMAKE_PATH "${_inc}" _inc_norm)
                nasm_resolve_path("${_cur}" "${_inc_norm}" _abs)

                if(_abs)
                    list(APPEND _deps "${_abs}")
                    list(APPEND _stack "${_abs}")
                endif()
            endif()
        endforeach()
    endwhile()

    list(REMOVE_DUPLICATES _deps)
    set(${out_list} "${_deps}" PARENT_SCOPE)
endfunction()

foreach(src ${ASM_SOURCES})
    set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${src}")
endforeach()

set(_total_nasm_edges 0)
foreach(src ${ASM_SOURCES})
    nasm_collect_includes("${src}" _deps)

    if(_deps)
        foreach(h ${_deps})
            set_property(DIRECTORY APPEND PROPERTY CMAKE_CONFIGURE_DEPENDS "${h}")
        endforeach()

        set_source_files_properties(${src} PROPERTIES OBJECT_DEPENDS "${_deps}")
        list(LENGTH _deps _k)
        math(EXPR _total_nasm_edges "${_total_nasm_edges} + ${_k}")
    endif()
endforeach()
message(STATUS "NASM include edges tracked: ${_total_nasm_edges}")

# ------- add executable -------
add_executable(${EXECUTABLE_NAME_VAR} ${C_SOURCES} ${CPP_SOURCES} ${ASM_SOURCES})
add_dependencies(${EXECUTABLE_NAME_VAR} sync_nasm_includes update_gitignore)

if(CMAKE_CONFIGURATION_TYPES)
    set_target_properties(${EXECUTABLE_NAME_VAR} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY_DEBUG          "${CMAKE_BINARY_DIR}/bin/Debug"
        RUNTIME_OUTPUT_DIRECTORY_RELEASE        "${CMAKE_BINARY_DIR}/bin/Release"
        RUNTIME_OUTPUT_DIRECTORY_RELWITHDEBINFO "${CMAKE_BINARY_DIR}/bin/RelWithDebInfo"
        RUNTIME_OUTPUT_DIRECTORY_MINSIZEREL     "${CMAKE_BINARY_DIR}/bin/MinSizeRel"
    )
else()
    set_target_properties(${EXECUTABLE_NAME_VAR} PROPERTIES
        RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin"
    )
endif()

if(NOT MSVC)
  target_link_libraries(${EXECUTABLE_NAME_VAR} PRIVATE m)
endif()

if(WIN32)
    set(NASM_FORMAT win64)
    target_compile_definitions(${EXECUTABLE_NAME_VAR} PRIVATE WINDOWS)
else()
    set(NASM_FORMAT elf64)
    target_compile_definitions(${EXECUTABLE_NAME_VAR} PRIVATE LINUX)

    include(CheckPIESupported)
    check_pie_supported()
    set(CMAKE_POSITION_INDEPENDENT_CODE ON)
    target_compile_definitions(${EXECUTABLE_NAME_VAR} PRIVATE CLIB_PIC_CALL)

    set(CMAKE_EXE_LINKER_FLAGS "${CMAKE_EXE_LINKER_FLAGS} -z noexecstack")
endif()

# ------- optimizations & per-config flags -------
if(MSVC)
    target_compile_definitions(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<CONFIG:Debug>:DEBUG>
        $<$<CONFIG:Release>:NDEBUG>
    )

    target_compile_options(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<AND:$<CONFIG:Debug>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:/Od>
        $<$<AND:$<CONFIG:Release>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:/O2>
        $<$<AND:$<CONFIG:Release>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:/Gy>
    )

    target_link_options(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<CONFIG:Release>:/OPT:REF>
        $<$<CONFIG:Release>:/OPT:ICF>
        $<$<CONFIG:Release>:/INCREMENTAL:NO>
        $<$<CONFIG:RelWithDebInfo>:/OPT:REF>
        $<$<CONFIG:RelWithDebInfo>:/OPT:ICF>
        $<$<CONFIG:RelWithDebInfo>:/INCREMENTAL:NO>
        $<$<CONFIG:MinSizeRel>:/OPT:REF>
        $<$<CONFIG:MinSizeRel>:/OPT:ICF>
        $<$<CONFIG:MinSizeRel>:/INCREMENTAL:NO>
    )
elseif(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_definitions(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<CONFIG:Debug>:DEBUG>
        $<$<CONFIG:Release>:NDEBUG>
    )

    target_compile_options(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<AND:$<CONFIG:Debug>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:-O0>
        $<$<AND:$<CONFIG:Debug>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:-g>
        $<$<AND:$<CONFIG:Release>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:-O3>
        $<$<AND:$<CONFIG:Release>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:-ffunction-sections>
        $<$<AND:$<CONFIG:Release>,$<OR:$<COMPILE_LANGUAGE:C>,$<COMPILE_LANGUAGE:CXX>>>:-fdata-sections>
    )

    target_link_options(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<CONFIG:Release>:-Wl,--gc-sections,-s>
    )
endif()

# ------- nasm assembler flags -------
foreach(src ${ASM_SOURCES})
    set_source_files_properties(${src} PROPERTIES
        LANGUAGE ASM_NASM
        NASM_OBJ_FORMAT ${NASM_FORMAT})
endforeach()

foreach(path ${NASM_INCLUDE_DIRS})
    target_compile_options(${EXECUTABLE_NAME_VAR} PRIVATE
        $<$<COMPILE_LANGUAGE:ASM_NASM>:-I${path}>)
endforeach()

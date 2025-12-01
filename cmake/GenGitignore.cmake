# Inputs:
#   - DEPS_FILE  : path with one active dependency name per line
#   - OUT        : destination file path to lib/.gitignore
#   - LIB_DIR    : absolute path to lib/
#   - DEV_ACTIVE : optional bool - ON/OFF effective dev mode
#   - REPO_ROOT  : optional path to repo root for git prune/add

if(NOT DEFINED DEPS_FILE OR NOT DEFINED OUT OR NOT DEFINED LIB_DIR)
        message(FATAL_ERROR "GenGitignore.cmake: missing DEPS_FILE/OUT/LIB_DIR")
endif()

foreach(_k DEPS_FILE OUT LIB_DIR REPO_ROOT)
    if(DEFINED ${_k})
        string(REGEX REPLACE "^\"|\"$" "" ${_k} "${${_k}}")
    endif()
endforeach()

if(DEFINED DEV_ACTIVE AND DEV_ACTIVE)
    set(_dev TRUE)
else()
    set(_dev FALSE)
endif()

file(MAKE_DIRECTORY "${LIB_DIR}")

function(_write_if_changed path content)
    if(EXISTS "${path}")
        file(READ "${path}" _old)
        if(_old STREQUAL content)
            set(_changed FALSE PARENT_SCOPE)
            return()
        endif()
    endif()
    file(WRITE "${path}" "${content}")
    set(_changed TRUE PARENT_SCOPE)
endfunction()

if(_dev)
    set(_desired ".dev-mode\n")
else()
    file(READ "${DEPS_FILE}" _deps_raw)
    string(REGEX REPLACE "[\r\n]+" ";" DEPS "${_deps_raw}")
    list(REMOVE_DUPLICATES DEPS)
    list(SORT DEPS)

    set(_desired "*\n")
    string(APPEND _desired "!*/\n")
    string(APPEND _desired "!.gitignore\n")
    string(APPEND _desired ".dev-mode\n")
    foreach(dep IN LISTS DEPS)
        if(NOT dep STREQUAL "")
            string(APPEND _desired "!${dep}/**\n")
        endif()
    endforeach()
endif()

_write_if_changed("${OUT}" "${_desired}")
if(_changed)
    if(_dev)
        message(STATUS "lib/.gitignore set to dev mode (not ignoring lib/)")
    else()
        message(STATUS "lib/.gitignore updated")
    endif()
else()
    if(_dev)
        message(STATUS "lib/.gitignore unchanged (dev mode)")
    else()
        message(STATUS "lib/.gitignore unchanged")
    endif()
endif()

if(NOT _dev AND DEFINED REPO_ROOT)
    find_program(GIT_EXECUTABLE git)
    if(GIT_EXECUTABLE)
        execute_process(
            COMMAND "${GIT_EXECUTABLE}" rev-parse --is-inside-work-tree
            WORKING_DIRECTORY "${REPO_ROOT}"
            OUTPUT_VARIABLE _in_repo
            OUTPUT_STRIP_TRAILING_WHITESPACE
            ERROR_QUIET
        )
        if(_in_repo STREQUAL "true")
            set(_allow ${DEPS})

            file(GLOB _entries RELATIVE "${LIB_DIR}" "${LIB_DIR}/*")
            foreach(_d IN LISTS _entries)
                if(IS_DIRECTORY "${LIB_DIR}/${_d}")
                    list(FIND _allow "${_d}" _idx)
                    if(_idx EQUAL -1)
                        execute_process(
                            COMMAND "${GIT_EXECUTABLE}" -C "${REPO_ROOT}" rm -r --cached --ignore-unmatch "lib/${_d}"
                            OUTPUT_QUIET ERROR_QUIET
                        )
                    endif()
                endif()
            endforeach()

            execute_process(
                COMMAND "${GIT_EXECUTABLE}" -C "${REPO_ROOT}" add -A -- lib
                OUTPUT_QUIET ERROR_QUIET
            )
            message(STATUS "git index for lib/ pruned & refreshed")
        endif()
    endif()
endif()

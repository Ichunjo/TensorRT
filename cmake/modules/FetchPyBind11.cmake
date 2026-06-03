# SPDX-License-Identifier: Apache-2.0

if(NOT TARGET pybind11::module)
    message(STATUS "Fetching pybind11 from GitHub...")
    include(FetchContent)
    FetchContent_Declare(
        pybind11
        GIT_REPOSITORY https://github.com/pybind/pybind11.git
        GIT_TAG        v3.0.4
    )
    # Disable building tests for pybind11 to save build time
    set(PYBIND11_TEST OFF CACHE BOOL "" FORCE)
    
    FetchContent_MakeAvailable(pybind11)
endif()

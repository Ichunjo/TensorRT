if(NOT TARGET pybind11::module)
    message(STATUS "Using local pybind11 from ${CMAKE_SOURCE_DIR}/parsers/onnx/third_party/onnx/third_party/pybind11")
    add_subdirectory(
        "${CMAKE_SOURCE_DIR}/parsers/onnx/third_party/onnx/third_party/pybind11"
        "${CMAKE_CURRENT_BINARY_DIR}/pybind11_build"
        EXCLUDE_FROM_ALL
    )
endif()

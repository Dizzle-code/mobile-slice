cmake_minimum_required(VERSION 3.22)

# Added as a subdirectory of the engine's src/CMakeLists.txt by engine/build-android.sh
# (ORCAXR_SLICE_PROBE_DIR), engine/build-windows.ps1 or engine/build-macos.sh.
if (NOT TARGET libslic3r)
    message(FATAL_ERROR "Configure slicer_cli through engine/build-android.sh, build-windows.ps1 or build-macos.sh")
endif()

add_executable(slicer_cli slicer_cli.cpp nanosvg_impl.cpp)
target_compile_features(slicer_cli PRIVATE cxx_std_17)
target_include_directories(slicer_cli PRIVATE "${CMAKE_SOURCE_DIR}/src" "${CMAKE_SOURCE_DIR}/deps_src")
target_link_libraries(slicer_cli PRIVATE libslic3r boost_libs nlohmann_json)
# libslic3r uses OpenSSL's MD5; on the desktop only the GUI target links it.
if (NOT ANDROID AND TARGET OpenSSL::Crypto)
    target_link_libraries(slicer_cli PRIVATE OpenSSL::Crypto)
endif()
if (WIN32)
    target_sources(slicer_cli PRIVATE slicer_cli.manifest)
    target_link_libraries(slicer_cli PRIVATE psapi bcrypt crypt32 ws2_32)
endif()

# cmake/coremark.cmake
#
# Defines the `coremark` STATIC library containing the upstream CoreMark
# benchmark sources. No porting layer is included; the consuming project is
# responsible for providing one.
#
# This file is designed to be self-contained: it can be consumed either by
# the accompanying root CMakeLists.txt (via add_subdirectory / FetchContent)
# or directly via include():
#
#   include(path/to/coremark/cmake/coremark.cmake)
#
# ---------------------------------------------------------------------------
# Consumer responsibilities
# ---------------------------------------------------------------------------
#
# 1. Create an INTERFACE (or OBJECT/STATIC) library that:
#      - Provides `core_portme.c` as a source
#      - Exposes the directory containing `core_portme.h` as an
#        INTERFACE include directory
#
#    Example:
#      add_library(my_portme STATIC core_portme.c)
#      target_include_directories(my_portme PUBLIC ${CMAKE_CURRENT_SOURCE_DIR})
#
# 2. Inject that target into coremark so its sources can find core_portme.h,
#    the porting symbols are available at link time, and both targets receive
#    the selected run configuration:
#
#      coremark_link_port(my_portme)
#
# 3. Select the run type while configuring CMake (default: PERFORMANCE):
#
#      cmake -DCOREMARK_RUN_TYPE=VALIDATION ...
#
#    Supported values are PERFORMANCE and VALIDATION. The wrapper defines
#    exactly one of PERFORMANCE_RUN or VALIDATION_RUN for both the benchmark
#    sources and the porting layer.
#
# 4. Put only platform-specific configuration on the port target. Standard
#    benchmark settings such as data size, iterations, execution context, seed
#    method, memory method, and embedded entry-point shape are owned by this
#    wrapper so every baseline uses the same values:
#
#      target_compile_definitions(my_portme PUBLIC
#          HAS_FLOAT=1
#          HAS_STDIO=1
#          HAS_PRINTF=1
#          FLAGS_STR=\"\"
#          MEM_LOCATION=\"Internal SRAM stack\"
#      )
#
# 5. Link your application against coremark:
#
#      target_link_libraries(my_app PRIVATE coremark)
#
# ---------------------------------------------------------------------------

# Guard against multiple inclusion (e.g. two consumers in the same build tree)
if(TARGET coremark)
    return()
endif()

# Locate the repository root relative to this file's directory (cmake/)
get_filename_component(_COREMARK_ROOT "${CMAKE_CURRENT_LIST_DIR}/.." ABSOLUTE)

# Select one standard CoreMark seed set for this build. A cache variable keeps
# the choice visible to presets, GUIs, and command-line reconfiguration.
set(COREMARK_RUN_TYPE "PERFORMANCE" CACHE STRING
    "CoreMark run type: PERFORMANCE or VALIDATION")
set_property(CACHE COREMARK_RUN_TYPE PROPERTY STRINGS PERFORMANCE VALIDATION)

string(TOUPPER "${COREMARK_RUN_TYPE}" _COREMARK_RUN_TYPE_NORMALIZED)
if(NOT _COREMARK_RUN_TYPE_NORMALIZED STREQUAL "PERFORMANCE" AND
   NOT _COREMARK_RUN_TYPE_NORMALIZED STREQUAL "VALIDATION")
    message(FATAL_ERROR
        "Invalid COREMARK_RUN_TYPE='${COREMARK_RUN_TYPE}'. "
        "Expected PERFORMANCE or VALIDATION.")
endif()

# Store the normalized value so subsequent CMake runs and tooling display the
# effective configuration rather than a differently-cased user input.
set(COREMARK_RUN_TYPE "${_COREMARK_RUN_TYPE_NORMALIZED}" CACHE STRING
    "CoreMark run type: PERFORMANCE or VALIDATION" FORCE)
set_property(CACHE COREMARK_RUN_TYPE PROPERTY STRINGS PERFORMANCE VALIDATION)

add_library(coremark_run_config INTERFACE)
add_library(CoreMark::RunConfig ALIAS coremark_run_config)

# Standard configuration shared by every MCU baseline. Keep these values here
# rather than in an individual core_portme.h so benchmark projects cannot drift
# silently from one another.
target_compile_definitions(coremark_run_config INTERFACE
    TOTAL_DATA_SIZE=2000
    ITERATIONS=0
    MULTITHREAD=1
    MAIN_HAS_NOARGC=1
    MAIN_HAS_NORETURN=0
    SEED_METHOD=SEED_VOLATILE
    MEM_METHOD=MEM_STACK
)

if(COREMARK_RUN_TYPE STREQUAL "PERFORMANCE")
    target_compile_definitions(coremark_run_config INTERFACE PERFORMANCE_RUN=1)
else()
    target_compile_definitions(coremark_run_config INTERFACE VALIDATION_RUN=1)
endif()

message(STATUS "CoreMark run type: ${COREMARK_RUN_TYPE}")

add_library(coremark STATIC
    "${_COREMARK_ROOT}/core_list_join.c"
    "${_COREMARK_ROOT}/core_main.c"
    "${_COREMARK_ROOT}/core_matrix.c"
    "${_COREMARK_ROOT}/core_state.c"
    "${_COREMARK_ROOT}/core_util.c"
)

# Expose coremark.h to both the library itself and its consumers.
# core_portme.h (included by coremark.h) must be reachable via the portme
# target that the consumer injects (see step 2 above).
target_include_directories(coremark PUBLIC
    "${_COREMARK_ROOT}"
)

# Embedded baselines provide their own application main(). Rename CoreMark's
# entry point consistently so consumers only need to call coremark_run().
target_compile_definitions(coremark PRIVATE main=coremark_run)

# The benchmark sources and port must use the same run definition. The
# coremark_link_port() helper below attaches this configuration to the port.
target_link_libraries(coremark PUBLIC coremark_run_config)

function(coremark_link_port port_target)
    if(NOT TARGET "${port_target}")
        message(FATAL_ERROR
            "coremark_link_port(): target '${port_target}' does not exist")
    endif()

    target_link_libraries("${port_target}" PUBLIC coremark_run_config)
    target_link_libraries(coremark PUBLIC "${port_target}")
endfunction()

unset(_COREMARK_ROOT)
unset(_COREMARK_RUN_TYPE_NORMALIZED)

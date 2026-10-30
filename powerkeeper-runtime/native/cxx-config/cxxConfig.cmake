# Standalone NDK adapter for LSPlant's mandatory Prefab target.
# Never replace Android NDK's actual libc++ or hide missing C++ symbols.
if(NOT TARGET cxx::cxx)
  add_library(cxx::cxx INTERFACE IMPORTED)
endif()

// libslic3r's SVG import expects the nanosvg implementation, which upstream only compiles into the GUI.
#include <cstdio>
#include <cstring>
#include <cmath>
#include <cstdlib>
#define NANOSVG_IMPLEMENTATION
#include "nanosvg/nanosvg.h"

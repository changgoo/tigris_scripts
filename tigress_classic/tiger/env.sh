# Machine environment for TIGRESS-classic builds and jobs on tiger.
#
# The toolchains, module stacks and complete compiler flags are those benchmarked for
# TIGRESS-NCR (../../tigress_ncr/tiger/env.sh, README.md there); the same code base and
# build options apply here, so this file reuses them instead of keeping a copy that could
# drift. DEFAULT_TOOLCHAIN and FLAGS_* can be overridden below once tigress_classic has
# its own benchmark.
#
#   source env.sh
#   load_toolchain <toolchain>   # loads modules, sets CXX_PRESET and TC_CXXFLAGS

source "$(dirname "${BASH_SOURCE[0]}")/../../tigress_ncr/tiger/env.sh"

# Machine environment for NASA HECC Athena, Turin nodes (PBS model=tur_ath)
#   2x AMD EPYC 9745 (Turin dense, Zen 5c), 256 cores/node, 2 NUMA domains (1 per socket),
#   16 CCDs x 16 cores (32 MB L3 each), HPE Slingshot (cxi), HPE Cray PE 25.09.
#   Login nodes (athfe*) have the same CPU, so builds on the login node target the right arch.
#
# Machine-env contract (see ../bench/BENCHMARK_SPEC.md and ../bench/env_template.sh), with
# PBS instead of Slurm: the PBS_* variables below replace SLURM_*, and the benchmark runs
# go through bench/pbs_submit.sh, which bundles several runs into one PBS job.
#
#   source env.sh
#   load_toolchain <toolchain>   # loads modules, sets CXX_PRESET, TC_CXXFLAGS, MPI_CXX
#
# Toolchains: all use cray-mpich (OFI/Slingshot), cray-hdf5-parallel 1.14.3.7 and
# cray-fftw 3.3.10.11 (x86_turin). There is no Open MPI, and no parallel HDF5 for Intel MPI.
#   gcc        : PrgEnv-gnu   GCC 14.2          + cray-mpich 8.1.33
#   aocc       : PrgEnv-aocc  AOCC 5.0 (clang 17) + cray-mpich 8.1.33
#   cce        : PrgEnv-cray  CCE 20 (clang 20)   + cray-mpich 8.1.33
#   icpx       : PrgEnv-intel oneAPI 2025.3 icpx  + cray-mpich 8.1.33
#   gcc-mpich9 : PrgEnv-gnu   GCC 14.2          + cray-mpich 9.0.1
# gcc is the default: fastest in the fresh-start matrix (2026-10-20, production-diagnostics
# 23071491f, 512 ranks on 2 nodes, 3 repeats; MHD/CRMHD s/cycle): gcc 0.436/0.433,
# gcc-mpich9 0.433/0.433 (tie; gcc needs no module swap), aocc 0.473/0.464,
# icpx 0.465/0.510. CCE is REJECTED: it miscompiles (MHD dt off from cycle 10, CRMHD
# 35-39 history columns off) and is 3-6x slower, all in NCR photochemistry.
#
# Notes
# - The compiler is the Cray wrapper CC (MPI_CXX), not mpicxx: CC adds the include and
#   link paths of cray-mpich, cray-hdf5-parallel and cray-fftw. build_tigress.sh writes
#   MPI_CXX over configure.py's "CXX := mpicxx". CC also prepends its own -march for
#   craype-x86-turin (znver4 for GCC, core-avx2 -mtune=core-avx2 for icpx); the -march in
#   TC_CXXFLAGS comes later and wins, and icpx gets -mtune=znver5 explicitly.
# - ~/.bashrc activates ~/myenv, a Python venv with a pip-installed MPICH whose mpiexec and
#   mpicxx shadow the Cray ones. load_toolchain drops the venv's bin from PATH, and
#   MPI_LAUNCH is the PALS mpiexec by absolute path.
# - Environment Modules 3.2: change a version with "module swap", and never run module
#   commands inside $(...) or a pipe (they would run in a subshell).
# - Self-gravity (FFT, grav_bc=disk) is 3.5x slower than on stellarai-amd even at the
#   same layout (4 nodes x 96 ranks: grav 0.069 vs 0.020 s/cycle). It is not the FFT
#   library (MKL's FFTW3 interface instead of cray-fftw: same time, 2026-10-20) and none
#   of MPICH_ALLTOALLV_THROTTLE=32, MPICH_SMP_SINGLE_COPY_MODE=CMA, MPICH_OFI_NIC_POLICY=NUMA,
#   FI_CXI_RX_MATCH_MODE=hybrid, MPICH_SHARED_MEM_COLL_OPT=0 changes it: the fftMPI
#   remaps (point-to-point + Alltoallv) are slow on this network. Open; needs a profile.
#   For CRMHD, gravity/solve_grav_hyperbolic_dt=true removes most of it (22-36% faster).
# - Non-default cray-* versions are found at run time only through CRAY_LD_LIBRARY_PATH,
#   which load_toolchain prepends to LD_LIBRARY_PATH.

# --- machine description ------------------------------------------------------------
MACHINE_CPU="2x AMD EPYC 9745 (Zen 5c)"
CORES_PER_NODE=256
PBS_QUEUE=devel               # devel: 1 queued + 1 running job per user, 2 h, 256 nodes
PBS_MODEL=tur_ath
PBS_GROUP=s2800               # allocation (acct_ytd)
SBU_RATE=12.19                # SBU per node-hour on tur_ath
SCRATCH_BASE=/nobackup/$USER
MAKE_JOBS=16
PALS_MPIEXEC=/opt/cray/pals/1.7/bin/mpiexec
MPI_LAUNCH=$PALS_MPIEXEC      # the bench job adds --hosts, -n, --ppn and --cpu-bind "$(cpu_bind <ppn>)"

# cpu_bind <ranks per node>: PALS --cpu-bind value. A full node binds one rank per core;
# fewer ranks are spread evenly over the 16 CCDs (e.g. 192 = the first 12 cores of each
# CCD) so every L3 and memory channel gets the same load. CPUs 0-255 are the physical
# cores whether SMT is on or off.
cpu_bind() {
    local ppn=$1 per=$(( $1 / 16 ))
    if (( ppn >= CORES_PER_NODE )); then echo core; return; fi
    echo "list:$(for c in $(seq 0 $((CORES_PER_NODE - 1))); do (( c % 16 < per )) && printf '%d:' $c; done | sed 's/:$//')"
}

# --- toolchains ---------------------------------------------------------------------
TOOLCHAINS="gcc aocc cce icpx gcc-mpich9"
DEFAULT_TOOLCHAIN=gcc

# --- benchmark checkpoints (8 pc, 384 meshblocks) ------------------------------------
BENCH_DATA=$SCRATCH_BASE/tigris-benchmark   # copied from /projects/EOSTRIKE/tigris-benchmark
BENCH_CACHE=$BENCH_DATA                     # /nobackup is visible from compute nodes
BENCH_RST_mhd=mhd-ncr-8pc/TIGRESS_NCR.00006.rst      # t=300
BENCH_RST_crmhd=crmhd-ncr-8pc/TIGRESS_NCR.00003.rst  # t=150, CR<->NCR coupled

# --- production flags per compiler: complete sets --------------------------------------
# Flag sweep (2026-10-20, flag_variants.txt, fresh start, CRMHD with sparse gravity):
# GCC preset (= FLAGS_GCC), preset-v512 and fast-lto tie within 1%; fast math + LTO is
# worth 7% (MHD) / 15% (CRMHD) over plain -O3; safe-lto (no fast math) is 4% / 9% slower.
# AOCC and icpx variants are 6% and 6-29% behind GCC. Winners kept: FLAGS_GCC preset,
# FLAGS_AOCC preset, FLAGS_ICPX preset (fast2 is 6% faster but removes NaN checks).
# CCE flags are untuned: the toolchain is rejected (see above).
FLAGS_GCC="-O3 -std=c++11 -march=znver5 -ffast-math -fno-finite-math-only -fopenmp-simd -flto=auto -fwhole-program -fprefetch-loop-arrays"
FLAGS_AOCC="-O3 -std=c++11 -march=znver5 -ffast-math -fno-finite-math-only -fopenmp-simd -flto -fuse-ld=lld"
FLAGS_CCE="-O3 -std=c++11 -march=znver5 -ffast-math -fno-finite-math-only -fopenmp-simd -flto"
FLAGS_ICPX="-O3 -std=c++11 -march=znver5 -mtune=znver5 -ipo -qopenmp-simd -fp-model=fast -Wno-tautological-constant-compare -Wno-array-bounds"

load_toolchain() {
    local tc=${1:-$DEFAULT_TOOLCHAIN}
    local fftw_mod=cray-fftw
    module purge
    case "$tc" in
        gcc)
            module load PrgEnv-gnu
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        gcc-mpich9)
            module load PrgEnv-gnu
            module swap cray-mpich cray-mpich/9.0.1
            CXX_PRESET=g++;     TC_CXXFLAGS=$FLAGS_GCC ;;
        aocc)
            module load PrgEnv-aocc
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_AOCC ;;
        cce)
            module load PrgEnv-cray
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_CCE ;;
        icpx)
            module load PrgEnv-intel
            module swap intel intel/2025.3
            CXX_PRESET=clang++; TC_CXXFLAGS=$FLAGS_ICPX ;;
        *)
            echo "load_toolchain: unknown toolchain '$tc' ($TOOLCHAINS)" >&2
            return 1 ;;
    esac
    module load craype-x86-turin cray-hdf5-parallel $fftw_mod cray-pals
    MPI_CXX=CC
    HDF5DIR=$HDF5_DIR
    [ -n "$CRAY_LD_LIBRARY_PATH" ] && export LD_LIBRARY_PATH=$CRAY_LD_LIBRARY_PATH${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}
    if [ -n "$VIRTUAL_ENV" ]; then
        PATH=$(echo "$PATH" | tr ':' '\n' | grep -vxF "$VIRTUAL_ENV/bin" | paste -sd:)
        export PATH
    fi
}

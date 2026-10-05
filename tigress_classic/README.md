# Stellar

Clone repositories at your `$HOME` directory. All you need is at `$HOME/tigris_scripts/tigress_classic/stellar`

## Clone tigris source code repository
```sh
git clone git@github.com:PrincetonUniversity/tigris.git tigris
```

## Clone the script repository (this repository)
```sh
git clone git@github.com:changgoo/tigris_scripts.git
```

## Compile
Use `build_tigress.sh` (run with no arguments for all options). On stellar, tiger and
stellarai-amd, `<machine>/env.sh` supplies the module stack and complete compiler flags,
reusing the toolchain benchmark of TIGRESS-NCR (`../tigress_ncr/<machine>/env.sh` and its
README):

| machine       | default toolchain (`--cc`) | compiler + MPI                    |
|---------------|----------------------------|-----------------------------------|
| stellar       | `icpx-impi`                | oneAPI 2024.2 icpx + Intel MPI    |
| tiger         | `icpx-impi`                | oneAPI 2024.2 icpx + Intel MPI    |
| stellarai-amd | `gcc`                      | GCC 14 + Open MPI                 |

```sh
./build_tigress.sh --machine=stellar --physics=crmhd   # -> stellar/tigris-master_crmhd-fft-icpx-impi.exe
```
The toolchain is part of the exe name, and a job must load the same modules
(`source <machine>/env.sh; load_toolchain <toolchain>`). Job scripts made by `gen_job.py`
do this (see below). The hand-written slurm scripts in `stellar/` and `tiger/` still load
their own modules and run the older exe names, so convert one before using a new exe with
it. Other machines (anvil, ...) keep their hard-coded settings in `build_tigress.sh`.

### Legacy `compile.sh`
First, the script use an alias `module_icpx` to load proper module. Recommended to add these lines to your `.bashrc` file (my choice after some trials and errors).
```sh
alias module_gcc='module purge; module load anaconda3/2023.3 fftw/gcc/3.3.10 intel-mpi/gcc/2021.13 hdf5/gcc/intel-mpi/1.14.4'
alias module_icpx='module purge; module load anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
```
Otherwise, just copy the module load command to the compile script.

Then, simply compile with a choice of `CC` and `physics`. E.g., for crmhd with icpx,
```sh
./compile.sh icpx crmhd
```

## Slurm job submission
See `tigress_classic_crmhd-lowres_subcycle.slurm`. It is taking 6 arguments.
```sh
sbatch tigress_classic_crmhd-lowres_subcycle.slurm <compiler> <start_flag> <MHDBC=diode> <CRBC=lngrad_out> <beta=10> <crsubcycle=false>
```

For a default run, you can submit a job using
```sh
sbatch tigress_classic_crmhd-lowres_subcycle.slurm icpx -i
```

But, read through the script, especially check __parameters__.

Note that the script without a start_flag `-r` will wipe out any existing folder with the same name.
Also, the script automatically resubmit the job if the job is terminated by the wall time limit (`EXITCODE=3`).
To disable this feature, you can simply set the time limit set by `-t` option longer than the slurm time limit set by `#SBATCH --time` option.

At the end, it will automatically call a script for quick snapshot image creation, assuming you have proper `pyathena` installed. Just comment out if you are not sure about this part.

## Unified job script generator (`gen_job.py`)

`gen_job.py` in the `tigress_classic/` directory generates job scripts for all machines.
Use `--machine` to select the target system; Slurm (stellar/tiger/stellarai-amd/anvil) and PBS (nasa_athena) are both supported.

On stellar, tiger and stellarai-amd the job sources `<machine>/env.sh`, loads the toolchain
`CC` (default: `DEFAULT_TOOLCHAIN` of env.sh) and runs the exe `build_tigress.sh` built for it,
`tigris-master_<physics>-fft-<toolchain>.exe`. Pass `--worktree`/`--grav` with the same values
as the build, and pick another toolchain at submission with `sbatch <script> -i CC=gcc-impi`.
The job stops with the build command to run if the exe is missing.

### Mesh geometry

Specify mesh with `--preset` or explicit `--mesh`, `--mblock`, `--dx` flags:

| Preset   | mesh             | meshblock | dx   | domain (x1/x2 × x3)       |
|----------|------------------|-----------|------|----------------------------|
| lowres   | 64×64×512        | 16        | 16pc | ±512 pc × ±4096 pc         |
| medres   | 128×128×1024     | 32        | 8pc  | ±512 pc × ±4096 pc         |
| highres  | 256×256×2048     | 64        | 4pc  | ±512 pc × ±4096 pc         |
| bigbox   | 256×256×1024     | 32        | 8pc  | ±1024 pc × ±4096 pc        |

Node count is derived automatically: `nprocs = (nx1/mb1)×(nx2/mb2)×(nx3/mb3)`, then `nodes = ceil(nprocs / cores_per_node)`. Override with `--nodes` if needed.

### Examples

```sh
# Stellar: crmhd highres (4pc) long run
python3 gen_job.py --machine stellar --preset highres --physics crmhd --walltime 48:00:00

# Tiger: mhd lowres test run, write to file
python3 gen_job.py --machine tiger --preset lowres --physics mhd --walltime 02:00:00 --nlim 100 -o test.slurm

# Anvil: crmhd bigbox with beta=10
python3 gen_job.py --machine anvil --preset bigbox --physics crmhd --walltime 12:00:00 --beta 10 --rundir-suffix b10

# NASA Athena: mhd 4pc long run
python3 gen_job.py --machine nasa_athena --preset highres --physics mhd --walltime 48:00:00 --queue long

# NASA Athena: crmhd devel queue test
python3 gen_job.py --machine nasa_athena --preset highres --physics crmhd --walltime 02:00:00 --queue devel --nlim 100

# Custom mesh (not a preset): 512×512×2048, meshblock 64, dx=2pc on stellar
python3 gen_job.py --machine stellar --mesh 512 512 2048 --mblock 64 --dx 2 --physics crmhd --walltime 48:00:00
```

Run `python3 gen_job.py --help` for all options.


## Compiler flags: keep NaN checks

The solver's safety nets for bad cells are NaN tests: the C2P density and pressure floors,
the CR-FOFC and CRAverage flags, the CR implicit-update revert, and the NCR solver bail-out.
`-ffast-math` (GCC/Clang) and icpx `-fp-model=fast=2` let the compiler assume finite math, so
all of these compile to `false`.

The scripts here therefore keep NaN checks:
- The explicit `-ffast-math` flag sets (anvil, delta, `build_tigress*.sh`) add
  `-fno-finite-math-only`.
- The `g++-simd` builds pass `--cflag=-fno-finite-math-only`, because configure.py's
  `g++-simd` preset hard-codes `-ffast-math`.
- The Stellar/Tiger `icpx` preset keeps icpx's default `fp-model=fast`, which keeps NaN
  checks.

`../tigress_ncr/bench/nan_check.cpp` tests a flag set:

    mpicxx <flags> ../tigress_ncr/bench/nan_check.cpp -o nan_check && ./nan_check 0

It prints `nan_checks=kept` for safe flag sets. See also `../tigress_ncr/README.md`, section
"Floating-point model".

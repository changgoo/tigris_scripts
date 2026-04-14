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
See `compile.sh`.

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
Use `--machine` to select the target system; Slurm (stellar/tiger/anvil) and PBS (nasa_athena) are both supported.

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


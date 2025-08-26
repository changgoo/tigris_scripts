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



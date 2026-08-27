# Build and run TIGRESS-NCR with cosmic rays on Stellar

This procedure builds the CRMHD + NCR executable and submits the coupled
TIGRESS-NCR job on Stellar.  Commands below are literal: they do not depend on
shell aliases such as `ml`.  The standard environment variables `HOME` and
`USER` are used because the build and job scripts use the same paths.

The coupled configuration has all three of these settings:

- the executable is configured with `--cr=mg` and `-ncr`;
- `athinput.tigress_ncr` sets `<photchem>/mode = ncr` and
  `<cr>/self_consistent_flag = 1`;
- the Slurm job supplies the runtime override `cr/photchem_flag=1`.

Together, these settings allow CR energy density to set the local NCR cosmic-ray
ionization rate and allow NCR ion/neutral abundances to set the CR scattering
coefficient.

## 1. Start a login shell and initialize Modules

Log in to Stellar and use Bash.  If `module` is not already defined by the
login shell, initialize Environment Modules explicitly:

```bash
source /usr/share/Modules/init/bash
type module
type sbatch
type squeue
```

The last three commands should report a shell function for `module` and paths
for the Slurm commands.  Do not substitute a local alias such as `ml` for the
`module` commands below.

## 2. Verify the repository layout

The scripts assume these exact locations:

```text
$HOME/tigris
$HOME/tigris/.worktrees/ncr-cr-coupling
$HOME/tigris_scripts/tigress_ncr
```

Verify the main source repository and this scripts repository:

```bash
test -d "$HOME/tigris/.git"
test -f "$HOME/tigris_scripts/tigress_ncr/build_tigress.sh"
test -f "$HOME/tigris_scripts/tigress_ncr/athinput.tigress_ncr"
```

If the main source repository is missing, clone it explicitly:

```bash
git clone git@github.com:PrincetonUniversity/tigris.git "$HOME/tigris"
```

The job uses the `ncr-cr-coupling` source worktree because that branch contains
the coupled code and the required 10-column cooling table.  Check an existing
worktree before using it:

```bash
git -C "$HOME/tigris" fetch origin ncr-cr-coupling
git -C "$HOME/tigris/.worktrees/ncr-cr-coupling" status --short --branch
```

Stop and resolve any unmerged or modified files reported by `git status` before
building.  Once the worktree is clean and checked out on the local
`ncr-cr-coupling` branch, fast-forward it explicitly:

```bash
git -C "$HOME/tigris/.worktrees/ncr-cr-coupling" merge --ff-only origin/ncr-cr-coupling
```

If the worktree does not exist, create a clean detached worktree at the remote
branch instead:

```bash
mkdir -p "$HOME/tigris/.worktrees"
git -C "$HOME/tigris" fetch origin ncr-cr-coupling
git -C "$HOME/tigris" worktree add --detach \
  "$HOME/tigris/.worktrees/ncr-cr-coupling" origin/ncr-cr-coupling
```

Confirm that the source and both runtime tables exist:

```bash
test -f "$HOME/tigris/.worktrees/ncr-cr-coupling/src/pgen/tigress_ncr.cpp"
test -f "$HOME/tigris/.worktrees/ncr-cr-coupling/inputs/tables/tigress_coolftn_ncr.txt"
test -f "$HOME/tigris/.worktrees/ncr-cr-coupling/inputs/tables/Z014_GenevaV00.txt"
```

## 3. Load the Stellar build environment

Use the Intel oneAPI/Open MPI stack used by both the build script and the
`icpx` path in the Slurm jobs:

```bash
module purge
module load anaconda3/2023.3
module load intel-oneapi/2024.2
module load openmpi/oneapi-2024.2/4.1.6
module load hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4
module load fftw/oneapi-2024.2/3.3.10
module list
command -v icpx
command -v mpicxx
```

`build_tigress.sh` repeats these `module purge` and `module load` commands so
the build is not affected by previously loaded modules.

## 4. Build the CRMHD + NCR executable

Run the build script from `tigress_ncr/`; its current directory determines
where the finished executable is copied.

```bash
cd "$HOME/tigris_scripts/tigress_ncr"
bash ./build_tigress.sh \
  --machine=stellar \
  --physics=crmhd \
  --grav=fft \
  --build=0 \
  --src=tigris \
  --flux=hll \
  --worktree=ncr-cr-coupling
```

This configures Athena++ with the effective physics options
`-b --cr=mg --flux=hlld -ncr`, builds with four make jobs, and copies the
result here:

```text
$HOME/tigris_scripts/tigress_ncr/stellar/tigris_ncr_crmhd-fft.exe
```

Verify it before submitting:

```bash
test -x "$HOME/tigris_scripts/tigress_ncr/stellar/tigris_ncr_crmhd-fft.exe"
ls -lh "$HOME/tigris_scripts/tigress_ncr/stellar/tigris_ncr_crmhd-fft.exe"
```

## 5. Check the job-specific settings

The Slurm scripts currently use account `eost`.  Set `#SBATCH --account` to a
different allocation if needed.  The production script also sends mail to the
address in `#SBATCH --mail-user`; update that line before submitting if it is
not your address.

The batch job selects its compiler environment from its first argument.  Use
`icpx`, matching the module stack and build above.  Inside the allocation the
job explicitly runs the equivalent of:

```bash
module purge
module load anaconda3/2023.3
module load intel-oneapi/2024.2
module load openmpi/oneapi-2024.2/4.1.6
module load hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4
module load fftw/oneapi-2024.2/3.3.10
```

The coupled jobs copy the executable, input file, cooling table, and population
synthesis table into a run directory under
`/scratch/gpfs/$USER/tigress_ncr/`.

Important: submitting without `-r` is a fresh start.  If the target run
directory already exists, the job deletes its contents before launching.
Inspect or move any existing run data first.

## 6. Submit the one-node coupled test job

Start with the 16 pc coupled job.  It uses one node, 32 MPI ranks, and one
32-cubed meshblock per rank:

```bash
cd "$HOME/tigris_scripts/tigress_ncr/stellar"
sbatch ./tigress_ncr_crmhd_16pc_test_coupled.slurm icpx
```

Slurm prints a job ID.  The run directory is:

```text
/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-16pc-test-coupled
```

Monitor it with explicit Slurm commands, replacing `JOB_ID` with the number
printed by `sbatch`:

```bash
squeue --user "$USER"
scontrol show job JOB_ID
tail -f "$HOME/tigris_scripts/tigress_ncr/stellar/crncr16c-JOB_ID.out"
tail -f "$HOME/tigris_scripts/tigress_ncr/stellar/crncr16c-JOB_ID.err"
```

The Slurm output should show `cr/photchem_flag=1` in `params`.  Athena's own
standard output and error are written inside the run directory:

```bash
tail -f "/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-16pc-test-coupled/out.txt"
tail -f "/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-16pc-test-coupled/err.txt"
```

The test job does not automatically resubmit.  If it produced
`TIGRESS_NCR.final.rst` and needs another walltime segment, submit a restart:

```bash
test -f "/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-16pc-test-coupled/TIGRESS_NCR.final.rst"
cd "$HOME/tigris_scripts/tigress_ncr/stellar"
sbatch ./tigress_ncr_crmhd_16pc_test_coupled.slurm icpx -r
```

## 7. Submit the four-node 8 pc production job

After the coupled test is satisfactory, submit the 8 pc job.  It uses four
nodes and 384 MPI ranks:

```bash
cd "$HOME/tigris_scripts/tigress_ncr/stellar"
sbatch ./tigress_ncr_crmhd_8pc.slurm icpx
```

Its run directory is:

```text
/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-8pc-mesh-level
```

This production job requests a 23.5-hour Athena soft limit within a 24-hour
Slurm allocation.  When Athena exits with code 3 at that soft limit, the script
automatically submits the next restart as:

```bash
cd "$HOME/tigris_scripts/tigress_ncr/stellar"
sbatch ./tigress_ncr_crmhd_8pc.slurm icpx -r
```

For a manual restart, first confirm that the final restart file exists, then
run the same command:

```bash
test -f "/scratch/gpfs/$USER/tigress_ncr/crmhd-ncr-8pc-mesh-level/TIGRESS_NCR.final.rst"
cd "$HOME/tigris_scripts/tigress_ncr/stellar"
sbatch ./tigress_ncr_crmhd_8pc.slurm icpx -r
```

## 8. Postprocessing dependency

After Athena exits, both coupled job scripts attempt snapshot postprocessing.
That step expects all of the following to exist:

```text
$HOME/.conda/envs/pyathena
$HOME/pyathena_master
$HOME/TIGRESS-CR/python/plot_slices_ncr.py
```

It explicitly changes to this environment:

```bash
module purge
module load anaconda3/2024.6
module load openmpi/gcc/4.1.6
conda activate pyathena
```

A missing postprocessing dependency can make the final plotting step fail, but
it does not change whether the preceding Athena simulation completed.  Check
both the Slurm logs and the Athena logs in the run directory when diagnosing a
job.

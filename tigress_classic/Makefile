# User-configurable variables
MACHINE ?= stellar
CC ?= icpx
PHYSICS ?= hydro
DEBUG ?= 0

# Athena source and build directories
SRCDIR ?= $(HOME)/tigris
BUILDDIR ?= $(SRCDIR)
CURDIR := $(shell pwd)

# Problem name
PROB := tigress_classic

# Compiler and physics options
ifeq ($(PHYSICS),hydro)
  PHY_OPTIONS :=
else ifeq ($(PHYSICS),mhd)
  PHY_OPTIONS := -b
else ifeq ($(PHYSICS),crmhd)
  PHY_OPTIONS := -b --cr=mg
else
  PHY_OPTIONS :=
endif

# Machine-specific module loading
ifeq ($(MACHINE),stellar)
  MODULE_LOAD := anaconda3/2023.3 intel-oneapi/2024.2 openmpi/oneapi-2024.2/4.1.6 hdf5/oneapi-2024.2/openmpi-4.1.6/1.14.4 fftw/oneapi-2024.2/3.3.10
  CC := icpx
else ifeq ($(MACHINE),tiger)
  MODULE_LOAD :=
  CC := icpx
else ifeq ($(MACHINE),anvil)
  MODULE_LOAD := module purge; module load anaconda; module load gcc; module load openmpi; module load fftw hdf5
  HDF5DIR := $(RCAC_HDF5_ROOT)
  CC := icpx
else
  MODULE_LOAD :=
  CC := g++
endif

ifeq ($(DEBUG),1)
  DEBUG_OPTION := -debug
  CC := g++
else
  DEBUG_OPTION :=
endif

# Athena configure options
CONFIG_OPTIONS := $(DEBUG_OPTION) --nghost=4 -fft -fb --grav=blockfft -mpi -hdf5 --cxx=$(CC)

# Target executable name
EXE := $(CURDIR)/$(MACHINE)/$(PROB)_$(PHYSICS)_$(CC)$(DEBUG_OPTION).exe

.PHONY: all clean

all:
	@echo "Loading modules for $(MACHINE)... $(MODULE_LOAD)"
	@if [ -n "$(MODULE_LOAD)" ]; then \
    module purge && module load $(MODULE_LOAD) && module list; \
  fi; \
  HDF5_LIB := $(HDF5DIR)/lib64; \
  HDF5_INC := $(HDF5DIR)/include; \
  PATH_OPTIONS := --lib_path=$(HDF5_LIB) --include=$(HDF5_INC); \
	echo "Configuring Athena++ in $(BUILDDIR)..."; \
	cd $(BUILDDIR) && ./configure.py --prob=$(PROB) $(CONFIG_OPTIONS) $(PHY_OPTIONS) $(PATH_OPTIONS); \
	cd $(BUILDDIR) && make clean && make all -j4; \
  cp $(BUILDDIR)/bin/athena $(EXE); \
	echo "Executable copied to $(EXE)"

clean:
	@cd $(BUILDDIR) && make clean
	@rm -f $(EXE)

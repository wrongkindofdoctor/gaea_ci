# Test executable builds
SITE ?= skylake
COMPILERS ?= skylake-intel20
MODES ?= debug
GRIDS ?= dynamic_symmetric dynamic
CONFIGURATIONS ?= ice_ocean_SIS2
SIS2_CONFIGS = ice_ocean_SIS2

# Sometimes BASE will be the regression test suite dir
BASE := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
REPO := $(BASE)
ENVIRONS := $(BASE)/environs
TEMPLATES := $(REPO)/src/mkmf/templates
LIST_PATHS := $(REPO)/src/mkmf/bin/list_paths
MKMF := $(REPO)/src/mkmf/bin/mkmf


# Source trees
shared_src = src/FMS
ice_ocean_SIS2_src = src/MOM6/config_src/coupled_driver \
                     $(sort $(dir src/MOM6/src/*)) \
                     $(sort $(dir src/MOM6/src/*/*)) \
                     src/FMScoupler/full \
                     src/FMScoupler/shared \
                     src/atmos_null \
                     src/land_null \
                     src/icebergs \
                     src/ice_param \
                     src/SIS2/src \
                     src/FMS/include

# Track individual files
shared_files = $(sort $(foreach d, $(shared_src), $(shell find $(d) -name '*.F90')))
ice_ocean_SIS2_files = $(sort $(foreach d, $(ice_ocean_SIS2_src), $(shell find $(d) -name '*.F90')))

# MOM6 grid-specific source
mom6_dynamic_src = ../src/MOM6/config_src/dynamic
mom6_dynamic_symmetric_src = ../src/MOM6/config_src/dynamic_symmetric

# SIS2 grid-specific source
sis2_dynamic_src = ../src/SIS2/config_src/dynamic
sis2_dynamic_symmetric_src = ../src/SIS2/config_src/dynamic_symmetric

# mkmf preprocessor flags
shared_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD"
ice_ocean_SIS2_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_"


# Functions
all_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), build/$(c)/$(m)/$(g)/$(1)/$(2))))
all_configs = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/$(c)/$(m)/$(g)/$(p)/$(1)))))
all_projects = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS) shared, build/$(c)/$(m)/$(g)/$(p)/$(1)))))

# FMS projects
fms_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), build/$(c)/$(m)/$(g)/shared/$(1))))

# MOM6-SIS2 executables
sis2_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(SIS2_CONFIGS), build/$(c)/$(m)/$(g)/$(p)/$(1)))))

all_repro = $(foreach c, $(COMPILERS), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/$(c)/repro/$(g)/$(p)/$(1))))
all_debug = $(foreach c, $(COMPILERS), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/$(c)/debug/$(g)/$(p)/$(1))))


# Target pathname parsing
compiler = $(word 2,$(subst /, ,$@))
mode = $(word 3,$(subst /, ,$@))
grid = $(word 4,$(subst /, ,$@))
config = $(word 5,$(subst /, ,$@))


# Modes
repro_flags = REPRO=1
debug_flags = DEBUG=1


# Rules
.PHONY: all dev debug

# Development builds; swap with `all` for deployment
all: $(call all_debug,MOM6)
dev: $(foreach c, $(CONFIGURATIONS), $(foreach x, $(COMPILERS), build/$(x)/repro/dynamic_symmetric/$(c)/MOM6))
debug: $(foreach c, $(CONFIGURATIONS), $(foreach x, $(COMPILERS), build/$(x)/debug/dynamic_symmetric/$(c)/MOM6))

# path_names
$(call all_builds,shared,path_names): $(shared_src)
$(call all_builds,ice_ocean_SIS2,path_names): $(ice_ocean_SIS2_src)

$(call fms_builds,path_names):
	mkdir -p $(dir $@)
	cd $(dir $@) && $(LIST_PATHS) \
		-l $(addprefix $(REPO)/, $^)

$(call sis2_builds,path_names):
	mkdir -p $(dir $@)
	cd $(dir $@) && $(LIST_PATHS) \
		-l \
			$(addprefix $(REPO)/, $^) \
			$(addprefix $(REPO)/, $(mom6_$(grid)_src)) \
			$(addprefix $(REPO)/, $(sis2_$(grid)_src))

# Makefile
$(call all_builds,shared,Makefile) : %/Makefile : %/path_names $(shared_files)
	cd $(dir $@) && $(MKMF) \
		-t $(TEMPLATES)/$(compiler).mk \
		-p libfms.a \
		-c $($(config)_cpp) \
		$(notdir $<)


# NOTE: Still not sure if file should go with `Makefile` or `MOM6`...
# Replace libfms with generic %/shared rule?
# TODO: Merge with all_configs?
$(call all_builds,ice_ocean_SIS2,Makefile): %/ice_ocean_SIS2/Makefile: %/shared/libfms.a $(ice_ocean_SIS2_files)

# TODO: Define path to shared as function?
$(call all_configs,Makefile): %/Makefile: %/path_names
	cd $(dir $@) && $(MKMF) \
		-t $(TEMPLATES)/$(compiler).mk \
		-o '-I $(BASE)/$(subst $(config),shared,$(dir $@))' \
		-p MOM6 \
		-l '-L $(BASE)/$(subst $(config),shared,$(dir $@)) -lfms' \
		-c $($(config)_cpp) \
		$(notdir $<)


# libfms.a and MOM6 builds
$(call all_builds,shared,libfms.a): %/libfms.a: %/Makefile
$(call all_configs,MOM6): %/MOM6: %/Makefile

$(call all_builds,shared,libfms.a) $(call all_configs,MOM6):
	make \
		-j \
		-C $(dir $@) \
		NETCDF=3 \
		$($(mode)_flags) \
		$(notdir $@)



clean:
	rm -rf build

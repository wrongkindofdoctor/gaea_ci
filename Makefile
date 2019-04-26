# Attempt at a general Makefile for multiple drivers and compilers
# Rules are all phony at the moment, currently not filename-based

# Functions

# Drivers
DRIVERS := ocean_only ice_ocean_SIS2

# Expected template format is ${SITE}-${COMPILER}.mk
COMPILERS := gnu intel pgi
MODES := repro debug
SITE ?= ncrc

# Mode configuration flags
repro_flags = REPRO=1
debug_flags = DEBUG=1

# This does not invoke the shell, but adds a redundant slash (-_-)
#BASE := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
BASE := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
REPO := ${BASE}/MOM6-examples
LIST_PATHS := ${REPO}/src/mkmf/bin/list_paths
MKMF := ${REPO}/src/mkmf/bin/mkmf
TEMPLATES := ${REPO}/src/mkmf/templates

ENVIRONS := ${BASE}/environs

# "Lazy" evaluation of current build directory
# These assume rules of the form $(compiler)/$(config)/$(mode)
# 	but $(word n ...) could support other formats
BUILD = ${BASE}/build/$@
compiler = $(firstword $(subst /, ,$@))
mode = $(lastword $(subst /, ,$@))

all: ${DRIVERS}

ocean_only: $(foreach c, ${COMPILERS}, $c/ocean_only)
#ice_ocean_SIS2: $(foreach c, ${COMPILERS}, $c/ice_ocean_SIS2)
#coupled_AM2_LM3_SIS
#coupled_AM2_LM3_SIS2
#ice_ocean_SIS
#land_ice_ocean_LM3_SIS2
shared: $(foreach c, ${COMPILERS}, $c/shared)

%/ocean_only: %/shared
	mkdir -p ${BUILD}
	rm -f ${BUILD}/path_names
	cd ${BUILD} && ${LIST_PATHS} \
		-l ${REPO}/src/MOM6/{config_src/dynamic_symmetric,config_src/solo_driver,src/{*,*/*}}
	cd ${BUILD} && ${MKMF} \
		-t ${TEMPLATES}/${SITE}-$*.mk \
		-o '-I ${BASE}/build/$*/shared/repro' \
		-p MOM6 \
		-l '-L${BASE}/build/$*/shared/repro -lfms' \
		-c '-Duse_libMPI -Duse_netCDF -DSPMD' \
		${BUILD}/path_names
	source ${ENVIRONS}/$*.env && make \
		-j \
		-C ${BUILD} \
		NETCDF=3 \
		REPRO=1 \
		MOM6

# Using -build is just a hacky way to bundle multiple rules with dependencies
# Probably a better way to do it...
# TODO: Set .PHONY iteratively

%/ice_ocean_SIS2: $(foreach m, $(MODES), %/ice_ocean_SIS2/$(m)-build)
	@echo "Finishing $@"

# Need empty recipes (;) here!
%/ice_ocean_SIS2/repro-build: %/shared/repro %/ice_ocean_SIS2/repro ;
%/ice_ocean_SIS2/debug-build: %/shared/debug %/ice_ocean_SIS2/debug ;

$(foreach c,$(COMPILERS), $(foreach m, $(MODES), $(c)/ice_ocean_SIS2/$(m))):
	@echo "Starting $@"
	mkdir -p $(BUILD)
	rm -f $(BUILD)/path_names
	cd $(BUILD) && $(LIST_PATHS) \
		-l \
			$(REPO)/src/MOM6/config_src/{dynamic_symmetric,coupled_driver} \
			$(REPO)/src/MOM6/src/{*,*/*}/ \
			$(REPO)/src/{atmos_null,coupler,land_null,ice_ocean_extras,icebergs,SIS2,FMS/coupler,FMS/include}
	cd $(BUILD) && $(MKMF) \
		-t $(TEMPLATES)/$(SITE)-$(compiler).mk \
		-o '-I $(BASE)/build/$(compiler)/shared/repro' \
		-p MOM6 \
		-l '-L $(BASE)/build/$(compiler)/shared/repro -lfms' \
		-c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_' \
		$(BUILD)/path_names
	source $(ENVIRONS)/$(compiler).env && make \
		-j \
		-C $(BUILD) \
		NETCDF=3 \
		$($(@F)_flags) \
		MOM6
	@echo "Finished $@"

# No real need for dirty tricks here, due to no dependencies

%/shared: $(foreach m, $(MODES), %/shared/$(m))
	@echo "Finished $^"

$(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(c)/shared/$(m))):
	@echo "Starting $@"
	mkdir -p $(BUILD)
	rm -f $(BUILD)/path_names
	cd $(BUILD) && $(LIST_PATHS) \
		-l $(REPO)/src/FMS
	cd $(BUILD) && $(MKMF) \
		-t $(TEMPLATES)/$(SITE)-$(compiler).mk \
		-p libfms.a \
		-c "-Duse_libMPI -Duse_netCDF -DSPMD" \
		$(BUILD)/path_names
	source $(ENVIRONS)/$(compiler).env && make \
		-j \
		-C $(BUILD) \
		NETCDF=3 \
		$($(mode)_flags) \
		libfms.a
	@echo "Finished $@"

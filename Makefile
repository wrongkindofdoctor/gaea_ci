# Attempt at a general Makefile for multiple drivers and compilers
# Rules are all phony at the moment, currently not filename-based

# Drivers
DRIVERS := ocean_only ice_ocean_SIS2

# Expected template format is ${SITE}-${COMPILER}.mk
COMPILERS := gnu intel pgi
SITE ?= ncrc

# This does not invoke the shell, but adds a redundant slash (-_-)
#BASE := $(dir $(realpath $(lastword $(MAKEFILE_LIST))))
BASE := $(shell dirname $(realpath $(lastword $(MAKEFILE_LIST))))
REPO := ${BASE}/MOM6-examples
LIST_PATHS := ${REPO}/src/mkmf/bin/list_paths
MKMF := ${REPO}/src/mkmf/bin/mkmf
TEMPLATES := ${REPO}/src/mkmf/templates

ENVIRONS := ${BASE}/environs

# "Lazy" evaluation of current build directory
BUILD = ${BASE}/build/$@/repro

all: ${DRIVERS}

ocean_only: $(foreach c, ${COMPILERS}, $c/ocean_only)
ice_ocean_SIS2: $(foreach c, ${COMPILERS}, $c/ice_ocean_SIS2)
shared: $(foreach c, ${COMPILERS}, $c/shared)

%/ocean_only: %/shared
	mkdir -p ${BUILD}
	rm -f ${BUILD}/path_names
	cd ${BUILD} && ${LIST_PATHS} \
		-l ${REPO}/src/MOM6/{config_src/dynamic,config_src/solo_driver,src/{*,*/*}}
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

%/ice_ocean_SIS2: %/shared
	mkdir -p ${BUILD}
	rm -f ${BUILD}/path_names
	cd ${BUILD} && ${LIST_PATHS} \
		-l \
			${REPO}/src/MOM6/config_src/{dynamic,coupled_driver} \
			${REPO}/src/MOM6/src/{*,*/*}/ \
			${REPO}/src/{atmos_null,coupler,land_null,ice_ocean_extras,icebergs,SIS2,FMS/coupler,FMS/include}
	cd ${BUILD} && ${MKMF} \
		-t ${TEMPLATES}/${SITE}-$*.mk \
		-o '-I ${BASE}/build/$*/shared/repro' \
		-p MOM6 \
		-l '-L ${BASE}/build/$*/shared/repro -lfms' \
		-c '-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_' \
		${BUILD}/path_names
	source ${ENVIRONS}/$*.env && make \
		-j \
		-C ${BUILD} \
		NETCDF=3 \
		REPRO=1 \
		MOM6

%/shared:
	mkdir -p ${BUILD}
	rm -f ${BUILD}/path_names
	cd ${BUILD} && ${LIST_PATHS} \
		-l ${REPO}/src/FMS
	cd ${BUILD} && ${MKMF} \
		-t ${TEMPLATES}/${SITE}-$*.mk \
		-p libfms.a \
		-c "-Duse_libMPI -Duse_netCDF -DSPMD" \
		${BUILD}/path_names
	source ${ENVIRONS}/$*.env && make \
		-j \
		-C ${BUILD} \
		NETCDF=3 \
		REPRO=1 \
		libfms.a

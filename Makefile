# Test executable builds
SITE ?= ncrc
COMPILERS ?= gnu #intel pgi
MODES ?= repro debug
GRIDS ?= dynamic_symmetric dynamic
CONFIGURATIONS ?= \
	ocean_only \
	ice_ocean_SIS2 #\
	#land_ice_ocean_LM3_SIS2 \
	#coupled_AM2_LM3_SIS \
	#coupled_AM2_LM3_SIS2

# TODO: Merge into configurations?
MOM6_CONFIGS = \
	ocean_only

SIS1_CONFIGS = \
	coupled_AM2_LM3_SIS

SIS2_CONFIGS = \
	ice_ocean_SIS2 \
	land_ice_ocean_LM3_SIS2 \
	coupled_AM2_LM3_SIS2

# Sometimes BASE will be the regression test suite dir
BASE := $(realpath $(dir $(lastword $(MAKEFILE_LIST))))
REPO := $(BASE)
ENVIRONS := $(BASE)/environs
TEMPLATES := $(REPO)/src/mkmf/templates
LIST_PATHS := $(REPO)/src/mkmf/bin/list_paths
MKMF := $(REPO)/src/mkmf/bin/mkmf


# Source trees
# TODO: Bundle submodel directories together into variables
shared_src = \
	src/FMS 
ocean_only_src = \
	src/MOM6/config_src/solo_driver \
	$(sort $(dir src/MOM6/src/*)) \
	$(sort $(dir src/MOM6/src/*/*)) \
	src/FMS/include
#ice_ocean_SIS2_src = \
#	src/MOM6/config_src/coupled_driver \
#	$(sort $(dir src/MOM6/src/*)) \
#	$(sort $(dir src/MOM6/src/*/*)) \
#	src/coupler \
#	src/atmos_null \
#	src/land_null \
#	src/icebergs src/ice_param src/SIS2 \
#	src/FMS/coupler src/FMS/include
ice_ocean_SIS2_src = \
	src/MOM6/config_src/coupled_driver \
	$(sort $(dir src/MOM6/src/*)) \
	$(sort $(dir src/MOM6/src/*/*)) \
	src/FMScoupler/full src/FMScoupler/shared \
	src/atmos_null \
	src/land_null \
	src/icebergs src/ice_param src/SIS2/src \
	src/FMS/include
land_ice_ocean_LM3_SIS2_src = \
	src/MOM6/config_src/coupled_driver \
	$(sort $(dir src/MOM6/src/*)) \
	$(sort $(dir src/MOM6/src/*/*)) \
	src/FMScoupler/full src/FMScoupler/shared \
	src/atmos_null \
	src/LM3 \
	src/icebergs src/ice_param src/SIS2/src \
	src/FMS/include
coupled_AM2_LM3_SIS_src = \
	src/MOM6/config_src/coupled_driver \
	$(sort $(dir src/MOM6/src/*)) \
	$(sort $(dir src/MOM6/src/*/*)) \
	src/FMScoupler/full src/FMScoupler/shared \
	$(addprefix src/AM2/,atmos_drivers/coupled atmos_shared_am3) \
	$(addprefix src/AM2/,$(addprefix atmos_fv_dynamics/, driver/coupled model tools)) \
	src/atmos_param_am3 \
	src/LM3 \
	src/ice_param src/SIS \
	src/FMS/include
coupled_AM2_LM3_SIS2_src = \
	src/MOM6/config_src/coupled_driver \
	$(sort $(dir src/MOM6/src/*)) \
	$(sort $(dir src/MOM6/src/*/*)) \
	src/FMScoupler/full src/FMScoupler/shared \
	$(addprefix src/AM2/,atmos_drivers/coupled atmos_shared_am3) \
	$(addprefix src/AM2/,$(addprefix atmos_fv_dynamics/, driver/coupled model tools)) \
	src/atmos_param_am3 \
	src/LM3 \
	src/icebergs src/ice_param src/SIS2/src \
	src/FMS/include

# Track individual files
# TODO: Build up the sources first, by model (not project)
# 		Then use $(dir ..) to build up the project directories for path_names
# TODO: These may ultimately not be necessary... I do not plan on touching
# 		anything but MOM6 code so only need to track src/MOM6.
shared_files = $(sort $(foreach d, $(shared_src), $(shell find $(d) -name '*.F90')))
ocean_only_files = $(sort $(foreach d, $(ocean_only_src), $(shell find $(d) -name '*.F90')))
ice_ocean_SIS2_files = $(sort $(foreach d, $(ice_ocean_SIS2_src), $(shell find $(d) -name '*.F90')))
land_ice_ocean_LM3_SIS2_files = $(sort $(foreach d, $(land_ice_ocean_LM3_SIS2_src), $(shell find $(d) -name '*.F90')))
coupled_AM2_LM3_SIS_files = $(sort $(foreach d, $(coupled_AM2_LM3_SIS_src), $(shell find $(d) -name '*.F90')))
coupled_AM2_LM3_SIS2_files = $(sort $(foreach d, $(coupled_AM2_LM3_SIS2_src), $(shell find $(d) -name '*.F90')))

# MOM6 grid-specific source
mom6_dynamic_src = \
	src/MOM6/config_src/dynamic
mom6_dynamic_symmetric_src = \
	src/MOM6/config_src/dynamic_symmetric

# SIS2 grid-specific source
sis2_dynamic_src = \
	src/SIS2/config_src/dynamic
sis2_dynamic_symmetric_src = \
	src/SIS2/config_src/dynamic_symmetric

# mkmf preprocessor flags
shared_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD"
ocean_only_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD"
ice_ocean_SIS2_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_"
land_ice_ocean_LM3_SIS2_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_"
coupled_AM2_LM3_SIS_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_"
coupled_AM2_LM3_SIS2_cpp = "-Duse_libMPI -Duse_netCDF -DSPMD -Duse_AM3_physics -D_USE_LEGACY_LAND_"


# Functions
# TODO: Condense these into nested function calls
all_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), build/$(c)/$(m)/$(g)/$(1)/$(2))))
all_configs = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/$(c)/$(m)/$(g)/$(p)/$(1)))))
all_projects = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS) shared, build/$(c)/$(m)/$(g)/$(p)/$(1)))))

# FMS projects
fms_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), build/$(c)/$(m)/$(g)/shared/$(1))))

# MOM6 or MOM6-SIS1 executables
mom6_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(SIS1_CONFIGS) $(MOM6_CONFIGS), build/$(c)/$(m)/$(g)/$(p)/$(1)))))

# MOM6-SIS2 executables
sis2_builds = $(foreach c, $(COMPILERS), $(foreach m, $(MODES), $(foreach g, $(GRIDS), $(foreach p, $(SIS2_CONFIGS), build/$(c)/$(m)/$(g)/$(p)/$(1)))))

all_repro = $(foreach c, $(COMPILERS), $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/$(c)/repro/$(g)/$(p)/$(1))))
all_debug = $(foreach g, $(GRIDS), $(foreach p, $(CONFIGURATIONS), build/gnu/debug/$(g)/$(p)/$(1)))


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
dev: $(foreach c, $(CONFIGURATIONS), build/gnu/repro/dynamic_symmetric/$(c)/MOM6)
debug: $(foreach c, $(CONFIGURATIONS), build/gnu/debug/dynamic_symmetric/$(c)/MOM6)
all: $(call all_repro,MOM6) $(call all_debug,MOM6)

# Internal GFDL source code checkout
# TODO: Set up proper dependencies within the recipes
$(call all_builds,land_ice_ocean_SIS2,MOM6): src/LM3
$(call all_builds,coupled_AM2_LM3_SIS,MOM6): src/AM2 src/LM3 src/SIS
$(call all_builds,coupled_AM2_LM3_SIS2,MOM6): src/AM2 src/LM3

src/AM2:
	mkdir -p $@
	git -C $@ clone http://gitlab.gfdl.noaa.gov/fms/atmos_shared_am3.git
	git -C $@/atmos_shared_am3 checkout warsaw_201803
	git -C $@ clone http://gitlab.gfdl.noaa.gov/fms/atmos_drivers.git
	git -C $@/atmos_drivers checkout warsaw_201803
	git -C $@ clone http://gitlab.gfdl.noaa.gov/fms/atmos_fv_dynamics.git
	git -C $@/atmos_fv_dynamics checkout warsaw_201803
	git -C $(dir $@) clone http://gitlab.gfdl.noaa.gov/fms/atmos_param_am3.git
	git -C $(dir $@)/atmos_param_am3 checkout warsaw_201803

src/LM3:
	mkdir -p $@
	git -C $@ clone http://gitlab.gfdl.noaa.gov/fms/land_param.git
	git -C $@/land_param checkout xanadu
	git -C $@ clone http://gitlab.gfdl.noaa.gov/fms/land_lad2.git
	git -C $@/land_lad2 checkout verona_201701
	# LM3 requires explicit preprocessing
	find $@/land_lad2 -type f -name \*.F90 \
		-exec cpp -Duse_libMPI -Duse_netCDF -DSPMD -Duse_LARGEFILE -C -nostdinc -v -I $(REPO)/src/FMS/include -o '{}'.cpp {} \;
	find $@/land_lad2 -type f -name \*.F90.cpp -exec rename .F90.cpp .f90 {} \;
	find $@/land_lad2 -type f -name \*.F90 -exec rename .F90 .F90_preCPP {} \;

src/SIS:
	git -C $(dir $@) clone http://gitlab.gfdl.noaa.gov/fms/ice_sis.git $(notdir $@)
	git -C $@ checkout xanadu


# path_names
$(call all_builds,shared,path_names): $(shared_src)
$(call all_builds,ocean_only,path_names): $(ocean_only_src)
$(call all_builds,ice_ocean_SIS2,path_names): $(ice_ocean_SIS2_src)
$(call all_builds,land_ice_ocean_LM3_SIS2,path_names): $(land_ice_ocean_LM3_SIS2_src)
$(call all_builds,coupled_AM2_LM3_SIS,path_names): $(coupled_AM2_LM3_SIS_src)
$(call all_builds,coupled_AM2_LM3_SIS2,path_names): $(coupled_AM2_LM3_SIS2_src)


$(call fms_builds,path_names):
	mkdir -p $(dir $@)
	cd $(dir $@) && $(LIST_PATHS) \
		-l $(addprefix $(REPO)/, $^)

$(call mom6_builds,path_names):
	mkdir -p $(dir $@)
	cd $(dir $@) && $(LIST_PATHS) \
		-l \
			$(addprefix $(REPO)/, $^) \
			$(addprefix $(REPO)/, $(mom6_$(grid)_src))

$(call sis2_builds,path_names):
	mkdir -p $(dir $@)
	cd $(dir $@) && $(LIST_PATHS) \
		-l \
			$(addprefix $(REPO)/, $^) \
			$(addprefix $(REPO)/, $(mom6_$(grid)_src)) \
			$(addprefix $(REPO)/, $(sis2_$(grid)_src))

#$(call all_projects,path_names):
#	mkdir -p $(dir $@)
#	cd $(dir $@) && $(LIST_PATHS) \
#		-l $(addprefix $(REPO)/, $^) $(addprefix $(REPO)/, $($(grid)_src))


# Makefile
$(call all_builds,shared,Makefile) : %/Makefile : %/path_names $(shared_files)
	cd $(dir $@) && $(MKMF) \
		-t $(TEMPLATES)/$(SITE)-$(compiler).mk \
		-p libfms.a \
		-c $($(config)_cpp) \
		$(notdir $<)


# NOTE: Still not sure if file should go with `Makefile` or `MOM6`...
# Replace libfms with generic %/shared rule?
# TODO: Merge with all_configs?
$(call all_builds,ocean_only,Makefile): %/ocean_only/Makefile: %/shared/libfms.a $(ocean_only_files)
$(call all_builds,ice_ocean_SIS2,Makefile): %/ice_ocean_SIS2/Makefile: %/shared/libfms.a $(ice_ocean_SIS2_files)
$(call all_builds,land_ice_ocean_LM3_SIS2,Makefile): %/land_ice_ocean_LM3_SIS2/Makefile: %/shared/libfms.a $(land_ice_ocean_LM3_SIS2_files)
$(call all_builds,coupled_AM2_LM3_SIS,Makefile): %/coupled_AM2_LM3_SIS/Makefile: %/shared/libfms.a $(coupled_AM2_LM3_SIS_files)
$(call all_builds,coupled_AM2_LM3_SIS2,Makefile): %/coupled_AM2_LM3_SIS2/Makefile: %/shared/libfms.a $(coupled_AM2_LM3_SIS2_files)

# TODO: Define path to shared as function?
$(call all_configs,Makefile): %/Makefile: %/path_names
	cd $(dir $@) && $(MKMF) \
		-t $(TEMPLATES)/$(SITE)-$(compiler).mk \
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

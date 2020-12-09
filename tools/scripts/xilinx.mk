#------------------------------------------------------------------------------
#                           ENVIRONMENT VARIABLES                              
#------------------------------------------------------------------------------

TEMP_DIR	= $(BUILD_DIR)/tmp
BINARY		= $(BUILD_DIR)/$(PROJECT_NAME).elf

#	WINDOWS
ifeq ($(OS), Windows_NT)

replace_heap = powershell \( \( Get-Content	-Path $3 -Raw \) 	\
		-Replace \'_HEAP_SIZE : $1\', \'_HEAP_SIZE : $2\' \) \| \
		Set-Content -Path $3

#	LINUX
else

replace_heap = sed -i "s/_HEAP_SIZE : $1/_HEAP_SIZE : $2/g"	$3

endif

ARCH = $(shell $(call read_file, $(BUILD_DIR)/tmp/arch.txt))

# Define the platform compiler switch
CFLAGS += -DXILINX_PLATFORM						\
	 -fdata-sections						\
	 -ffunction-sections 						\
	 -O2								\
	 -g3
# Xilinx's generated linker script path
LSCRIPT		:= $(BUILD_DIR)/app/src/lscript.ld
# Xilinx's generate bsp library path
LIB_PATHS	+= -L$(BUILD_DIR)/bsp/$(ARCH)/lib
# Xilinx's bsp include path
CFLAGS		+= -I$(BUILD_DIR)/bsp/$(ARCH)/include
################|--------------------------------------------------------------
################|                   Zynq                                       
################|--------------------------------------------------------------
ifeq (ps7_cortexa9_0,$(strip $(ARCH)))

CC := arm-none-eabi-gcc
AR := arm-none-eabi-ar

LD := $(CC)

CFLAGS += -mcpu=cortex-a9 						\
	  -mfpu=vfpv3 							\
	  -mfloat-abi=hard

LDFLAGS += -specs=$(BUILD_DIR)/app/src/Xilinx.spec 			\
	   -mfpu=vfpv3							\
 	   -mfloat-abi=hard 						\
	   -mcpu=cortex-a9						\
	   -Wl,-build-id=none

endif

################|--------------------------------------------------------------
################|                   ZynqMP                                     
################|--------------------------------------------------------------
ifeq (psu_cortexa53_0,$(strip $(ARCH)))

CC := aarch64-none-elf-gcc
AR := aarch64-none-elf-ar

LD := $(CC)

endif
################|--------------------------------------------------------------
################|                  Microblaze                                  
################|--------------------------------------------------------------
ifeq (sys_mb,$(strip $(ARCH)))

ifeq ($(OS), Windows_NT)
CC := mb-gcc
AR := mb-ar
else
CC := microblaze-xilinx-elf-gcc
AR := microblaze-xilinx-elf-ar
endif

LD := $(CC)

CFLAGS += -mcpu=cortex-a9 						\
	  -DXILINX -DMICROBLAZE						\
	  -DXILINX_PLATFORM						\
	  -mlittle-endian						\
	  -mxl-barrel-shift						\
	  -mxl-pattern-compare 						\
	  -mno-xl-soft-div						\
	  -mcpu=v11.0							\
	  -mno-xl-soft-mul						\
	  -mxl-multiply-high

LDFLAGS += -Xlinker --defsym=_HEAP_SIZE=0x100000 			\
	   -Xlinker --defsym=_STACK_SIZE=0x2000 			\
	   -mlittle-endian 						\
	   -mxl-barrel-shift						\
	   -mxl-pattern-compare						\
	   -mno-xl-soft-div						\
	   -mcpu=v11.0							\
	   -mno-xl-soft-mul						\
	   -mxl-multiply-high 						\
	   -Wl,--no-relax 						\
	   -Wl,--gc-sections 

endif

# Common xilinx libs
LIB_FLAGS += -Wl,--start-group,-lxil,-lgcc,-lc,--end-group

# Add the common include paths
CFLAGS += -I$(BUILD_DIR)/app/src

#Add more dependencies to $(BINARY) rule.
$(BINARY): $(TEMP_DIR)/arch.txt

PHONY += xilinx_run
xilinx_run: all
	xsdb $(PLATFORM_TOOLS)/upload.tcl\
		$(ARCH)\
		$(BUILD_DIR)/hw/system_top.bit\
		$(BINARY)\
		$(BUILD_DIR)/hw

PHONY += xilinx_update_srcs
xilinx_update_srcs:
ifeq 'y' '$(strip $(LINK_SRCS))'
	$(foreach dir,$(SRC_DIRS),\
		$(call mk_dir,$(dir $(BUILD_DIR)/app/src/$(call get_relative_path, $(dir))))\
		$(cmd_separator)\
		$(call make_dir_link,$(dir),\
		$(BUILD_DIR)/app/src/$(call get_relative_path, $(dir))) $(cmd_separator)) \
		echo Dir links created
	
	$(foreach file,$(FILES_OUT_OF_DIRS),\
		$(call mk_dir,$(dir $(BUILD_DIR)/app/src/$(call get_relative_path, $(file))))\
		$(cmd_separator)\
		$(call make_link,$(file),\
		$(BUILD_DIR)/app/src/$(call get_relative_path, $(file)))$(cmd_separator)) \
		echo File links created
else
	$(foreach file,$(SRCS) $(INCS), $(call copy_fun,$(file),$(BUILD_DIR)/app/src) &&) \
		echo Src files copied
endif

#do copy of HARDWARE to tmp is needed?
$(TEMP_DIR)/arch.txt: $(HARDWARE)
	$(call mk_dir,$(BUILD_DIR)/app $(BUILD_DIR)/app/src $(OBJECTS_DIR) $(TEMP_DIR))
	$(call copy_fun,$(HARDWARE),$(TEMP_DIR))
	xsct $(PLATFORM_TOOLS)/read_hdf.tcl $(TEMP_DIR) $(TEMP_DIR)/$(notdir $(HARDWARE))

xilinx_project: $(BUILD_DIR)/.bsp.target

PHONY += xilinx_project_build
xilinx_project_build: all
	xsct $(NO-OS)/tools/scripts/platform/xilinx/build_project.tcl $(WORKSPACE)


ADD_INCLUDE_PATHS=$(foreach dir, $(EXTRA_INC_PATHS),\
		sdk configapp -app app include-path $(dir);)
ADD_COMPILER_DEFINES = $(foreach flag, $(FLAGS_WITHOUT_D),\
		sdk configapp -app app define-compiler-symbols $(flag);)
ADD_LIBRARIES = $(foreach lib, $(EXTRA_LIBS_NAMES), \
		sdk configapp -app app libraries $(lib);)
ADD_LIBRARIES_PATH = $(foreach path, $(EXTRA_LIBS_PATHS), \
		sdk configapp -app app library-search-path $(path);)

ifeq ($(OS), Windows_NT)
UDPATE_TCL_CONTENT = setws $(WORKSPACE);$(ADD_INCLUDE_PATHS) $(ADD_COMPILER_DEFINES) $(ADD_LIBRARIES_PATH) $(ADD_LIBRARIES)
else
UDPATE_TCL_CONTENT = "setws $(WORKSPACE);$(ADD_INCLUDE_PATHS) $(ADD_COMPILER_DEFINES) $(ADD_LIBRARIES_PATH) $(ADD_LIBRARIES)"
endif

$(BUILD_DIR)/.bsp.target: $(TEMP_DIR)/arch.txt
	xsdk -batch -source $(PLATFORM_TOOLS)/create_project.tcl $(WORKSPACE) $(HARDWARE) $(ARCH)
	echo $(UDPATE_TCL_CONTENT) > $(TEMP_DIR)/update_sdk.tcl
	xsct $(TEMP_DIR)/update_sdk.tcl
ifeq ($(strip $(ARCH)),sys_mb)
	$(call replace_heap, 0x800, 0x100000, $(BUILD_DIR)/app/src/lscript.ld)
else
	$(call replace_heap, 0x2000, 0x100000, $(BUILD_DIR)/app/src/lscript.ld)
endif
	$(MAKE) xilinx_update_srcs
	$(call set_one_time_rule,$@)

clean_all: xilinx_clean_all

xilinx_clean_all:
	-$(call remove_dir,.Xil)
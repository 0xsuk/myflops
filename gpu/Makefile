RTL_DIR = rtl
TB_DIR  = tb
SIM_DIR = sim

RTL_SRC = \
	$(RTL_DIR)/gpu_pkg.sv \
	$(RTL_DIR)/fp32_adder.sv \
	$(RTL_DIR)/fetch_unit.sv \
	$(RTL_DIR)/decode_unit.sv \
	$(RTL_DIR)/alu.sv \
	$(RTL_DIR)/register_file.sv \
	$(RTL_DIR)/warp_scheduler.sv \
	$(RTL_DIR)/shared_memory.sv \
	$(RTL_DIR)/memory_controller.sv \
	$(RTL_DIR)/streaming_processor.sv \
	$(RTL_DIR)/gpu_top.sv

.PHONY: sim clean

CURDIR := $(shell pwd)

sim: $(RTL_SRC) $(TB_DIR)/tb_gpu_top.cpp
	verilator --cc --exe --trace --top-module gpu_top \
		-Wno-fatal \
		-Mdir $(SIM_DIR)/obj \
		$(RTL_SRC) $(CURDIR)/$(TB_DIR)/tb_gpu_top.cpp
	make -C $(SIM_DIR)/obj -f Vgpu_top.mk Vgpu_top
	cd $(SIM_DIR) && ./obj/Vgpu_top

clean:
	rm -rf $(SIM_DIR)/obj $(SIM_DIR)/gpu_test.vcd

# cocotb testbench: qlin dispatch programs on the QubiC distributed
# processor (RTL). QUBIC_PATH is a clone of
# gitlab.com/LBL-QubiC/distributed_processor; its venv must be first on PATH
# (cocotb, distproc). bench/run_qubic.py sets QLIN_DISPATCH_IN and
# QLIN_DISPATCH_OUT and runs `make`.
QUBIC_PATH ?= $(HOME)/dev/oss/qubic-distproc
SIM ?= verilator
TOPLEVEL_LANG ?= verilog
COMPILE_ARGS += -Wno-fatal
# Verilator 5 rejects hierarchical parameter values that 4.106 (the QubiC CI
# pin) accepts; 4.106 does not know the warning code.
ifeq ($(shell verilator --version | cut -d' ' -f2 | cut -d. -f1),5)
COMPILE_ARGS += -Wno-HIERPARAM
endif

VERILOG_SOURCES += $(QUBIC_PATH)/hdl/*.v
VERILOG_SOURCES += $(QUBIC_PATH)/hdl/*.sv
VERILOG_SOURCES += $(QUBIC_PATH)/hdl/*.vh
VERILOG_SOURCES += $(QUBIC_PATH)/sim_modules/*.sv
TOPLEVEL = toplevel_sim
MODULE = dispatch_qlin_tb

include $(shell cocotb-config --makefiles)/Makefile.sim

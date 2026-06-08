# ARMv7 SoC with INT8 Systolic NPU

A from-scratch ARMv7 system-on-chip written in VHDL-2008, targeting bare-metal C and eventual GDSII tapeout on SkyWater 130nm via the Efabless/OpenLane flow. Built as a deep technical learning project and portfolio piece — every module was designed, debugged, and verified by hand.

---

## What's in here

### CPU

A fully pipelined ARMv7 core with a classic 5-stage design: Fetch, Decode, Execute, Memory, Writeback. Not a soft-core wrapper — the pipeline, hazard unit, forwarding logic, and branch predictor were all built from scratch.

- **Hazard detection and forwarding** — handles load-use, MUL stalls, and LDM/STM multi-cycle stalls. `stall_all` gates the F/D register to prevent instruction skipping during multi-cycle operations.
- **Branch predictor** — reduces branch penalty on correctly predicted branches
- **Wallace tree multiplier** — multi-cycle hardware multiplier with a busy/valid handshake to the pipeline
- **Kogge-Stone adder** — parallel prefix adder on the critical accumulator path
- **Barrel shifter** — supports LSL, LSR, ASR, ROR inline with ALU operations
- **LDM/STM sequencer** — full support for ARM block load/store with pre/post-index, ascending/descending, and writeback modes
- **Interrupt system** — IRQ/FIQ with CPSR/SPSR save-restore, banked registers (IRQ: R13/R14, FIQ: R8-R14), ARM-standard vector table at `0x00000000`, and mode switching between USER/IRQ/FIQ/SVC

### NPU

A 32×32 INT8 output-stationary systolic array for matrix multiplication, integrated as an MMIO peripheral at `0x40000400`.

- **1024 processing elements** — each PE computes a signed INT8 MAC each cycle and accumulates into a 32-bit register
- **Diagonal skew injection** — two skew injectors align the A and B operand streams along the correct diagonal before they enter the array
- **4-state FSM controller** — `S_IDLE → S_COMPUTE (32 cycles) → S_DRAIN (63 cycles) → S_STORE (32 cycles)`
- **Ping-pong double buffering** — the CPU can load the next tile into one bank while the array computes on the other
- **IRQ on completion** — `done` pulses into the CPU interrupt line so the ISR handles result readout instead of polling

The NPU sits behind an `npu_wrapper` that handles the MMIO register file, tile load sequencing, and result readback. The CPU writes matrices byte-by-byte via MMIO, asserts start, and gets interrupted when results are ready.

### SoC fabric

- **MMIO bus** — routes the CPU's memory stage to either data memory or one of five peripheral slots based on the upper address bits
- **Single 100MHz clock domain** throughout

---

## Memory map

| Address range | Peripheral |
|---|---|
| `0x00010000 – 0x000103FF` | Data memory (1KB) |
| `0x40000000 – 0x400000FF` | IRQ controller (P0) |
| `0x40000100 – 0x400001FF` | UART (P1, stub) |
| `0x40000200 – 0x400002FF` | Timer (P2, stub) |
| `0x40000300 – 0x400003FF` | GPIO (P3, stub) |
| `0x40000400 – 0x400004FF` | NPU accelerator (P4) |

### NPU register map (offset from `0x40000400`)

| Offset | Register | Description |
|---|---|---|
| `0x00` | `NPU_CTRL` | `[0]` start, `[1]` reset, `[2]` busy (RO), `[3]` done latch (W1C) |
| `0x08` | `NPU_SEL` | `[0]` matrix select: 0=A, 1=B |
| `0x0C` | `NPU_WADDR` | Flat byte index into matrix (row×32 + col) |
| `0x10` | `NPU_WDATA` | Write one INT8 byte, triggers buffer write |
| `0x14` | `NPU_RADDR` | Result index to read |
| `0x18` | `NPU_RESULT` | 32-bit signed accumulator output (RO) |

---

## File map

```
top.vhd                  — SoC top level
datapath.vhd             — 5-stage pipeline, LDM/STM sequencer, MMIO wiring
controlunit.vhd          — decode, condition logic, interrupt control
regfile.vhd              — banked register file with IRQ/FIQ mode support
alu.vhd                  — ALU with Kogge-Stone adder and barrel shifter
hazardunit.vhd           — stall and flush logic
branchp.vhd              — branch predictor
dcache.vhd               — 4-way set-associative write-back L1 data cache
imem.vhd                 — instruction memory
mmiobus.vhd              — MMIO address decoder (P0–P4)
wallacemul.vhd           — Wallace tree multiplier
condlogic.vhd            — ARM condition code evaluation
maindecoder.vhd          — main instruction decoder
aludecoder.vhd           — ALU control decoder
pclogic.vhd              — PC update logic

npu_wrapper.vhd          — MMIO ↔ NPU bridge, tile load FSM, result readback
accelerator_top.vhd      — NPU top: FSM + skew injectors + systolic array
controller_fsm.vhd       — 4-state NPU sequencer
systolic_array.vhd       — 32×32 PE grid
pe.vhd                   — single INT8 MAC processing element
skew_injector.vhd        — diagonal delay injector
ping_pong_buffer.vhd     — double-buffer wrapper over two SRAM banks
sram_1r1w.vhd            — behavioural 1R1W SRAM (replace with foundry macro at tapeout)
systolic_pkg.vhd         — shared types and constants for the NPU
```

---

## Toolchain

- **VHDL-2008** throughout — no vendor-specific primitives
- **Vivado** — used for behavioural simulation and synthesis checks (not targeting FPGA primitives)
- **GHDL** — fast behavioural simulation for the NPU (the 32×32 array is too large for comfortable FPGA synthesis)
- **arm-none-eabi-gcc** — bare-metal C toolchain for software targeting the CPU
- **SkyWater 130nm PDK + Efabless/OpenLane** — tapeout flow (planned)

---

## What's next

- UART, SPI, I2C peripheral implementations
- L2 unified cache
- AHB-Lite bus fabric replacing the current MMIO bus
- GHDL simulation and testbench for the full NPU integration
- OpenLane tapeout prep (likely targeting Tiny Tapeout with a smaller 8×8 NPU variant)

---

## Notes

This is an ASIC-oriented design. `sram_1r1w.vhd` is a behavioural placeholder — at physical implementation it gets replaced with a foundry SRAM compiler macro. The reset style is synchronous active-high throughout. The 32×32 systolic array synthesizes to ~115K LUTs and ~134K FFs on FPGA fabric, which is expected and fine — the ASIC standard cell implementation is a completely different story.

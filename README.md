# ARMv7 SoC with Heterogeneous INT8 NPU Cluster

A from-scratch ARMv7 system-on-chip written in VHDL-2008, targeting bare-metal C and eventual GDSII tapeout on SkyWater 130nm via the Efabless/OpenLane flow. Built as a deep technical portfolio project covering CPU microarchitecture, custom AI accelerator design, clock domain crossing, and hardware scheduling.

---

## Architecture Overview

The SoC integrates a pipelined ARMv7 CPU with a heterogeneous multi-NPU cluster connected over a hardware dispatch engine. The NPU cluster contains six systolic arrays of varying sizes, each running its own independent clock domain, with all inter-domain crossings handled by correct CDC primitives.

---

## CPU

A fully pipelined ARMv7 core with a 5-stage design: Fetch, Decode, Execute, Memory, Writeback. 

- **Hazard detection and forwarding** — handles load-use, MUL stalls, and LDM/STM multi-cycle stalls. `stall_all` gates the F/D register to prevent instruction skipping during multi-cycle operations
- **Branch predictor** — reduces branch penalty on correctly predicted branches
- **Wallace tree multiplier** — multi-cycle hardware multiplier with a busy/valid handshake to the pipeline
- **Kogge-Stone adder** — parallel prefix adder on the critical accumulator path
- **Barrel shifter** — supports LSL, LSR, ASR, ROR inline with ALU operations
- **LDM/STM sequencer** — full support for ARM block load/store with pre/post-index, ascending/descending, and writeback modes
- **Interrupt system** — IRQ/FIQ with CPSR/SPSR save-restore, banked registers (IRQ: R13/R14, FIQ: R8–R14), ARM-standard vector table at `0x00000000`, and mode switching between USER/IRQ/FIQ/SVC
- **4-way set-associative L1 data cache** — write-back with pseudo-LRU replacement, 4 sets

---

## NPU Cluster

A heterogeneous array of six INT8 systolic arrays, each operating in its own clock domain. A hardware tile planner and dispatch engine schedule work across the cluster with no software involvement after job submission.

### Array instances

| ID | Size | Clock |
|---|---|---|
| 0 | 64×64 | 200 MHz |
| 1 | 32×32 | 150 MHz |
| 2 | 16×16 | 133 MHz |
| 3 | 8×8 | 100 MHz |
| 4 | 4×4 A | 100 MHz |
| 5 | 4×4 B | 100 MHz |

All six arrays are parameterized from a single `accelerator_top` entity via a `SIZE` generic. The systolic array uses output-stationary dataflow with diagonal skew injection on both A and B operand streams.

**Sustained throughput (32×32 array at 100 MHz):** 25.8 GMAC/s (32,768 MACs / 127 cycles)

### Tile scheduling

The CPU writes a single job descriptor (M, K, N dimensions and matrix base addresses) into MMIO registers and asserts `job_start`. The hardware tile planner then:

1. Computes the full output tile decomposition using a fill-big-first policy — interior 64×64 blocks are scheduled first, followed by edge strips and the corner remainder
2. Assigns each tile to the appropriate NPU based on tile dimensions
3. Writes the complete schedule into a 65,536-entry schedule RAM before any compute begins (static pre-allocation, not real-time scheduling)

The dispatch FSM then walks the schedule RAM and issues tile descriptors to each NPU's command FIFO. Each descriptor carries source/destination addresses, tile coordinates, K-slice index, and an `is_last_k` flag.

### CDC infrastructure

Every NPU clock domain is fully isolated with correct CDC primitives:

- **`async_fifo`** — parameterized dual-clock FIFO with Gray-coded read/write pointers and 2FF synchronizers on each pointer crossing. Used on the command path (CPU clock → NPU clock), carrying 136-bit tile descriptors
- **`cdc_pulse_sync`** — toggle-based pulse synchronizer for the done path (NPU clock → CPU clock). Toggle-based rather than level-based to guarantee capture regardless of the src/dst clock ratio
- **`rst_sync`** — asynchronous assert, synchronous deassert reset synchronizer, one instance per NPU clock domain
- **`cdc_sync`** — standard 2FF synchronizer for slow-changing control signals

### Per-NPU tile sequencer

Each NPU has a 2-state FSM (SEQ_IDLE / SEQ_WAIT) running in its own clock domain. It reads one descriptor from the command FIFO, fires a single-cycle `start` pulse to the accelerator, and waits for `done` before reading the next descriptor. This prevents re-entry and ensures the systolic array is never restarted mid-computation.

---

## SoC Fabric

- **MMIO bus** — routes the CPU memory stage to data memory or one of five peripheral slots based on upper address bits
- **NPU wrapper** — bridges the MMIO bus to the original 32×32 NPU, handles tile load sequencing and result readback via ping-pong buffers

---

## Memory Map

| Address range | Peripheral |
|---|---|
| `0x00010000 – 0x000103FF` | Data memory (1KB) |
| `0x40000000 – 0x400000FF` | IRQ controller (P0) |
| `0x40000100 – 0x400001FF` | UART (P1, stub) |
| `0x40000200 – 0x400002FF` | Timer (P2, stub) |
| `0x40000300 – 0x400003FF` | GPIO (P3, stub) |
| `0x40000400 – 0x400004FF` | NPU accelerator (P4) |

### NPU MMIO register map (offset from `0x40000400`)

| Offset | Register | Description |
|---|---|---|
| `0x00` | `NPU_CTRL` | `[0]` start, `[1]` reset, `[2]` busy (RO), `[3]` done latch (W1C) |
| `0x08` | `NPU_SEL` | `[0]` matrix select: 0=A, 1=B |
| `0x0C` | `NPU_WADDR` | Flat byte index into matrix (row×32 + col) |
| `0x10` | `NPU_WDATA` | Write one INT8 byte, triggers buffer write |
| `0x14` | `NPU_RADDR` | Result index to read |
| `0x18` | `NPU_RESULT` | 32-bit signed accumulator output (RO) |

---

## File Map

```
soc/
├── top.vhd
├── rtl/
│   ├── cpu/
│   │   ├── alu.vhd
│   │   ├── aludecoder.vhd
│   │   ├── branchp.vhd
│   │   ├── condlogic.vhd
│   │   ├── controlunit.vhd
│   │   ├── datapath.vhd
│   │   ├── hazardunit.vhd
│   │   ├── maindecoder.vhd
│   │   ├── pclogic.vhd
│   │   ├── regfile.vhd
│   │   └── wallacemul.vhd
│   ├── npu/
│   │   ├── accelerator_top.vhd
│   │   ├── controller_fsm.vhd
│   │   ├── dispatch_fsm.vhd
│   │   ├── npu_cluster_top.vhd
│   │   ├── npu_wrapper.vhd
│   │   ├── pe.vhd
│   │   ├── skew_injector.vhd
│   │   ├── systolic_array.vhd
│   │   ├── systolic_pkg.vhd
│   │   └── tile_planner.vhd
│   ├── fabric/
│   │   ├── async_fifo.vhd
│   │   ├── cdc_pulse_sync.vhd
│   │   ├── cdc_sync.vhd
│   │   ├── mmiobus.vhd
│   │   └── rst_sync.vhd
│   └── memory/
│       ├── dcache.vhd
│       ├── imem.vhd
│       ├── sched_ram.vhd
│       └── sram_1r1w.vhd
│       └── ping_pong_buffer.vhd
└── tb/
    ├── tb_alu_ks.vhd
    ├── tb_alu_shift.vhd
    ├── tb_bp.vhd
    ├── tb_irq.vhd
    ├── tb_ldmstm.vhd
    ├── tb_mmio_bus.vhd
    ├── tb_npu_cluster.vhd
    ├── tb_npu2_solo.vhd
    ├── tb_top.vhd
    └── tb_wallacemul.vhd
```

---

## Verification

### CPU testbenches (Vivado)
- `tb_top` — full pipeline: arithmetic, branching, load/store, forwarding
- `tb_ldmstm` — LDM/STM block transfer with writeback and edge cases
- `tb_irq` — IRQ/FIQ entry, CPSR/SPSR save-restore, ISR return

### NPU testbenches (GHDL + Vivado)
- `tb_npu_cluster` — submits an (80×48)×(48×72) INT8 GEMM to the full heterogeneous cluster. Verifies the 64×64 interior tile numerically (4096 elements) across a 200MHz/100MHz CDC boundary. `job_done` asserts at cpu cycle 531
- `tb_npu2_solo` — tests the 16×16 systolic array standalone across three cases: K=SIZE (exact), K<SIZE (zero-padded), and identity-style matrices. All cases pass

---

## STA & Area

### PE synthesis area (Sky130 HD, TT 1.80V, 25°C, pre-layout): 4590.65 µm² total cell area

- Sequential area: 960.92 µm² (20.93%), with 48 dfxtp flops
- Total mapped cells: 550

### PE timing (OpenSTA, same corner, pre-layout):

- Constraint: 10.0 ns clock period (100 MHz)
- Critical path arrival: 9.4507 ns
- Required time: 9.9129 ns
- Slack: +0.4622 ns (MET)
- Estimated pre-layout Fmax from critical path: ~105.8 MHz

---

## Toolchain

- **VHDL-2008** throughout — no vendor-specific primitives
- **Vivado 2025.2** — behavioural simulation and synthesis checks (not targeting FPGA primitives)
- **GHDL** — fast behavioural simulation for the NPU cluster
- **SkyWater 130nm PDK + Efabless/OpenLane** — tapeout flow (planned)

---

## What's Next

- AHB-Lite bus fabric replacing the current MMIO bus
- Dual-core CPU with shared L2 cache
- OpenLane tapeout prep — likely targeting Tiny Tapeout with an 8×8 NPU variant
- ONNX-to-MMIO tile scheduler (Python) for full-stack demo

---

## Notes

This is an ASIC-oriented design. `sram_1r1w.vhd` is a behavioural placeholder — at physical implementation it gets replaced with a foundry SRAM compiler macro. Reset is synchronous active-high throughout except at CDC boundaries where `rst_sync` handles the domain crossing correctly. The 32×32 systolic array synthesizes to ~115K LUTs and ~134K FFs on FPGA fabric — expected and intentional, the ASIC standard cell implementation is a completely different story.

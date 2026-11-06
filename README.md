# Ethernet 1 Gb/s MAC/PHY IP (Verilog-2001)

Synthesizable, full-duplex Ethernet MAC with GMII/MII PHY pins and AXI4-Stream host
interfaces, plus fifteen self-checking testbenches and an end-to-end pin-to-pin loopback.

`1 Gb/s = 125 MHz x 8 bits` — one octet per GMII clock.
`10/100 Mb/s` by the same datapath through 4-bit MII, selected by `speed_select`.

**Status: simulation-verified. Not yet synthesised onto a board.**

---

## Repository layout

```
ethernet_mac_top.v          top level: TX + RX + host FIFOs + optional internal loopback
ethernet_mac_loopback_tb.v  end-to-end bench (TX pins -> RX pins, 106 checks)
TX/                         8 files: transmit path + shared CRC engine
RX/                         6 files: receive path
1G_MAC_PHY_BTP_PPT.pptx     project slides
ETHERNET_1Gbs_MAC_PHY_REPORT.pdf   full report (architecture, verification, handover)
```

Every `.v` file is Verilog-2001 and uses `` `default_nettype none ``.

---

## Modules

| File | Module | Role |
|---|---|---|
| `TX/tx_mac_controller.v` | `tx_mac_controller` | Main TX FSM: AXI4-Stream in, frame assembly, drop/underrun handling |
| `TX/tx_fifo.v` | `tx_fifo` | 2048 x 8 host-domain FIFO (in-flight capacity = DEPTH + 1) |
| `TX/tx_padding.v` | `tx_padding` | Pads short frames to 60 bytes |
| `TX/tx_fcs.v` | `tx_fcs` | Appends the 32-bit FCS |
| `TX/crc32_parallel.v` | `crc32_parallel` | CRC-32 engine, 8 bits per cycle (shared with RX) |
| `TX/tx_preamble.v` | `tx_preamble` | 7 x `0x55` preamble + `0xD5` SFD |
| `TX/tx_ifg.v` | `tx_ifg` | 96-bit-time interframe gap timer (12 cycles GMII, 24 MII) |
| `TX/tx_gmii_mii.v` | `tx_gmii_mii` | Egress shifter: GMII 8-bit / MII 4-bit |
| `RX/rx_mac_controller.v` | `rx_mac_controller` | RX FSM: frame verdict, length and error pulses |
| `RX/rx_gmii_mii.v` | `rx_gmii_mii` | Ingress: GMII pass-through, MII nibble pack |
| `RX/rx_preamble.v` | `rx_preamble` | SFD hunt with a sliding window (`PRE_MAX`) |
| `RX/rx_fcs.v` | `rx_fcs` | CRC check, FCS strip, error flag |
| `RX/rx_fifo.v` | `rx_fifo` | 2048 x 8 receive FIFO |
| `RX/crc32_parallel.v` | `crc32_parallel` | Same engine as `TX/` (one copy only when compiling) |

Benches: 9 in `TX/`, 5 in `RX/`, 1 at the root (`ethernet_mac_loopback_tb.v`).

---

## Quick start

Requires Icarus Verilog (`iverilog` + `vvp`); the OSS CAD Suite bundle is easiest on
Windows. On Windows OSS CAD Suite, **both** `bin` and `lib` must be on `PATH` or `vvp`
cannot find its DLLs:

```bash
export PATH=/d/oss-cad-suite/bin:/d/oss-cad-suite/lib:$PATH
```

### One bench

```bash
cd TX
iverilog -g2005 -o sim_tx_fcs_tb.vvp tx_fcs_tb.v tx_fcs.v crc32_parallel.v
vvp sim_tx_fcs_tb.vvp
```

### Whole design (top level)

```bash
iverilog -g2005 -o mac.vvp ethernet_mac_top.v \
  TX/tx_mac_controller.v TX/tx_fifo.v TX/tx_padding.v TX/tx_fcs.v \
  TX/tx_preamble.v TX/tx_ifg.v TX/tx_gmii_mii.v TX/crc32_parallel.v \
  RX/rx_mac_controller.v RX/rx_gmii_mii.v RX/rx_preamble.v RX/rx_fcs.v RX/rx_fifo.v
```

### End-to-end loopback (the headline result)

```bash
iverilog -g2005 -o loopback.vvp ethernet_mac_loopback_tb.v \
  TX/tx_mac_controller.v TX/tx_fifo.v TX/tx_padding.v TX/tx_fcs.v \
  TX/tx_preamble.v TX/tx_ifg.v TX/tx_gmii_mii.v TX/crc32_parallel.v \
  RX/rx_mac_controller.v RX/rx_gmii_mii.v RX/rx_preamble.v RX/rx_fcs.v RX/rx_fifo.v
vvp loopback.vvp
# -> RESULT : 106 passed, 0 failed, 106 total
# -> ethernet_mac_loopback_tb : ALL CHECKS PASS
```

`bash run_all.sh` runs all fifteen benches and writes `run_logs/<bench>.log` plus a summary.
Note that `TX/crc32_parallel.v` and `RX/crc32_parallel.v` are the same module — never pass
both to `iverilog`, and never compile with `TX/*.v RX/*.v` wildcards.

### Synthesis (Yosys)

`TX/synth.ys` currently elaborates `tx_ifg` only. Point `read_verilog` / `hierarchy -top`
at `ethernet_mac_top` and list all thirteen unique files to synthesise the whole MAC.

---

## What is verified

| Area | State |
|---|---|
| Unit benches (preamble, FCS, padding, IFG, FIFOs, GMII/MII, controllers) | pass, self-checking |
| Pin-to-pin loopback: framing, padding, CRC, corruption detection, gap | pass (106 checks) |
| CRC-32 vs. the standard polynomial, all single-bit errors dropped on the wire | pass |
| 10/100 MII path | pass against a behavioural model |
| Synthesis / timing / board bring-up | **not done** |

The loopback bench instantiates the transmit and receive chains directly, not
`ethernet_mac_top`; the top level is elaborated but has no dedicated bench.

---

## Rules that carry the design

Read these before changing anything — each one is a place where a plausible "clean-up"
breaks the design.

1. **Zero-slack FCS handoff.** The FCS module must accept a beat in the same cycle the
   controller releases it. Inserting a register here silently corrupts every frame.
2. **Gray-code CDC only.** `rx_frame_len_out` crosses from `rx_clk` to the host domain as
   Gray code. A binary bus with two flops will glitch on multi-bit transitions.
3. **RX contiguity is assumed.** The receiver expects an unbroken byte stream inside a
   frame; there is no per-byte re-synchronisation.
4. **The gap is longer than nominal.** Measured 120 bit times on GMII and 108 on MII
   instead of 96, because the timer counts from a registered `ifg_start` and the frame
   tail is not counted. Still legal Ethernet — but do not "simplify" the timer without
   re-measuring.
5. **One frame in flight.** The FIFO holds DEPTH + 1 entries; back-to-back frames without
   a gap will drop the second.
6. **Whole-frame verdict.** A frame is delivered or dropped as a unit; there is no
   partial-frame flush to the host.

---

## Key parameters (`ethernet_mac_top`)

| Parameter | Default | Meaning |
|---|---|---|
| `DATA_W` | 8 | Datapath width (8 only, in bits per cycle) |
| `TX_FIFO_ADDR_W` / `RX_FIFO_ADDR_W` | 11 | 2048-entry FIFOs |
| `MIN_FRAME_LEN` | 60 | Pad target, bytes |
| `MAX_FRAME_LEN` | 1514 | Maximum accepted frame, bytes |
| `PREAMBLE_LEN` | 7 | `0x55` bytes before the SFD |
| `PREAMBLE_BYTE` / `SFD_BYTE` | `0x55` / `0xD5` | Wire constants |
| `IFG_BIT_TIMES` | 96 | Interframe gap |
| `ERR_CYCLES` | 2 | `tx_er` assertion width |
| `PRE_MAX` | 32 | SFD search window |
| `INT_LOOPBACK` | 1 | Internal TX-to-RX loopback |

---

## Known limitations

- Full duplex only: no carrier sense, collision detection or backoff.
- No PAUSE flow control, no MDIO management, no address filtering, no VLAN, no statistics.
- MII is verified against a behavioural model, not a real PHY.
- No synthesis results, no timing closure, no board bring-up.
- `DATA_W` other than 8 and jumbo frames are unsupported.

## Documentation

`ETHERNET_1Gbs_MAC_PHY_REPORT.pdf` covers the architecture, module-by-module design, the
verification strategy and results, and a handover chapter with rebuild commands, the
acceptance milestones and the path to hardware.

## License

Add a license before reuse. Until then, all rights reserved by the author.

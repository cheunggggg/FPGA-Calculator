# FPGA Calculator — Basys3 / Verilog

A hardware calculator implemented in Verilog for the Digilent Basys3 FPGA board. Supports nine arithmetic operations across two signed 6-bit inputs, with results displayed on up to **six seven-segment digits** (four onboard + two via PmodSSD) and a negative-result LED indicator.
This was created as a final project for COM SCI M152A. WINTER 2025

---

## Features

| Operation | Trigger | Notes |
|-----------|---------|-------|
| Add | `BTNL` (T18) | |
| Subtract | `BTNR` (W19) | |
| Multiply | `BTNU` (T17) | |
| Divide | `BTND` (U17) | Truncates decimals; divide-by-zero → `9999` |
| Equals | `BTNC` (U18) | Executes the selected operation |
| Modulo | Ext `BTN0` (JB) | Mod-by-zero → `9999` |
| Power | Ext `BTN1` (JB) | Negative exponent → `9998`; `x^0 = 1` |
| Negate | Ext `BTN2` (JB) | Negates the first input |
| Reset | Ext `BTN3` (JB) | Clears display and state to `000000` |

- **6-digit output** — four digits on the Basys3 display + two digits on a PmodSSD connected to JA/JXADC
- **Negative results** — `LD15` lights up; the display shows the absolute value
- **Overflow handling** — results larger than 999,999 wrap to the lower six digits
- **Button debouncing** — 20-bit counter samples inputs at a slower rate and detects rising edges to prevent spurious triggers
- **100 MHz clock**, display refresh at 500 Hz with time-multiplexed anode selection

---

## Hardware Requirements

- Digilent **Basys3** FPGA board (Artix-7)
- **PmodSSD** connected to **JA** and **JXADC** (two additional digits)
- External button module connected to **JB** (BTN0–BTN3)
- Vivado 2018+ (note: XDC definitions require version-specific syntax)

---

## Input Mapping

### Switches
| Switches | Function |
|----------|----------|
| SW0–SW5 | First operand (6-bit binary) |
| SW6–SW11 | Second operand (6-bit binary) |
| SW12 | Sign bit of first operand |
| SW13 | Sign bit of second operand |

Numbers are read as 7-bit two's complement values (`{sign, 6-bit magnitude}`), giving a range of **−64 to +63** per operand.

---

## Module Overview

```
Calculator.v
├── Calculator          — Top-level: input handling, debouncing, arithmetic, display control
├── DisplayController   — Converts a 4-bit digit (0–9) to 7-segment patterns
│                         for both the onboard display (active-low) and PmodSSD (active-high)
└── DisplaySSD          — Multiplexes digit5 and digit6 onto the two-digit PmodSSD
                          using a clock-driven refresh counter and CAT select signal
```

### `Calculator`
- Reads SW and button inputs
- Debounces all five onboard buttons and four external buttons via a 20-bit counter
- Detects rising edges to latch the selected operation
- On `BTNC` (Equals), executes the operation with a `case` statement
- Power is computed iteratively with a state machine (`power_calculating` flag)
- Extracts six decimal digits from the 32-bit signed result via modulo/division
- Drives the four onboard anode-multiplexed digits at 500 Hz
- Instantiates `DisplaySSD` for the upper two digits

### `DisplayController`
- Pure combinational; maps a 4-bit value to both `segOut` (active-low, onboard) and `SSD` (active-high, PmodSSD)

### `DisplaySSD`
- Alternates between `digit5` and `digit6` on each rising edge of its internal refresh counter
- Drives `CAT` to select which of the two PmodSSD digits is active

---

## Error Codes

| Code | Meaning |
|------|---------|
| `9999` | Division or modulo by zero |
| `9998` | Negative exponent (not supported) |

---

## Known Limitations

- Input range is **−64 to +63** per operand (6-bit + sign)
- Results over **999,999** silently wrap (lower six digits kept)
- Division and power results are **integer only** — decimals are truncated
- No PmodKYPD support (found unreliable in testing; switches used instead)

---

## Authors

Brandon Cheung, Maddox Yu

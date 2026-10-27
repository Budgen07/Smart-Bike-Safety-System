# Smart Bike Safety System using BBC micro:bit v2

## Project Overview

A real-time bike safety controller implemented in **ARM Thumb-2 Assembly** on the BBC micro:bit v2 (nRF52833 Cortex-M4). The system uses onboard sensors and peripherals to detect riding state and alert the rider of dangerous conditions.

### System Behavior

| State | Trigger | LED Pattern | Sound | Exit |
|-------|---------|-------------|-------|------|
| **NORMAL** | Default / riding | Small diamond ◇ | Silent | Tilt → BRAKE, Impact → ACCIDENT |
| **BRAKE** | Y-axis tilt exceeds threshold | Rectangle □ (stop sign) | Silent | Tilt normal → NORMAL, Impact → ACCIDENT |
| **ACCIDENT** | Extreme acceleration spike | Flashing X ✕ | 1kHz alarm beep | Button A (acknowledge) |

### Button Controls

| Button | Action |
|--------|--------|
| **A** | Reset/acknowledge accident → return to NORMAL |
| **B** | Cycle sensitivity: LOW → MEDIUM → HIGH → LOW |
| **A+B** | Manual test mode: force ACCIDENT state |

---

## File Structure

```
smart_bike_safety/
├── constants.inc    ← Hardware register definitions (shared header)
├── main.S           ← Vector table, reset handler, state machine
├── interrupts.S     ← GPIOTE button interrupt handlers
├── sensor.S         ← I2C (TWIM) + accelerometer driver
├── display.S        ← LED matrix multiplexing engine
├── sound.S          ← Speaker alarm generation
├── linker.ld        ← Memory layout for nRF52833
├── Makefile         ← Build automation
└── README.md        ← This file
```

---

## Architecture Concepts Demonstrated

### 1. Memory-Mapped I/O

Every hardware peripheral is controlled by reading/writing to specific memory addresses. There are no special I/O instructions — standard `LDR`/`STR` instructions access hardware registers.

**Key addresses (from nRF52833 datasheet + Microbit_Reference.pdf):**

| Peripheral | Base Address | Example Register |
|-----------|-------------|-----------------|
| GPIO Port 0 | `0x50000000` | PIN_CNF[15] = `0x5000073C` |
| GPIO Port 1 | `0x50000300` | PIN_CNF[5] = `0x50000A14` |
| TWIM0 (I2C) | `0x40003000` | ENABLE = `0x40003500` |
| GPIOTE | `0x40006000` | CONFIG[0] = `0x40006510` |
| RNG | `0x4000D000` | VALUE = `0x4000D508` |

**Example — turning on an LED at (ROW3, COL1):**
```arm
@ COL1 = P0.28, ROW3 = P0.15  (from Microbit_Reference.pdf)
@ Set column HIGH (anode):
ldr r0, =0x50000508     @ GPIO_P0_OUTSET
ldr r1, =(1 << 28)      @ Pin 28 bitmask
str r1, [r0]             @ Memory-mapped write → hardware pin goes HIGH

@ Set row LOW (cathode):
ldr r0, =0x5000050C     @ GPIO_P0_OUTCLR
ldr r1, =(1 << 15)      @ Pin 15 bitmask
str r1, [r0]             @ LED at (ROW3, COL1) lights up!
```

### 2. Interrupt Handling

Buttons use **hardware interrupts** instead of polling (more CPU-efficient):

```
Button press → GPIOTE detects falling edge
            → Hardware generates IRQ6
            → CPU auto-saves registers to stack (context switch)
            → CPU jumps to ISR via vector table[22] (offset 0x58)
            → ISR sets flag in RAM
            → CPU auto-restores registers
            → Main loop checks flag asynchronously
```

**Key components:**
- **GPIOTE**: Peripheral that monitors GPIO pin transitions
- **NVIC**: CPU-internal interrupt controller (enables/disables IRQ lines)
- **Vector Table**: 23-entry table at address 0x00 mapping IRQs to handlers
- **EXC_RETURN**: Special value in LR that triggers exception return sequence

### 3. Sensor Data Handling

The LSM303AGR accelerometer communicates via I2C (TWIM peripheral with EasyDMA):

```
CPU writes register address to RAM buffer
    → TWIM DMA sends buffer over I2C SCL/SDA
    → Accelerometer responds with 6 data bytes
    → TWIM DMA stores response in RAM buffer
    → CPU reads and processes results
```

Data processing pipeline:
```
Raw I2C bytes → Extract high bytes → Sign-extend (SXTB instruction)
             → Compute |X|+|Y|+|Z| → Compare against thresholds
             → State transition decision
```

### 4. State Machine Control Logic

Three states with defined transitions, implemented as an assembly-level state machine:

```
                    ┌──────────────────────┐
                    │                      │
          tilt>thresh             impact>thresh
                    │                      │
    ┌────────┐    ┌─┴──────┐    ┌──────────┴─┐
    │ NORMAL ├───►│ BRAKE  ├───►│  ACCIDENT   │
    │   ◇    │◄───┤   □    │    │  ✕ + beep   │
    └────────┘    └────────┘    └──────┬──────┘
         ▲         tilt<thresh         │
         │                             │
         └─────── Button A ────────────┘
```

---

## Build Instructions

### Prerequisites

Install the ARM GNU Embedded Toolchain:

```bash
# macOS (Homebrew)
brew install --cask gcc-arm-embedded
# or
brew install arm-none-eabi-gcc

# Ubuntu/Debian
sudo apt install gcc-arm-none-eabi

# Windows
# Download from: https://developer.arm.com/downloads/-/gnu-rm
```

Verify installation:
```bash
arm-none-eabi-as --version
```

### Building

```bash
cd smart_bike_safety/

# Build the hex file
make

# Or step by step:
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -g -I. -o main.o main.S
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -g -I. -o display.o display.S
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -g -I. -o sensor.o sensor.S
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -g -I. -o interrupts.o interrupts.S
arm-none-eabi-as -mcpu=cortex-m4 -mthumb -g -I. -o sound.o sound.S
arm-none-eabi-ld -T linker.ld -o smart_bike.elf main.o display.o sensor.o interrupts.o sound.o
arm-none-eabi-objcopy -O ihex smart_bike.elf smart_bike.hex
```

### Flashing to micro:bit

The micro:bit appears as a USB drive named `MICROBIT`:

```bash
# macOS
make flash
# or: cp smart_bike.hex /Volumes/MICROBIT/

# Linux
make flash-linux
# or: cp smart_bike.hex /media/$USER/MICROBIT/

# Windows
# Copy smart_bike.hex to the MICROBIT drive in File Explorer
```

The micro:bit will automatically restart and run the program.

### Generating Disassembly (for debugging)

```bash
make disasm
# Creates smart_bike.lst with full disassembly
```

---

## Testing Plan

### Step 1: Basic Boot Test
1. Flash `smart_bike.hex` to the micro:bit
2. **Expected**: Small diamond pattern ◇ appears on LED matrix (NORMAL state)
3. **Verify**: The diamond pattern should be steady, not flickering

### Step 2: Brake Detection (Tilt Test)
1. Hold the micro:bit flat (horizontal)
2. Slowly tilt the board backward (away from you, ~30-45°)
3. **Expected**: LED changes to rectangle pattern □ (BRAKE state)
4. Return to flat position
5. **Expected**: LED returns to diamond pattern ◇ (NORMAL state)

### Step 3: Accident Detection (Impact Test)
1. Hold the micro:bit in hand
2. Give it a sharp shake or sudden jolt
3. **Expected**: LED shows flashing X pattern ✕ with alarm beep
4. Press **Button A** (left button)
5. **Expected**: Alarm stops, returns to diamond pattern ◇

### Step 4: Manual Test Mode
1. Press **Button A + Button B** simultaneously
2. **Expected**: Immediately enters ACCIDENT state (flashing X + beep)
3. Press **Button A** to reset
4. **Expected**: Returns to NORMAL state

### Step 5: Sensitivity Adjustment
1. Press **Button B** (right button)
2. **Expected**: Display briefly shows "M" (Medium → switching to High)
3. Press **Button B** again
4. **Expected**: Display briefly shows "H" (High → switching to Low)
5. Press **Button B** again
6. **Expected**: Display briefly shows "L" (Low → switching to Medium)
7. **Verify**: At HIGH sensitivity, smaller tilts trigger BRAKE state

### Step 6: Sound Test
1. Enter ACCIDENT state (via shake or A+B buttons)
2. **Expected**: ~1kHz beep audible from onboard speaker
3. **Verify**: Beep alternates with silence (intermittent alarm)
4. Press Button A → beep should stop immediately

---

## Debugging Tips

### No LEDs visible?
- Check that the micro:bit is powered (USB or battery)
- Verify the hex file was fully copied (wait for the MICROBIT drive to finish writing)
- Try re-flashing; the board should auto-restart
- Check `make disasm` output to verify vector table is at address 0x00

### LEDs flickering or dim?
- The display_refresh timing may need adjustment
- Try increasing the per-column delay from 2ms to 3ms in `display.S`
- Check that all LED pin configurations are correct in `gpio_init`

### Buttons not responding?
- Verify GPIOTE configuration matches the pin numbers (A=P0.14, B=P0.23)
- Check that NVIC interrupt is enabled (bit 6 of ISER0)
- Ensure `cpsie i` is called to enable global interrupts
- Try adding a DSB instruction after clearing GPIOTE events (nRF52 errata workaround)

### Accelerometer not working?
- I2C initialization order matters: TWIM must be enabled AFTER setting pin select
- Verify accelerometer I2C address is 0x19 (SA0 high on micro:bit v2)
- Check that CTRL_REG1_A is properly configured (0x57 = 100Hz, normal mode)
- Try reading WHO_AM_I register (0x0F) — should return 0x33

### Sensitivity too high or too low?
- Adjust threshold values in `sensitivity_table` (main.S, .rodata section)
- Monitor raw accelerometer values by temporarily displaying them on the LED matrix
- Remember: high-byte values range from -128 to +127 for ±2g scale

### Build errors?
- Ensure `constants.inc` is in the same directory as the .S files
- Check that `-I.` flag is passed to the assembler
- Verify ARM toolchain is correctly installed: `arm-none-eabi-as --version`

---

## Report Section: Architecture Concepts

### Memory-Mapped I/O Implementation

The nRF52833 uses a unified memory map where all peripherals are accessed through standard load/store instructions at specific addresses. For example:

- **GPIO registers** at `0x50000000`: Writing to `OUTSET` (offset `0x508`) sets pins HIGH; writing to `OUTCLR` (offset `0x50C`) sets pins LOW. No special I/O bus exists — the same `STR` instruction used for RAM access controls hardware pins.

- **PIN_CNF registers** at `0x50000700 + 4*n`: Each pin has a dedicated 32-bit configuration register that controls direction (input/output), pull-up/down resistors, and drive strength. This is a direct example of "accessing the address pointed by the peripheral" as described in the reference material.

### Interrupt Handling Implementation

The system uses the **GPIOTE** peripheral for edge-triggered interrupts on GPIO pins:

1. **Configuration**: GPIOTE channels are configured to detect falling edges (HIGH→LOW transitions) on button pins. Each channel maps to a specific pin and polarity.

2. **Vector Table**: The GPIOTE ISR address is placed at offset `0x58` in the vector table (IRQ6 = system exception 22). The Cortex-M4 reads this address when IRQ6 fires.

3. **Context Switching**: On interrupt entry, the hardware automatically pushes 8 registers (r0-r3, r12, lr, pc, xPSR) onto the stack — a hardware-assisted context save. The special EXC_RETURN value in LR triggers the reverse operation on ISR exit.

4. **Flag-Based Communication**: The ISR sets a flag (memory variable), and the main loop polls the flag. This separates the timing-critical interrupt detection from the application-level response handling.

### Accelerometer Data Processing

Raw sensor data flows through several processing stages:

1. **I2C Communication**: The TWIM peripheral uses DMA to read 6 bytes from the LSM303AGR's output registers in a single transaction. DMA frees the CPU during the transfer.

2. **Data Extraction**: The 16-bit output is left-justified (10-bit value in bits [15:6]). Using only the high byte provides approximately 8-bit resolution — sufficient for tilt and impact detection.

3. **Sign Extension**: The `SXTB` instruction extends signed 8-bit values to 32-bit integers, enabling correct signed arithmetic for tilt direction detection.

4. **Magnitude Computation**: Manhattan distance (|X|+|Y|+|Z|) approximates the acceleration magnitude without requiring expensive square root computation. Conditional negate (`IT LT; NEGLT`) computes absolute values branchlessly.

---

## Hardware Specifications

| Component | Detail |
|-----------|--------|
| MCU | nRF52833 (ARM Cortex-M4, 64 MHz) |
| Flash | 512 KB |
| RAM | 128 KB |
| LED Matrix | 5×5, multiplexed via 10 GPIO pins |
| Buttons | 2 (A = P0.14, B = P0.23), active LOW |
| Accelerometer | LSM303AGR (I2C address 0x19) |
| Speaker | Onboard, connected to P0.00 |
| Power | USB or 2×AAA battery pack |

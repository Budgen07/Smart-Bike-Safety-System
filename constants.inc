@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ constants.inc - Hardware Register Definitions
@ Smart Bike Safety System for BBC micro:bit v2
@ nRF52833 (ARM Cortex-M4) Memory-Mapped Register Map
@
@ This file demonstrates MEMORY-MAPPED I/O: every peripheral
@ (GPIO, I2C, interrupts) is controlled by reading/writing to
@ specific memory addresses. There is no special I/O instruction -
@ regular LDR/STR instructions access hardware registers.
@
@ Reference: nRF52833 Product Specification + Microbit_Reference.pdf
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

@ ===================== Memory Layout =====================
.equ STACK_TOP,             0x20020000   @ Top of 128KB RAM

@ ===================== GPIO Port 0 =====================
@ Base address: 0x50000000 (from Microbit_Reference.pdf)
@ "The base address of all GPIO Pin P0 is 0x50000000"
@ GPIO pins control LEDs, buttons, speaker, and I2C lines.

.equ GPIO_P0_OUT,           0x50000504   @ Output register
.equ GPIO_P0_OUTSET,        0x50000508   @ Set bits HIGH
.equ GPIO_P0_OUTCLR,        0x5000050C   @ Set bits LOW
.equ GPIO_P0_IN,            0x50000510   @ Read input pin state
.equ GPIO_P0_DIR,           0x50000514   @ Direction (1=output)
.equ GPIO_P0_DIRSET,        0x50000518   @ Set direction bits
.equ GPIO_P0_PIN_CNF,       0x50000700   @ Pin config base (+4*n)

@ ===================== GPIO Port 1 =====================
@ COL4 of LED matrix is on Port 1 (separate address space!)
.equ GPIO_P1_OUTSET,        0x50000808
.equ GPIO_P1_OUTCLR,        0x5000080C
.equ GPIO_P1_DIRSET,        0x50000818
.equ GPIO_P1_PIN_CNF,       0x50000A00   @ + 4*n

@ ===================== GPIOTE (GPIO Tasks and Events) =====================
@ Used for INTERRUPT HANDLING: generates hardware interrupts
@ when button pins change state (falling edge = button press).
@ This is a key computer architecture concept: instead of
@ polling buttons in a loop, the hardware notifies the CPU.

.equ GPIOTE_EVENTS_IN0,     0x40006100   @ Event for channel 0
.equ GPIOTE_EVENTS_IN1,     0x40006104   @ Event for channel 1
.equ GPIOTE_INTENSET,       0x40006304   @ Interrupt enable (set)
.equ GPIOTE_INTENCLR,       0x40006308   @ Interrupt enable (clear)
.equ GPIOTE_CONFIG0,        0x40006510   @ Channel 0 config
.equ GPIOTE_CONFIG1,        0x40006514   @ Channel 1 config

@ ===================== NVIC (Nested Vectored Interrupt Controller) =====================
@ CPU-internal interrupt controller. Part of ARM Cortex-M4 core.
@ Manages interrupt priorities and enables/disables IRQ lines.

.equ NVIC_ISER0,            0xE000E100   @ Interrupt Set Enable
.equ NVIC_ICER0,            0xE000E180   @ Interrupt Clear Enable
.equ GPIOTE_IRQ_NUM,        6            @ GPIOTE = IRQ #6

@ ===================== TWIM0 (I2C Master with EasyDMA) =====================
@ Two-Wire Interface Master for communicating with the onboard
@ LSM303AGR accelerometer sensor. Uses DMA (Direct Memory Access)
@ to transfer data between RAM and the I2C bus.

.equ TWIM0_STARTRX,         0x40003000   @ Task: begin receiving
.equ TWIM0_STARTTX,         0x40003008   @ Task: begin transmitting
.equ TWIM0_STOP,            0x40003014   @ Task: stop transaction
.equ TWIM0_EVT_STOPPED,     0x40003104   @ Event: stopped
.equ TWIM0_EVT_ERROR,       0x40003124   @ Event: error
.equ TWIM0_SHORTS,          0x40003200   @ Shortcut config
.equ TWIM0_ENABLE,          0x40003500   @ Enable (write 6)
.equ TWIM0_PSEL_SCL,        0x40003508   @ SCL pin select
.equ TWIM0_PSEL_SDA,        0x4000350C   @ SDA pin select
.equ TWIM0_FREQUENCY,       0x40003524   @ I2C clock speed
.equ TWIM0_RXD_PTR,         0x40003534   @ RX DMA buffer address
.equ TWIM0_RXD_MAXCNT,      0x40003538   @ RX byte count
.equ TWIM0_TXD_PTR,         0x40003544   @ TX DMA buffer address
.equ TWIM0_TXD_MAXCNT,      0x40003548   @ TX byte count
.equ TWIM0_ADDRESS,         0x40003588   @ I2C slave address

.equ TWI_FREQ_100K,         0x01980000   @ 100 kHz clock

@ TWIM shortcut bits (auto-chain hardware tasks)
.equ SHORT_LASTTX_STARTRX,  (1 << 7)    @ TX done → start RX
.equ SHORT_LASTTX_STOP,     (1 << 9)    @ TX done → stop
.equ SHORT_LASTRX_STOP,     (1 << 12)   @ RX done → stop

@ ===================== LED Matrix Pin Mapping =====================
@ Reference: https://tech.microbit.org/hardware/schematic/#v2-pinmap
@ 5x5 LED matrix uses multiplexing: 5 row + 5 column GPIO pins.
@ Column = anode (HIGH to activate), Row = cathode (LOW to activate)

.equ ROW1_PIN,   21     @ P0.21
.equ ROW2_PIN,   22     @ P0.22
.equ ROW3_PIN,   15     @ P0.15 (offset 0x73C from base, per PDF)
.equ ROW4_PIN,   24     @ P0.24
.equ ROW5_PIN,   19     @ P0.19

.equ COL1_PIN,   28     @ P0.28 (per PDF example)
.equ COL2_PIN,   11     @ P0.11
.equ COL3_PIN,   31     @ P0.31
.equ COL4_PIN,    5     @ P1.05 ← Port 1!
.equ COL5_PIN,   30     @ P0.30

@ ===================== Button Pins =====================
.equ BTN_A_PIN,  14     @ P0.14 (active LOW, external pull-up)
.equ BTN_B_PIN,  23     @ P0.23 (active LOW, external pull-up)

@ ===================== Speaker Pin =====================
.equ SPEAKER_PIN, 0     @ P0.00 (micro:bit v2 onboard speaker)

@ ===================== Internal I2C Pins =====================
.equ I2C_SCL_PIN, 8     @ P0.08
.equ I2C_SDA_PIN, 16    @ P0.16

@ ===================== LSM303AGR Accelerometer =====================
.equ ACCEL_ADDR,        0x19    @ 7-bit I2C address
.equ ACCEL_CTRL_REG1,   0x20    @ Control register 1
.equ ACCEL_OUT_X_L,     0x28    @ X-axis data low byte
.equ ACCEL_MULTI,       0x80    @ OR with register for auto-increment
.equ ACCEL_CTRL1_VAL,   0x57    @ 100Hz, normal mode, XYZ enabled

@ ===================== Pin Configuration Values =====================
@ PIN_CNF register format:
@   Bit 0: DIR (0=input, 1=output)
@   Bit 1: INPUT (0=connect, 1=disconnect)
@   Bits 3:2: PULL (0=none, 1=down, 3=up)

.equ PIN_CNF_OUTPUT,    0x03    @ Output, input disconnected
.equ PIN_CNF_INPUT_PU,  0x0C    @ Input, connected, pull-up

@ ===================== Precomputed Bitmasks =====================
.equ ALL_ROWS_MASK, ((1<<ROW1_PIN)|(1<<ROW2_PIN)|(1<<ROW3_PIN)|(1<<ROW4_PIN)|(1<<ROW5_PIN))
.equ ALL_COLS_P0,   ((1<<COL1_PIN)|(1<<COL2_PIN)|(1<<COL3_PIN)|(1<<COL5_PIN))
.equ COL4_P1_MASK,  (1<<COL4_PIN)

@ ===================== Timing =====================
@ CPU @ 64 MHz, busy-wait loop ≈ 3 cycles/iteration
.equ LOOPS_PER_MS,  21333

@ ===================== Application Constants =====================
@ State machine states
.equ STATE_NORMAL,   0     @ Riding normally
.equ STATE_BRAKE,    1     @ Braking detected (tilt)
.equ STATE_ACCIDENT, 2     @ Fall/crash detected

@ Sensitivity levels
.equ SENS_LOW,       0
.equ SENS_MEDIUM,    1
.equ SENS_HIGH,      2

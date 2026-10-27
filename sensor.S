@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ sensor.S - Accelerometer & I2C Communication Module
@
@ Handles all communication with the LSM303AGR accelerometer via
@ the nRF52833's TWIM (I2C Master with EasyDMA) peripheral.
@
@ The TWIM uses DMA (Direct Memory Access) to transfer data between
@ RAM buffers and the I2C bus. This is a hardware optimization that
@ frees the CPU during data transfer.
@
@ Sensor data flow:
@   CPU writes register address to twi_tx_buf
@   → TWIM DMA sends twi_tx_buf over I2C to accelerometer
@   → Accelerometer responds with data
@   → TWIM DMA stores response in twi_rx_buf
@   → CPU reads results from twi_rx_buf
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .syntax unified
    .cpu cortex-m4
    .thumb

    .include "constants.inc"

@ === Exported Symbols ===
    .global twim_init
    .global accel_init
    .global accel_read_xyz
    .global accel_x, accel_y, accel_z

@ ==========================================================================
@  Code Section
@ ==========================================================================
    .section .text

@ --------------------------------------------------------------------------
@  twim_init - Initialize TWIM0 (I2C Master) peripheral
@  Configures pins, frequency, slave address, and enables the peripheral.
@ --------------------------------------------------------------------------
    .thumb_func
twim_init:
    push {lr}

    @ Disable peripheral first (it shares SPIM0/TWIS0 — may be in wrong mode)
    ldr  r0, =TWIM0_ENABLE
    mov  r1, #0
    str  r1, [r0]

    @ Configure I2C GPIO pins with pull-ups (needed for I2C bus)
    ldr  r0, =GPIO_P0_PIN_CNF
    ldr  r1, =PIN_CNF_INPUT_PU      @ Input, connected, pull-up
    str  r1, [r0, #(I2C_SCL_PIN * 4)]   @ P0.08 SCL
    str  r1, [r0, #(I2C_SDA_PIN * 4)]   @ P0.16 SDA

    @ Select SCL pin = P0.08
    ldr  r0, =TWIM0_PSEL_SCL
    mov  r1, #I2C_SCL_PIN
    str  r1, [r0]

    @ Select SDA pin = P0.16
    ldr  r0, =TWIM0_PSEL_SDA
    mov  r1, #I2C_SDA_PIN
    str  r1, [r0]

    @ Set I2C frequency to 100 kHz (standard mode)
    ldr  r0, =TWIM0_FREQUENCY
    ldr  r1, =TWI_FREQ_100K
    str  r1, [r0]

    @ Set slave address to accelerometer (0x19)
    ldr  r0, =TWIM0_ADDRESS
    mov  r1, #ACCEL_ADDR
    str  r1, [r0]

    @ Enable TWIM peripheral (write 6 = TWIM mode)
    ldr  r0, =TWIM0_ENABLE
    mov  r1, #6
    str  r1, [r0]

    pop  {pc}


@ --------------------------------------------------------------------------
@  twim_write - I2C Write Transaction
@  Sends bytes from RAM buffer to the I2C slave.
@  Uses hardware shortcut: LASTTX→STOP (auto-stop after last byte sent).
@
@  Input: r0 = pointer to TX buffer (in RAM), r1 = byte count
@ --------------------------------------------------------------------------
    .thumb_func
twim_write:
    push {r4-r5, lr}

    @ Configure DMA: set TX buffer pointer and count
    ldr  r2, =TWIM0_TXD_PTR
    str  r0, [r2]               @ DMA source = TX buffer in RAM
    ldr  r2, =TWIM0_TXD_MAXCNT
    str  r1, [r2]               @ Number of bytes to send

    @ Set shortcut: after last TX byte → auto-stop
    ldr  r2, =TWIM0_SHORTS
    ldr  r3, =SHORT_LASTTX_STOP
    str  r3, [r2]

    @ Clear STOPPED event (write 0 to event register)
    ldr  r2, =TWIM0_EVT_STOPPED
    mov  r3, #0
    str  r3, [r2]

    @ Trigger STARTTX task (write 1 to task register)
    ldr  r2, =TWIM0_STARTTX
    mov  r3, #1
    str  r3, [r2]

    @ Poll until STOPPED event fires (with timeout)
    ldr  r4, =200000            @ Timeout counter
.Ltw_poll:
    ldr  r2, =TWIM0_EVT_STOPPED
    ldr  r3, [r2]
    cmp  r3, #0
    bne  .Ltw_done
    subs r4, r4, #1
    bne  .Ltw_poll
.Ltw_done:
    @ Clear the event for next use
    ldr  r2, =TWIM0_EVT_STOPPED
    mov  r3, #0
    str  r3, [r2]

    pop  {r4-r5, pc}


@ --------------------------------------------------------------------------
@  twim_write_read - I2C Write-then-Read Transaction
@  First sends TX buffer (register address), then reads response.
@  Uses hardware shortcuts: LASTTX→STARTRX, LASTRX→STOP
@
@  Input: r0 = TX buf ptr, r1 = TX count, r2 = RX buf ptr, r3 = RX count
@ --------------------------------------------------------------------------
    .thumb_func
twim_write_read:
    push {r4-r6, lr}

    @ Set TX DMA buffer
    ldr  r4, =TWIM0_TXD_PTR
    str  r0, [r4]
    ldr  r4, =TWIM0_TXD_MAXCNT
    str  r1, [r4]

    @ Set RX DMA buffer
    ldr  r4, =TWIM0_RXD_PTR
    str  r2, [r4]
    ldr  r4, =TWIM0_RXD_MAXCNT
    str  r3, [r4]

    @ Set shortcuts: TX done → start RX, RX done → stop
    ldr  r4, =TWIM0_SHORTS
    ldr  r5, =(SHORT_LASTTX_STARTRX | SHORT_LASTRX_STOP)
    str  r5, [r4]

    @ Clear STOPPED event
    ldr  r4, =TWIM0_EVT_STOPPED
    mov  r5, #0
    str  r5, [r4]

    @ Trigger STARTTX task
    ldr  r4, =TWIM0_STARTTX
    mov  r5, #1
    str  r5, [r4]

    @ Poll until STOPPED event (with timeout)
    ldr  r6, =200000            @ Timeout counter
.Ltwr_poll:
    ldr  r4, =TWIM0_EVT_STOPPED
    ldr  r5, [r4]
    cmp  r5, #0
    bne  .Ltwr_done
    subs r6, r6, #1
    bne  .Ltwr_poll
.Ltwr_done:
    @ Clear event
    ldr  r4, =TWIM0_EVT_STOPPED
    mov  r5, #0
    str  r5, [r4]

    pop  {r4-r6, pc}

    .ltorg


@ --------------------------------------------------------------------------
@  accel_init - Configure the LSM303AGR Accelerometer
@  Writes CTRL_REG1_A = 0x57:
@    - ODR = 100 Hz (Output Data Rate)
@    - Normal power mode (10-bit resolution)
@    - X, Y, Z axes all enabled
@ --------------------------------------------------------------------------
    .thumb_func
accel_init:
    push {lr}

    @ Prepare TX buffer: [register_address, config_value]
    ldr  r0, =twi_tx_buf
    mov  r1, #ACCEL_CTRL_REG1       @ 0x20
    strb r1, [r0, #0]
    mov  r1, #ACCEL_CTRL1_VAL       @ 0x57
    strb r1, [r0, #1]

    @ I2C write: send 2 bytes (addr + value so accelerometer configures)
    @ r0 already = twi_tx_buf
    mov  r1, #2
    bl   twim_write

    pop  {pc}


@ --------------------------------------------------------------------------
@  accel_read_xyz - Read Accelerometer X, Y, Z Values
@
@  Reads 6 bytes from accelerometer (X_L, X_H, Y_L, Y_H, Z_L, Z_H)
@  using auto-increment (register address OR'd with 0x80).
@  Stores the HIGH bytes as sign-extended 32-bit values in accel_x/y/z.
@
@  Using high bytes provides ~8-bit resolution (±128 range for ±2g scale),
@  which is sufficient for tilt and impact detection.
@
@  Outputs: accel_x, accel_y, accel_z (32-bit signed, in memory)
@ --------------------------------------------------------------------------
    .thumb_func
accel_read_xyz:
    push {r4-r6, lr}

    @ Prepare TX buffer: register address with auto-increment bit
    @ 0x28 | 0x80 = 0xA8 → read starting from OUT_X_L_A
    ldr  r0, =twi_tx_buf
    mov  r1, #(ACCEL_OUT_X_L | ACCEL_MULTI)    @ 0xA8
    strb r1, [r0, #0]

    @ I2C write-then-read: send 1 byte (register addr), receive 6 bytes
    @ r0 = TX buffer pointer (already set)
    mov  r1, #1                  @ TX: 1 byte (register address)
    ldr  r2, =twi_rx_buf        @ RX: destination buffer
    mov  r3, #6                  @ RX: 6 bytes (X_L, X_H, Y_L, Y_H, Z_L, Z_H)
    bl   twim_write_read

    @ Extract HIGH bytes and sign-extend int8 → int32
    ldr  r4, =twi_rx_buf

    @ X axis (bytes 0-1: X_L, X_H)
    ldrb r0, [r4, #1]           @ X high byte
    sxtb r0, r0                 @ Sign-extend: int8 → int32
    ldr  r1, =accel_x
    str  r0, [r1]

    @ Y axis (bytes 2-3: Y_L, Y_H)
    ldrb r0, [r4, #3]           @ Y high byte
    sxtb r0, r0
    ldr  r1, =accel_y
    str  r0, [r1]

    @ Z axis (bytes 4-5: Z_L, Z_H)
    ldrb r0, [r4, #5]           @ Z high byte
    sxtb r0, r0
    ldr  r1, =accel_z
    str  r0, [r1]

    pop  {r4-r6, pc}


@ ==========================================================================
@  BSS Section (RAM buffers)
@ ==========================================================================
    .section .bss
    .align 2

@ I2C DMA buffers (MUST be in RAM for EasyDMA to access)
twi_tx_buf:     .space 4        @ TX buffer (max 2 bytes used, padded)
twi_rx_buf:     .space 8        @ RX buffer (max 6 bytes for accel data)

@ Accelerometer reading storage (sign-extended 32-bit values)
accel_x:        .space 4
accel_y:        .space 4
accel_z:        .space 4

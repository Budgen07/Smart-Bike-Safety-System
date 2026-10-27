@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ display.S - LED Matrix Display Module
@ Handles 5x5 LED multiplexing, display patterns, and timing.
@
@ The LED matrix works by multiplexing: rapidly scanning through
@ columns, setting the appropriate rows for each column. At ~100Hz
@ refresh rate, persistence of vision makes all LEDs appear lit.
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .syntax unified
    .cpu cortex-m4
    .thumb

    .include "constants.inc"

@ === Exported Symbols ===
    .global display_refresh
    .global display_clear
    .global display_set_pattern
    .global sleep_ms
    .global delay_ms
    .global framebuffer
    .global pattern_normal
    .global pattern_brake
    .global pattern_accident
    .global pattern_all_on
    .global sens_patterns

@ ==========================================================================
@  Code Section
@ ==========================================================================
    .section .text

@ --------------------------------------------------------------------------
@  delay_ms - Simple busy-wait delay (no display refresh)
@  Input: r0 = milliseconds
@  Used internally by display_refresh for per-column dwell time.
@ --------------------------------------------------------------------------
    .thumb_func
delay_ms:
    push {r4-r5, lr}
    mov  r4, r0
.Ldms_outer:
    cmp  r4, #0
    ble  .Ldms_done
    ldr  r5, =LOOPS_PER_MS
.Ldms_inner:
    subs r5, r5, #1         @ 1 cycle
    bne  .Ldms_inner         @ ~2 cycles (branch taken)
    subs r4, r4, #1
    b    .Ldms_outer
.Ldms_done:
    pop  {r4-r5, pc}


@ --------------------------------------------------------------------------
@  sleep_ms - Delay with continuous display refresh
@  Input: r0 = milliseconds
@  Each display_refresh cycle takes ~10ms (5 cols × 2ms).
@  Equivalent to: microbit.sleep(ms)
@ --------------------------------------------------------------------------
    .thumb_func
sleep_ms:
    push {r4, lr}
    mov  r4, r0
.Lsleep_loop:
    cmp  r4, #10
    blt  .Lsleep_done
    bl   display_refresh     @ ~10ms per refresh cycle
    sub  r4, r4, #10
    b    .Lsleep_loop
.Lsleep_done:
    pop  {r4, pc}


@ --------------------------------------------------------------------------
@  display_refresh - One complete LED matrix multiplex scan
@
@  Algorithm (for each column 0-4):
@    1. Turn off ALL columns (prevent ghosting between columns)
@    2. Set ALL rows HIGH (all LEDs off)
@    3. For each row: if framebuffer[row] bit[col] is set,
@       drive that row pin LOW (cathode active = LED on)
@    4. Turn on the current column pin HIGH (anode active)
@    5. Hold for ~2ms (column dwell time)
@
@  Total time: 5 × 2ms = ~10ms → ~100Hz refresh rate
@ --------------------------------------------------------------------------
    .thumb_func
display_refresh:
    push {r4-r7, lr}
    mov  r4, #0              @ r4 = column counter (0-4)

.Ldrf_col_loop:
    @ --- Step 1: All columns OFF ---
    ldr  r0, =GPIO_P0_OUTCLR
    ldr  r1, =ALL_COLS_P0
    str  r1, [r0]
    ldr  r0, =GPIO_P1_OUTCLR
    ldr  r1, =COL4_P1_MASK
    str  r1, [r0]

    @ --- Step 2: All rows HIGH (LEDs off) ---
    ldr  r0, =GPIO_P0_OUTSET
    ldr  r1, =ALL_ROWS_MASK
    str  r1, [r0]

    @ --- Step 3: Build row-clear mask from framebuffer ---
    @ Check framebuffer[row] bit[col] for each row.
    @ If set, add that row's GPIO bitmask to the clear mask.
    ldr  r5, =framebuffer
    ldr  r6, =row_masks
    mov  r7, #0              @ r7 = accumulated row OUTCLR mask
    mov  r3, #0              @ r3 = row counter
.Ldrf_row_check:
    ldrb r0, [r5, r3]       @ framebuffer[row]
    lsr  r0, r0, r4          @ shift right by column index
    tst  r0, #1              @ test LSB (this column's pixel)
    beq  .Ldrf_row_skip
    ldr  r1, [r6, r3, lsl #2] @ load row pin bitmask
    orr  r7, r7, r1          @ add to clear mask
.Ldrf_row_skip:
    add  r3, r3, #1
    cmp  r3, #5
    blt  .Ldrf_row_check

    @ Drive selected rows LOW (activate LED cathodes)
    cmp  r7, #0
    beq  .Ldrf_no_rows
    ldr  r0, =GPIO_P0_OUTCLR
    str  r7, [r0]
.Ldrf_no_rows:

    @ --- Step 4: Turn on current column ---
    ldr  r5, =col_masks_p0
    ldr  r6, [r5, r4, lsl #2]   @ P0 mask for this column
    cmp  r6, #0
    beq  .Ldrf_col4_p1

    @ Column is on Port 0
    ldr  r0, =GPIO_P0_OUTSET
    str  r6, [r0]
    b    .Ldrf_col_hold

.Ldrf_col4_p1:
    @ Column 3 (COL4) is on Port 1, pin 5
    ldr  r0, =GPIO_P1_OUTSET
    ldr  r1, =COL4_P1_MASK
    str  r1, [r0]

.Ldrf_col_hold:
    @ --- Step 5: Hold for ~3ms ---
    mov  r0, #3
    bl   delay_ms
    
    @ --- Blank all rows briefly to prevent ghosting ---
    ldr  r0, =GPIO_P0_OUTSET
    ldr  r1, =ALL_ROWS_MASK
    str  r1, [r0]
    
    @ Next column
    add  r4, r4, #1
    cmp  r4, #5
    blt  .Ldrf_col_loop

    @ --- Cleanup: all columns OFF ---
    ldr  r0, =GPIO_P0_OUTCLR
    ldr  r1, =ALL_COLS_P0
    str  r1, [r0]
    ldr  r0, =GPIO_P1_OUTCLR
    ldr  r1, =COL4_P1_MASK
    str  r1, [r0]

    pop  {r4-r7, pc}

    .ltorg


@ --------------------------------------------------------------------------
@  display_clear - Zero the framebuffer (all LEDs off)
@  Equivalent to: microbit.display.clear()
@ --------------------------------------------------------------------------
    .thumb_func
display_clear:
    ldr  r0, =framebuffer
    mov  r1, #0
    strb r1, [r0, #0]
    strb r1, [r0, #1]
    strb r1, [r0, #2]
    strb r1, [r0, #3]
    strb r1, [r0, #4]
    bx   lr


@ --------------------------------------------------------------------------
@  display_set_pattern - Copy a 5-byte LED pattern into the framebuffer
@  Input: r0 = pointer to 5-byte pattern array
@         Each byte = one row; bit N = column N (bit 0 = leftmost)
@ --------------------------------------------------------------------------
    .thumb_func
display_set_pattern:
    ldr  r1, =framebuffer
    ldrb r2, [r0, #0]
    strb r2, [r1, #0]
    ldrb r2, [r0, #1]
    strb r2, [r1, #1]
    ldrb r2, [r0, #2]
    strb r2, [r1, #2]
    ldrb r2, [r0, #3]
    strb r2, [r1, #3]
    ldrb r2, [r0, #4]
    strb r2, [r1, #4]
    bx   lr


@ ==========================================================================
@  Read-Only Data (stored in Flash)
@ ==========================================================================
    .section .rodata

@ Column bitmask table for Port 0 (indexed by column 0-4)
@ Column 3 (COL4) is on Port 1, so its P0 mask is 0.
    .global col_masks_p0
col_masks_p0:
    .word (1 << COL1_PIN)    @ Column 0: P0.28
    .word (1 << COL2_PIN)    @ Column 1: P0.11
    .word (1 << COL3_PIN)    @ Column 2: P0.31
    .word 0                  @ Column 3: P1.05 (handled separately)
    .word (1 << COL5_PIN)    @ Column 4: P0.30

@ Row bitmask table for Port 0 (indexed by row 0-4)
    .global row_masks
row_masks:
    .word (1 << ROW1_PIN)    @ Row 0: P0.21
    .word (1 << ROW2_PIN)    @ Row 1: P0.22
    .word (1 << ROW3_PIN)    @ Row 2: P0.15
    .word (1 << ROW4_PIN)    @ Row 3: P0.24
    .word (1 << ROW5_PIN)    @ Row 4: P0.19

@ --------------------------------------------------------------------------
@  LED Display Patterns (5 bytes each, row-major)
@
@  Bit encoding: bit 0 = column 0 (leftmost), bit 4 = column 4 (rightmost)
@  1 = LED on, 0 = LED off
@ --------------------------------------------------------------------------

@ NORMAL state: Small diamond (riding indicator)
@   .....
@   ..#..
@   .#.#.
@   ..#..
@   .....
pattern_normal:
    .byte 0x04, 0x04, 0x1F, 0x04	, 0x04

@ BRAKE state: Rectangle (stop/caution indicator)
@   #####
@   #...#
@   #...#
@   #...#
@   #####
pattern_brake:
    .byte 0x1F, 0x11, 0x11, 0x11, 0x1F

@ ACCIDENT state: X pattern (danger/SOS indicator)
@   #...#   = bits 0,4 = 0x11
@   .#.#.   = bits 1,3 = 0x0A
@   ..#..   = bit  2   = 0x04
@   .#.#.   = bits 1,3 = 0x0A
@   #...#   = bits 0,4 = 0x11
pattern_accident:
    .byte 0x11, 0x0A, 0x04, 0x0A, 0x11

@ Sensitivity level indicator patterns (shown when Button B cycles)
@
@ Level 0 (LOW) - "L":     Level 1 (MED) - "M":     Level 2 (HIGH) - "H":
@   #....                    #...#                    #...#
@   #....                    ##.##                    #...#
@   #....                    #.#.#                    #####
@   #....                    #...#                    #...#
@   #####                    #...#                    #...#
sens_patterns:
    .byte 0x01, 0x01, 0x01, 0x01, 0x1F     @ LOW  (offset 0)
    .byte 0x11, 0x1B, 0x15, 0x11, 0x11     @ MED  (offset 5)
    .byte 0x11, 0x11, 0x1F, 0x11, 0x11     @ HIGH (offset 10)

@ ALL ON pattern (startup self-test)
@   #####
@   #####
@   #####
@   #####
@   #####
pattern_all_on:
    .byte 0x1F, 0x1F, 0x1F, 0x1F, 0x1F


@ ==========================================================================
@  BSS Section (uninitialized RAM)
@ ==========================================================================
    .section .bss
    .align 2

@ Display framebuffer: 5 bytes (one per row), 3 bytes padding
framebuffer:
    .space 8

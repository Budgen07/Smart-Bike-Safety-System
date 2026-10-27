@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ main.S - Smart Bike Safety System: Main Program
@
@ This file contains:
@   - Cortex-M4 Vector Table (entry point for CPU)
@   - Reset Handler (hardware initialization sequence)
@   - GPIO Initialization (LED matrix pin configuration)
@   - Button Handler (processes ISR-set flags)
@   - State Machine (NORMAL → BRAKE → ACCIDENT transitions)
@
@ The state machine is the core control logic:
@   NORMAL:   Minimal LED indicator, monitor accelerometer
@   BRAKE:    Tilt detected (backward lean), show stop pattern
@   ACCIDENT: Extreme acceleration/fall, flash X + alarm beep
@
@ State transitions are triggered by:
@   - Accelerometer data exceeding thresholds (sensor-driven)
@   - Button presses (interrupt-driven, via flags)
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .syntax unified
    .cpu cortex-m4
    .thumb

    .include "constants.inc"

@ === External Symbols (defined in other modules) ===
    .global gpiote_isr          @ interrupts.S - ISR referenced in vector table


@ ==========================================================================
@  VECTOR TABLE (at address 0x00000000)
@ ==========================================================================
@ The Cortex-M4 reads this table on power-up/reset:
@   Word 0 (0x00): Initial Stack Pointer
@   Word 1 (0x04): Reset Handler address (program entry point)
@   Words 2-15:    Exception handlers (NMI, faults, SVC, etc.)
@   Words 16+:     Peripheral IRQ handlers
@
@ GPIOTE (button interrupts) is IRQ #6 → word 22 (offset 0x58)

    .section .vectors, "a"
    .word STACK_TOP              @ 0x00: Initial SP (top of 128KB RAM)
    .word reset_handler          @ 0x04: Reset Handler (entry point)
    .word default_handler        @ 0x08: NMI
    .word default_handler        @ 0x0C: HardFault
    .word default_handler        @ 0x10: MemManage
    .word default_handler        @ 0x14: BusFault
    .word default_handler        @ 0x18: UsageFault
    .word 0, 0, 0, 0            @ 0x1C-0x28: Reserved
    .word default_handler        @ 0x2C: SVCall
    .word default_handler        @ 0x30: Debug Monitor
    .word 0                      @ 0x34: Reserved
    .word default_handler        @ 0x38: PendSV
    .word default_handler        @ 0x3C: SysTick
    .word default_handler        @ 0x40: IRQ0  - POWER_CLOCK
    .word default_handler        @ 0x44: IRQ1  - RADIO
    .word default_handler        @ 0x48: IRQ2  - UARTE0
    .word default_handler        @ 0x4C: IRQ3  - SPIM0/TWIM0
    .word default_handler        @ 0x50: IRQ4  - SPIM1/TWIM1
    .word default_handler        @ 0x54: IRQ5  - NFCT
    .word gpiote_isr             @ 0x58: IRQ6  - GPIOTE ← BUTTON INTERRUPTS


@ ==========================================================================
@  CODE SECTION
@ ==========================================================================
    .section .text

@ --- Default exception handler (infinite loop) ---
    .thumb_func
    .global default_handler
default_handler:
    b    default_handler         @ Halt on unhandled exception


@ ==========================================================================
@  RESET HANDLER - Program Entry Point
@ ==========================================================================
@ Executed on power-up or reset. Initializes all hardware and enters
@ the main state machine loop.

    .thumb_func
    .global reset_handler
reset_handler:
    ldr  sp, =STACK_TOP          @ Initialize stack pointer

    @ --- Zero-initialize BSS section (uninitialized RAM) ---
    @ C runtime would do this; we do it manually in bare-metal
    ldr  r0, =_bss_start
    ldr  r1, =_bss_end
    mov  r2, #0
.Lbss_zero:
    cmp  r0, r1
    bge  .Lbss_done
    str  r2, [r0], #4           @ *ptr++ = 0
    b    .Lbss_zero
.Lbss_done:

    @ --- Set default sensitivity to MEDIUM ---
    ldr  r0, =sensitivity_level
    mov  r1, #SENS_MEDIUM
    str  r1, [r0]
    ldr  r0, =brake_thresh
    mov  r1, #25                 @ Medium brake threshold (1g ≈ 64 counts)
    str  r1, [r0]
    ldr  r0, =accident_thresh
    mov  r1, #160                @ Medium accident threshold
    str  r1, [r0]

    @ --- Initialize all hardware modules ---
    bl   gpio_init               @ LED matrix GPIO pins
    bl   twim_init               @ I2C for accelerometer
    bl   accel_init              @ Configure accelerometer sensor
    bl   sound_init              @ Speaker GPIO pin
    bl   gpiote_init             @ Button interrupts (enables IRQs)

    @ --- Set initial state ---
    ldr  r0, =current_state
    mov  r1, #STATE_NORMAL
    str  r1, [r0]

    @ --- Startup LED test: show ALL LEDs for 1 second ---
    @ This verifies the display hardware is working on boot.
    ldr  r0, =pattern_all_on
    bl   display_set_pattern
    ldr  r0, =1000
    bl   sleep_ms

    @ --- Then show normal pattern for 1 second ---
    ldr  r0, =pattern_normal
    bl   display_set_pattern
    ldr  r0, =1000
    bl   sleep_ms

    @ --- Enter main loop ---
    b    main_loop


@ ==========================================================================
@  GPIO INITIALIZATION
@ ==========================================================================
@ Configures all LED matrix pins (5 rows + 5 columns) as GPIO outputs.
@ Demonstrates memory-mapped I/O: each PIN_CNF register is at a
@ calculable address = 0x50000700 + (4 × pin_number)

    .thumb_func
gpio_init:
    push {r4-r5, lr}

    ldr  r4, =GPIO_P0_PIN_CNF
    ldr  r5, =PIN_CNF_OUTPUT     @ 0x03 = output, input disconnected

    @ Configure row pins as output (Port 0)
    str  r5, [r4, #(ROW1_PIN * 4)]   @ P0.21
    str  r5, [r4, #(ROW2_PIN * 4)]   @ P0.22
    str  r5, [r4, #(ROW3_PIN * 4)]   @ P0.15
    str  r5, [r4, #(ROW4_PIN * 4)]   @ P0.24
    str  r5, [r4, #(ROW5_PIN * 4)]   @ P0.19

    @ Configure column pins as output (Port 0)
    str  r5, [r4, #(COL1_PIN * 4)]   @ P0.28
    str  r5, [r4, #(COL2_PIN * 4)]   @ P0.11
    str  r5, [r4, #(COL3_PIN * 4)]   @ P0.31
    str  r5, [r4, #(COL5_PIN * 4)]   @ P0.30

    @ COL4 is on Port 1 — different base address!
    ldr  r4, =GPIO_P1_PIN_CNF
    str  r5, [r4, #(COL4_PIN * 4)]   @ P1.05

    @ Set all rows HIGH initially (all LEDs off)
    ldr  r0, =GPIO_P0_OUTSET
    ldr  r1, =ALL_ROWS_MASK
    str  r1, [r0]

    @ Set all columns LOW initially (all LEDs off)
    ldr  r0, =GPIO_P0_OUTCLR
    ldr  r1, =ALL_COLS_P0
    str  r1, [r0]
    ldr  r0, =GPIO_P1_OUTCLR
    ldr  r1, =COL4_P1_MASK
    str  r1, [r0]

    pop  {r4-r5, pc}

    .ltorg


@ ==========================================================================
@  HANDLE BUTTONS - Process ISR-set flags
@ ==========================================================================
@ This function is called from the main loop. It checks the button
@ flags set by the GPIOTE ISR and takes appropriate action.
@
@ Button A:   Reset from ACCIDENT state → NORMAL
@ Button B:   Cycle sensitivity level (LOW → MEDIUM → HIGH → LOW)
@ Both A+B:   Force ACCIDENT state (manual test mode)

    .thumb_func
handle_buttons:
    push {r4-r6, lr}

    @ --- Check A+B combo flag (highest priority) ---
    ldr  r0, =btn_ab_flag
    ldr  r1, [r0]
    cmp  r1, #1
    bne  .Lhb_check_a

    @ Clear flag
    mov  r1, #0
    str  r1, [r0]

    @ Force ACCIDENT state (test mode)
    ldr  r0, =current_state
    mov  r1, #STATE_ACCIDENT
    str  r1, [r0]
    pop  {r4-r6, pc}

.Lhb_check_a:
    @ --- Check Button A (acknowledge/reset) ---
    ldr  r0, =btn_a_flag
    ldr  r1, [r0]
    cmp  r1, #1
    bne  .Lhb_check_b

    @ Clear flag
    mov  r1, #0
    str  r1, [r0]

    @ Only effective in ACCIDENT state
    ldr  r0, =current_state
    ldr  r1, [r0]
    cmp  r1, #STATE_ACCIDENT
    bne  .Lhb_check_b           @ Ignore if not in ACCIDENT

    @ Reset to NORMAL
    mov  r1, #STATE_NORMAL
    str  r1, [r0]
    bl   sound_off               @ Stop alarm
    pop  {r4-r6, pc}

.Lhb_check_b:
    @ --- Check Button B (cycle sensitivity) ---
    ldr  r0, =btn_b_flag
    ldr  r1, [r0]
    cmp  r1, #1
    bne  .Lhb_done

    @ Clear flag
    mov  r1, #0
    str  r1, [r0]

    @ Cycle sensitivity: 0 → 1 → 2 → 0
    ldr  r0, =sensitivity_level
    ldr  r4, [r0]
    add  r4, r4, #1
    cmp  r4, #3
    it   eq
    moveq r4, #0
    str  r4, [r0]

    @ Update thresholds from lookup table
    ldr  r5, =sensitivity_table
    lsl  r6, r4, #3             @ Each entry = 8 bytes (2 words)
    ldr  r1, [r5, r6]           @ Brake threshold
    ldr  r0, =brake_thresh
    str  r1, [r0]
    add  r6, r6, #4
    ldr  r1, [r5, r6]           @ Accident threshold
    ldr  r0, =accident_thresh
    str  r1, [r0]

    @ Show sensitivity level letter briefly (L, M, or H)
    ldr  r0, =sens_patterns
    mov  r1, #5
    mla  r0, r4, r1, r0         @ r0 = sens_patterns + level * 5
    bl   display_set_pattern
    ldr  r0, =500
    bl   sleep_ms                @ Display for 500ms

.Lhb_done:
    pop  {r4-r6, pc}

    .ltorg


@ ==========================================================================
@  MAIN LOOP - State Machine
@ ==========================================================================
@ The core control logic. Runs forever, checking:
@   1. Button events (from ISR flags)
@   2. Accelerometer data (polled every ~50ms)
@   3. State transitions based on thresholds
@   4. LED pattern and sound output based on state

    .thumb_func
main_loop:
    @ === Step 1: Process button events ===
    bl   handle_buttons

    @ === Step 2: Check current state ===
    ldr  r0, =current_state
    ldr  r1, [r0]
    cmp  r1, #STATE_ACCIDENT
    beq  accident_loop           @ Special handling for accident

    @ === Step 3: Read accelerometer ===
    bl   accel_read_xyz

    @ Load axis values from memory
    ldr  r0, =accel_x
    ldr  r4, [r0]               @ r4 = X (signed)
    ldr  r0, =accel_y
    ldr  r5, [r0]               @ r5 = Y (signed)
    ldr  r0, =accel_z
    ldr  r6, [r0]               @ r6 = Z (signed)

    @ === Step 4: Compute acceleration magnitude ===
    @ magnitude ≈ |X| + |Y| + |Z|  (Manhattan distance approximation)
    @ Absolute value using conditional negate:
    @   if (val < 0) val = -val

    mov  r7, r4                  @ Start with X
    cmp  r7, #0
    it   lt
    neglt r7, r7                 @ r7 = |X|

    mov  r0, r5
    cmp  r0, #0
    it   lt
    neglt r0, r0                 @ r0 = |Y|
    add  r7, r7, r0

    mov  r0, r6
    cmp  r0, #0
    it   lt
    neglt r0, r0                 @ r0 = |Z|
    add  r7, r7, r0              @ r7 = |X| + |Y| + |Z|

    @ === Step 5: Check ACCIDENT threshold ===
    @ If magnitude exceeds accident threshold → impact/fall detected
    ldr  r0, =accident_thresh
    ldr  r0, [r0]
    cmp  r7, r0
    bgt  enter_accident

    @ === Step 6: Check BRAKE threshold ===
    @ If |Y| exceeds brake threshold → tilt detected (braking)
    mov  r0, r5
    cmp  r0, #0
    it   lt
    neglt r0, r0                 @ r0 = |Y|
    ldr  r1, =brake_thresh
    ldr  r1, [r1]
    cmp  r0, r1
    bgt  enter_brake

    @ === NORMAL state ===
    ldr  r0, =current_state
    mov  r1, #STATE_NORMAL
    str  r1, [r0]
    ldr  r0, =pattern_normal
    bl   display_set_pattern
    b    main_sleep

enter_brake:
    @ === BRAKE state ===
    ldr  r0, =current_state
    mov  r1, #STATE_BRAKE
    str  r1, [r0]
    ldr  r0, =pattern_brake
    bl   display_set_pattern
    b    main_sleep

enter_accident:
    @ === Transition to ACCIDENT state ===
    ldr  r0, =current_state
    mov  r1, #STATE_ACCIDENT
    str  r1, [r0]
    @ Fall through to accident_loop


@ --------------------------------------------------------------------------
@  ACCIDENT LOOP - X pattern + Alarm Beep (X stays visible!)
@  Alternates between solidly displaying the X pattern and playing the beep.
@  This creates a highly visible flashing alarm effect and guarantees
@  maximum LED brightness using the proven multiplexer.
@ --------------------------------------------------------------------------
accident_loop:
    push {r4, lr}

    @ Set danger pattern in framebuffer
    ldr  r0, =pattern_accident
    bl   display_set_pattern

    @ --- Alarm Beep and Flash Sequence ---
    @ Alternates 50ms of bright display and 50ms of sound.
    @ This creates a striking 10Hz flashing X pattern while
    @ perfectly preserving the stuttering alarm tone.
    mov  r4, #5
.Laccident_flash_loop:
    @ 1. Display X pattern solidly for 50ms
    mov  r0, #50
    bl   sleep_ms

    @ 2. Play 1kHz alarm tone for 50ms (LEDs are briefly off)
    mov  r0, #50
    bl   sound_beep

    subs r4, r4, #1
    bne  .Laccident_flash_loop

    @ --- Brief pause with X pattern solid ---
    mov  r0, #100
    bl   sleep_ms

    @ Check if button handler changed state (Button A reset)
    bl   handle_buttons
    ldr  r0, =current_state
    ldr  r1, [r0]
    cmp  r1, #STATE_ACCIDENT
    pop  {r4, lr}
    beq  accident_loop           @ Still in accident → keep beeping/flashing

    @ Exited accident state → silence alarm and return to main loop
    bl   sound_off
    b    main_loop


@ --------------------------------------------------------------------------
@  MAIN SLEEP - Delay between sensor readings
@  ~50ms poll interval → 20 readings/second
@ --------------------------------------------------------------------------
main_sleep:
    mov  r0, #50
    bl   sleep_ms
    b    main_loop

    .ltorg


@ ==========================================================================
@  Read-Only Data
@ ==========================================================================
    .section .rodata
    .align 2

@ Sensitivity threshold lookup table
@ Format: [brake_threshold, accident_threshold] per level (2 words each)
sensitivity_table:
    .word 40, 200            @ Level 0: LOW   (less sensitive, ~39° tilt)
    .word 25, 160            @ Level 1: MEDIUM (~23° tilt)
    .word 15, 120            @ Level 2: HIGH  (most sensitive, ~14° tilt)


@ ==========================================================================
@  BSS Section (application state variables)
@ ==========================================================================
    .section .bss
    .align 2

    .global current_state
    .global sensitivity_level
    .global brake_thresh
    .global accident_thresh

current_state:      .space 4     @ 0=NORMAL, 1=BRAKE, 2=ACCIDENT
sensitivity_level:  .space 4     @ 0=LOW, 1=MEDIUM, 2=HIGH
brake_thresh:       .space 4     @ Current brake threshold
accident_thresh:    .space 4     @ Current accident threshold

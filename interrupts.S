@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ interrupts.S - Button Interrupt Handlers
@
@ Demonstrates INTERRUPT HANDLING - a core computer architecture
@ concept. Instead of constantly polling button states in the main
@ loop (wasting CPU cycles), we configure the GPIOTE peripheral
@ to generate hardware interrupts on button press events.
@
@ Interrupt flow:
@   1. Button press → GPIO pin goes LOW (active-low)
@   2. GPIOTE detects falling edge → generates IRQ6
@   3. CPU suspends main code, auto-saves registers to stack
@   4. CPU jumps to gpiote_isr via vector table entry at 0x58
@   5. ISR sets a flag in RAM
@   6. CPU restores registers, resumes main code
@   7. Main loop checks flag and handles the button action
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .syntax unified
    .cpu cortex-m4
    .thumb

    .include "constants.inc"

@ === Exported Symbols ===
    .global gpiote_init
    .global gpiote_isr
    .global btn_a_flag
    .global btn_b_flag
    .global btn_ab_flag

@ ==========================================================================
@  Code Section
@ ==========================================================================
    .section .text

@ --------------------------------------------------------------------------
@  gpiote_init - Configure GPIOTE for Button Interrupts
@
@  Sets up two GPIOTE channels:
@    Channel 0: Button A (P0.14) - falling edge detection
@    Channel 1: Button B (P0.23) - falling edge detection
@
@  Then enables the GPIOTE IRQ in the NVIC and enables global interrupts.
@ --------------------------------------------------------------------------
    .thumb_func
gpiote_init:
    push {lr}

    @ --- Configure button pins as inputs with pull-up ---
    @ PIN_CNF[14] = INPUT, connected, pull-up
    ldr  r0, =GPIO_P0_PIN_CNF
    ldr  r1, =PIN_CNF_INPUT_PU
    str  r1, [r0, #(BTN_A_PIN * 4)]     @ P0.14 (Button A)
    str  r1, [r0, #(BTN_B_PIN * 4)]     @ P0.23 (Button B)

    @ --- Configure GPIOTE channel 0 for Button A ---
    @ CONFIG[0] = MODE(Event=1) | PSEL(14) | PORT(0) | POLARITY(HiToLo=2)
    @ Falling edge = button press (active-LOW with pull-up)
    ldr  r0, =GPIOTE_CONFIG0
    ldr  r1, =((1 << 0) | (BTN_A_PIN << 8) | (0 << 13) | (2 << 16))
    str  r1, [r0]

    @ --- Configure GPIOTE channel 1 for Button B ---
    @ CONFIG[1] = MODE(Event=1) | PSEL(23) | PORT(0) | POLARITY(HiToLo=2)
    ldr  r0, =GPIOTE_CONFIG1
    ldr  r1, =((1 << 0) | (BTN_B_PIN << 8) | (0 << 13) | (2 << 16))
    str  r1, [r0]

    @ --- Clear any pending events ---
    ldr  r0, =GPIOTE_EVENTS_IN0
    mov  r1, #0
    str  r1, [r0]
    ldr  r0, =GPIOTE_EVENTS_IN1
    str  r1, [r0]

    @ --- Enable interrupts for channels 0 and 1 ---
    @ INTENSET bit 0 = IN[0], bit 1 = IN[1]
    ldr  r0, =GPIOTE_INTENSET
    mov  r1, #0x03              @ Enable both channels
    str  r1, [r0]

    @ --- Enable GPIOTE IRQ in NVIC ---
    @ GPIOTE is IRQ #6 → bit 6 in ISER0
    ldr  r0, =NVIC_ISER0
    mov  r1, #(1 << GPIOTE_IRQ_NUM)     @ (1 << 6) = 0x40
    str  r1, [r0]

    @ --- Enable global interrupts (clear PRIMASK) ---
    cpsie i

    pop  {pc}


@ --------------------------------------------------------------------------
@  gpiote_isr - GPIOTE Interrupt Service Routine
@
@  Called by hardware when a button press is detected (falling edge).
@  The Cortex-M4 automatically saves r0-r3, r12, lr, pc, xPSR to stack
@  before entering the ISR, and restores them on return.
@
@  This ISR checks which button triggered the interrupt and also
@  checks if both buttons are pressed simultaneously (A+B combo).
@
@  Button actions:
@    Button A only  → sets btn_a_flag  (reset from accident)
@    Button B only  → sets btn_b_flag  (cycle sensitivity)
@    Both A+B       → sets btn_ab_flag (manual test mode)
@ --------------------------------------------------------------------------
    .thumb_func
gpiote_isr:
    @ r0-r3 are hardware-saved by Cortex-M4 exception entry
    @ Only need to save r4+ if used, plus lr (EXC_RETURN value)
    push {r4, lr}

    @ --- Check GPIOTE channel 0 (Button A event) ---
    ldr  r0, =GPIOTE_EVENTS_IN0
    ldr  r1, [r0]
    cmp  r1, #1
    bne  .Lisr_check_b

    @ Clear the event (write 0 to event register)
    mov  r1, #0
    str  r1, [r0]
    dsb                          @ nRF52 errata: prevent spurious re-entry

    @ Check if Button B is ALSO pressed (A+B combo detection)
    @ Read the actual pin state - Button B = P0.23, active LOW
    ldr  r0, =GPIO_P0_IN
    ldr  r1, [r0]
    tst  r1, #(1 << BTN_B_PIN)     @ Test bit 23
    beq  .Lisr_combo                @ If 0 (LOW), B is also pressed

    @ Solo Button A press
    ldr  r0, =btn_a_flag
    mov  r1, #1
    str  r1, [r0]
    b    .Lisr_done

.Lisr_check_b:
    @ --- Check GPIOTE channel 1 (Button B event) ---
    ldr  r0, =GPIOTE_EVENTS_IN1
    ldr  r1, [r0]
    cmp  r1, #1
    bne  .Lisr_done              @ Neither channel triggered (spurious)

    @ Clear the event
    mov  r1, #0
    str  r1, [r0]
    dsb                          @ nRF52 errata: prevent spurious re-entry

    @ Check if Button A is ALSO pressed (A+B combo detection)
    ldr  r0, =GPIO_P0_IN
    ldr  r1, [r0]
    tst  r1, #(1 << BTN_A_PIN)     @ Test bit 14
    beq  .Lisr_combo                @ If 0 (LOW), A is also pressed

    @ Solo Button B press
    ldr  r0, =btn_b_flag
    mov  r1, #1
    str  r1, [r0]
    b    .Lisr_done

.Lisr_combo:
    @ Both buttons pressed simultaneously → test mode
    ldr  r0, =btn_ab_flag
    mov  r1, #1
    str  r1, [r0]

.Lisr_done:
    @ Return from ISR: pop loads EXC_RETURN into PC,
    @ triggering the Cortex-M4 exception return sequence
    @ which restores the auto-saved registers from stack.
    pop  {r4, pc}

    .ltorg


@ ==========================================================================
@  BSS Section (button flags in RAM)
@ ==========================================================================
    .section .bss
    .align 2

@ Button event flags (set by ISR, cleared by main loop)
@ Using 32-bit words for atomic read/write on ARM
btn_a_flag:     .space 4        @ 1 = Button A pressed
btn_b_flag:     .space 4        @ 1 = Button B pressed
btn_ab_flag:    .space 4        @ 1 = Both buttons pressed

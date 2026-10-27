@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@ sound.S - Speaker/Alarm Module
@
@ Generates audible alarm tones through the micro:bit v2's onboard
@ speaker (connected to P0.00). Uses direct GPIO toggling to create
@ a square wave at approximately 1 kHz.
@
@ This is the simplest form of sound generation: rapidly switching
@ a GPIO pin between HIGH and LOW creates a vibration in the speaker
@ membrane, producing an audible tone.
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@

    .syntax unified
    .cpu cortex-m4
    .thumb

    .include "constants.inc"

@ === Exported Symbols ===
    .global sound_init
    .global sound_beep
    .global sound_off

@ ==========================================================================
@  Code Section
@ ==========================================================================
    .section .text

@ --------------------------------------------------------------------------
@  sound_init - Configure speaker pin as GPIO output
@ --------------------------------------------------------------------------
    .thumb_func
sound_init:
    @ Configure P0.00 (speaker) as high-drive output for louder sound
    @ PIN_CNF: DIR=1(output), INPUT=1(disconnect), PULL=0, DRIVE=3(H0H1)
    ldr  r0, =GPIO_P0_PIN_CNF
    ldr  r1, =0x0303              @ High-drive output, input disconnected
    str  r1, [r0, #(SPEAKER_PIN * 4)]    @ PIN_CNF[0]

    @ Set speaker pin LOW (silent)
    ldr  r0, =GPIO_P0_OUTCLR
    mov  r1, #(1 << SPEAKER_PIN)
    str  r1, [r0]

    bx   lr


@ --------------------------------------------------------------------------
@  sound_beep - Generate a ~1 kHz alarm tone
@
@  Produces a square wave by toggling P0.00 at 1 kHz:
@    500µs HIGH → 500µs LOW = 1ms period = 1 kHz
@
@  At 64 MHz, 500µs = 32,000 cycles.
@  Inner loop: ~3 cycles/iteration → 32000/3 ≈ 10,667 iterations
@
@  Input: r0 = duration in milliseconds (≈ number of cycles)
@  Note: This is a blocking function (no display refresh during beep)
@ --------------------------------------------------------------------------
    .thumb_func
sound_beep:
    push {r4-r6, lr}

    mov  r4, r0                  @ r4 = cycle count (≈ ms)
    ldr  r5, =GPIO_P0_OUTSET    @ r5 = OUTSET address (cached in reg)
    ldr  r6, =GPIO_P0_OUTCLR    @ r6 = OUTCLR address (cached in reg)
    mov  r3, #(1 << SPEAKER_PIN) @ r3 = speaker pin bitmask

.Lbeep_loop:
    cmp  r4, #0
    ble  .Lbeep_done

    @ --- HIGH half-cycle (~500µs) ---
    str  r3, [r5]                @ P0.00 = HIGH
    ldr  r0, =10667              @ Calibrated delay loop count
.Lbeep_hi:
    subs r0, r0, #1
    bne  .Lbeep_hi

    @ --- LOW half-cycle (~500µs) ---
    str  r3, [r6]                @ P0.00 = LOW
    ldr  r0, =10667
.Lbeep_lo:
    subs r0, r0, #1
    bne  .Lbeep_lo

    subs r4, r4, #1              @ Decrement cycle counter
    b    .Lbeep_loop

.Lbeep_done:
    @ Ensure speaker is LOW (silent) on exit
    str  r3, [r6]
    pop  {r4-r6, pc}


@ --------------------------------------------------------------------------
@  sound_off - Silence the speaker
@  Drives P0.00 LOW to stop any sound.
@ --------------------------------------------------------------------------
    .thumb_func
sound_off:
    ldr  r0, =GPIO_P0_OUTCLR
    mov  r1, #(1 << SPEAKER_PIN)
    str  r1, [r0]
    bx   lr

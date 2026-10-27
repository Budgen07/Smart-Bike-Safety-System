# ============================================================================
# Makefile - Smart Bike Safety System
# Target: BBC micro:bit v2 (nRF52833 / ARM Cortex-M4)
# ============================================================================

# Toolchain (ARM GNU Embedded Toolchain)
AS      = arm-none-eabi-as
LD      = arm-none-eabi-ld
OBJCOPY = arm-none-eabi-objcopy
OBJDUMP = arm-none-eabi-objdump
SIZE    = arm-none-eabi-size

# Flags
ASFLAGS = -mcpu=cortex-m4 -mthumb -g -I.
LDFLAGS = -T linker.ld

# Project
TARGET  = smart_bike
SRCS    = main.S display.S sensor.S interrupts.S sound.S
OBJS    = $(SRCS:.S=.o)

# ---- Build Targets ----

# Default: build the hex file (ready to flash)
all: $(TARGET).hex
	@echo ""
	@echo "=== Build successful! ==="
	@echo "Output: $(TARGET).hex"
	@echo "Flash:  cp $(TARGET).hex /Volumes/MICROBIT/"
	@echo ""

# Assemble each .S file into an object file
# Each file includes constants.inc, so it's a dependency
%.o: %.S constants.inc
	$(AS) $(ASFLAGS) -o $@ $<

# Link all object files into an ELF executable
$(TARGET).elf: $(OBJS)
	$(LD) $(LDFLAGS) -o $@ $^

# Convert ELF to Intel HEX format (what micro:bit accepts)
$(TARGET).hex: $(TARGET).elf
	$(OBJCOPY) -O ihex $< $@
	@$(SIZE) $<

# ---- Utility Targets ----

# Generate disassembly listing (useful for debugging)
disasm: $(TARGET).elf
	$(OBJDUMP) -d -S $< > $(TARGET).lst
	@echo "Disassembly written to $(TARGET).lst"

# Flash to micro:bit (macOS - copies hex to mounted drive)
flash: $(TARGET).hex
	@echo "Flashing to micro:bit..."
	cp $< /Volumes/MICROBIT/
	@echo "Done! micro:bit will restart automatically."

# Flash to micro:bit (Linux)
flash-linux: $(TARGET).hex
	@echo "Flashing to micro:bit..."
	cp $< /media/$(USER)/MICROBIT/
	@echo "Done!"

# Clean build artifacts
clean:
	rm -f *.o *.elf *.hex *.lst

# Show code size information
info: $(TARGET).elf
	$(SIZE) $<

.PHONY: all clean flash flash-linux disasm info

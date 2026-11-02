; Z8S180 internal I/O registers (Zilog UM0050). Use in0/out0 for these ports.

        .ifndef Z180_INC
        .equ Z180_INC, 1

        .equ CNTLA0, 0x00
        .equ CNTLA1, 0x01
        .equ CNTLB0, 0x02
        .equ CNTLB1, 0x03
        .equ STAT0, 0x04
        .equ STAT1, 0x05
        .equ TDR0, 0x06
        .equ TDR1, 0x07
        .equ RDR0, 0x08
        .equ RDR1, 0x09
        .equ CNTR, 0x0A
        .equ TRDR, 0x0B

; Programmable reload timers
        .equ TMDR0L, 0x0C
        .equ TMDR0H, 0x0D
        .equ RLDR0L, 0x0E
        .equ RLDR0H, 0x0F
        .equ TCR, 0x10
        .equ TCR_TDE0, 0x01             ; TCR: timer 0 counts
        .equ TCR_TIF0, 0x40             ; TCR: timer 0 reached 0
        .equ TMDR1L, 0x14
        .equ TMDR1H, 0x15
        .equ RLDR1L, 0x16
        .equ RLDR1H, 0x17
        .equ FRC, 0x18

; DMA channel 0: memory or I/O source to memory or I/O destination
        .equ SAR0L, 0x20
        .equ SAR0H, 0x21
        .equ SAR0B, 0x22
        .equ DAR0L, 0x23
        .equ DAR0H, 0x24
        .equ DAR0B, 0x25
        .equ BCR0L, 0x26
        .equ BCR0H, 0x27

; DMA channel 1: memory to and from an I/O port
        .equ MAR1L, 0x28
        .equ MAR1H, 0x29
        .equ MAR1B, 0x2A
        .equ IAR1L, 0x2B
        .equ IAR1H, 0x2C
        .equ IAR1B, 0x2D
        .equ BCR1L, 0x2E
        .equ BCR1H, 0x2F
        .equ DSTAT, 0x30
        .equ DMODE, 0x31
        .equ DCNTL, 0x32

; Interrupts and refresh
        .equ IL, 0x33
        .equ ITC, 0x34
        .equ RCR, 0x36

; Memory management: CBAR holds the common-area-1 and bank-area start pages.
        .equ CBR, 0x38
        .equ BBR, 0x39
        .equ CBAR, 0x3A
        .equ OMCR, 0x3E
        .equ ICR, 0x3F

; DSTAT bits. A write changes DE0 or DE1 only when its DWE bit is 0, so a
; channel 0 start with DSTAT_KEEP1 leaves a running channel 1 alone.
        .equ DSTAT_DE1, 0x80
        .equ DSTAT_DE1_BIT, 7
        .equ DSTAT_DE0, 0x40
        .equ DSTAT_DWE1, 0x20
        .equ DSTAT_DWE0, 0x10
        .equ DSTAT_DIE1, 0x08
        .equ DSTAT_DIE0, 0x04
        .equ DSTAT_DME, 0x01
        .equ DSTAT_KEEP1, DSTAT_DWE1
        .equ DSTAT_KEEP0, DSTAT_DWE0

; Write VALUE to the internal register PORT through A.
        .macro set_io port, value
        ld a,\value
        out0 (\port),a
        .endm

; DMODE: channel 0 address modes
        .equ DMODE_BURST, 0x02          ; memory to memory, burst
        .equ DMODE_SOURCE_FIXED, 0x08   ; the source address does not change

; DCNTL for the packet stream: DREQ1 edge-triggered, channel 1 I/O to memory.
        .equ DCNTL_STREAM, 0x0A

        .endif

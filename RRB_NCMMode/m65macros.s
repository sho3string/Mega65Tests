/*
 * Generate BASIC65 Boilerplate at $2001
 *    10 BANK0:SYS$addr
 * and starts segment Main with label main right after this
 */
.macro Basic65Upstart() {
        * = $2001 "BASIC Upstart"

        .encoding "petscii_upper"
        .word !nextline+, 10    // line 10
#if BENCHMARK
        .byte $9c               // CLRTI
        .text "TI:"
#endif
        .byte $fe, $02          // BANK0
        .text "0:"
        .byte $9e               // SYS$addr
        .text "$"
        .byte floor(((!main+>>12) & $f)/10)*7 + $30 + ((!main+>>12) & $f)
        .byte floor(((!main+>>8) & $f)/10)*7 + $30 + ((!main+>>8) & $f)
        .byte floor(((!main+>>4) & $f)/10)*7 + $30 + ((!main+>>4) & $f)
        .byte floor((!main+ & $f)/10)*7 + $30 + (!main+ & $f)
#if BENCHMARK
        .text ":ET"             // ET=TI
        .byte $b2
        .text "TI"
#endif
        .byte 0                 // eol
!nextline:
#if BENCHMARK
        .word !lastline+, 20    // line 20
        .byte $e8, $3a, $99     // SCNCLR:PRINTET
        .text "ET"
        .byte 0                 // eol
!lastline:
#endif
        .word 0                 // eop

!main:
        * = * "Main"
}


.macro BasicUpstart65(addr) {
	* = $2001 "Basic Program"
		.var addrStr = toIntString(addr)

		.byte $09,$20 //End of command marker (first byte after the 00 terminator)
		.byte $14,$00 //10
		.byte $fe,$02,$30,$00 //BANK 0
		.byte <end, >end //End of command marker (first byte after the 00 terminator)
		.byte $1e,$00 //20
		.byte $9e //SYS
		.text addrStr
		.byte $00
	end:
		.byte $00,$00	//End of basic terminators
}

.macro enable40Mhz() {
		lda #$41
		sta $00 //40 Mhz mode
}

.macro GoFaster() {
        lda #65
        sta $00 // switch to 40.5 MHz
}

.macro enableVIC3Registers () {
		lda #$00
		tax 
		tay 
		taz 
		map
		eom

		lda #$A5	//Enable VIC III
		sta $d02f
		lda #$96
		sta $d02f
}

.macro UnmapMemory() {
        lda #0
        tax
        tay
        taz
        map
        eom                     // zero out memory mapping
}

.macro EnableVIC4() {
        lda #$47                // do the magic knock
        sta $d02f
        lda #$53
        sta $d02f
}

.macro enableVIC4Registers() {

		lda #$00
		tax 
		tay 
		taz 
		map
		eom

		lda #$47	//Enable VIC IV
		sta $d02f
		lda #$53
		sta $d02f
}

.macro disableC65ROM() {
		lda #$70
		sta $d640
		eom
}

//
// Disabled Interrupts, clears Decimal flag and moves BasePage
//
.macro MoveBasePage(basepage) {
        sei                     // disable interupts
        cld                     // no binary decimals
        lda #basepage
        tab                     // move base-page so we can use base page addresses for everything
}


.macro disableCIA() {
	lda #$7f
	sta $dc0d
	sta $dd0d
}

.macro ResetBasePage() {
        lda #0
        tab
}

.macro UARTClearKey() {
        // clear key buffer
!loop:  lda UART_ASCIIKEY
        beq !enduart+
        sta UART_ASCIIKEY
        bra !loop-
!enduart:
}


// read ASCII key is in accumulator
.macro UARTWaitKey() {
!loop:  lda UART_ASCIIKEY
        beq !loop-
        sta UART_ASCIIKEY
}

.macro mapMemory(source, target) {
	.var sourceMB = (source & $ff00000) >> 20
	.var sourceOffset = ((source & $00fff00) - target)
	.var sourceOffHi = sourceOffset >> 16
	.var sourceOffLo = (sourceOffset & $0ff00 ) >> 8
	.var bitLo = pow(2, (((target) & $ff00) >> 12) / 2) << 4
	.var bitHi = pow(2, (((target-$8000) & $ff00) >> 12) / 2) << 4
	
	.if(target<$8000) {
		lda #sourceMB
		ldx #$0f
		ldy #$00
		ldz #$00
	} else {
		lda #$00
		ldx #$00
		ldy #sourceMB
		ldz #$0f
	}
	map 

	//Set offset map
	.if(target<$8000) {
		lda #sourceOffLo
		ldx #[sourceOffHi + bitLo]
		ldy #$00
		ldz #$00
	} else {
		lda #$00
		ldx #$00
		ldy #sourceOffLo
		ldz #[sourceOffHi + bitHi]
	}	
	map 
	eom
}

.macro VIC4_SetCharLocation(addr) {
	lda #[addr & $ff]
	sta $d068
	lda #[[addr & $ff00]>>8]
	sta $d069
	lda #[[addr & $ff0000]>>16]
	sta $d06a
}

.macro VIC4_SetScreenLocation(addr) {
	lda #[addr & $ff]
	sta $d060
	lda #[[addr & $ff00]>>8]
	sta $d061
	lda #[[addr & $ff0000]>>16]
	sta $d062
	lda #[[[addr & $ff0000]>>24] & $0f]
	sta $d063
}
.macro RunDMAJob(JobPointer) {
		lda #[JobPointer >> 16]
		sta $d702
		sta $d704
		lda #>JobPointer
		sta $d701
		lda #<JobPointer
		sta $d705
}
.macro DMAHeader(SourceBank, DestBank) {
		.byte $0A // Request format is F018A
		.byte $80, SourceBank
		.byte $81, DestBank
}
.macro DMAStep(SourceStep, SourceStepFractional, DestStep, DestStepFractional) {
		.if(SourceStepFractional != 0) {
			.byte $82, SourceStepFractional
		}
		.if(SourceStep != 1) {
			.byte $83, SourceStep
		}
		.if(DestStepFractional != 0) {
			.byte $84, DestStepFractional
		}
		.if(DestStep != 1) {
			.byte $85, DestStep
		}		
}


.macro DMADisableTransparency() {
		.byte $06
}
.macro DMAEnableTransparency(TransparentByte) {
		.byte $07 
		.byte $86, TransparentByte
}
.macro DMACopyJob(Source, Destination, Length, Chain, Backwards) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $04 //Copy and chain
	} else {
		.byte $00 //Copy and last request
	}	
	
	.var backByte = 0
	.if(Backwards) {
		.eval backByte = $40
		.eval Source = Source + Length - 1
		.eval Destination = Destination + Length - 1
	}
	.word Length //Size of Copy

	.word Source & $ffff
	.byte [Source >> 16] + backByte

	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f]  + backByte
	.if(Chain) {
		.word $0000
	}
}

.macro DMAFillJob(SourceByte, Destination, Length, Chain) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $07 //Fill and chain
	} else {
		.byte $03 //Fill and last request
	}	
	
	.word Length //Size of Copy
	.word SourceByte
	.byte $00
	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f] 
	.if(Chain) {
		.word $0000
	}
}

.macro DMAMixJob(Source, Destination, Length, Chain, Backwards) {
	.byte $00 //No more options
	.if(Chain) {
		.byte $04 //Mix and chain
	} else {
		.byte $00 //Mix and last request
	}	
	
	.var backByte = 0
	.if(Backwards) {
		.eval backByte = $40
		.eval Source = Source + Length - 1
		.eval Destination = Destination + Length - 1
	}
	.word Length //Size of Copy
	.word Source & $ffff
	.byte [Source >> 16] + backByte
	.word Destination & $ffff
	.byte [[Destination >> 16] & $0f]  + backByte
	.if(Chain) {
		.word $0000
	}
}
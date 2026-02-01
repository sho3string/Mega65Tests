.cpu _45gs02
#import "mega65defs.s"	
#import "m65macros.s"

.const COLOR_RAM = $ff80000
.const TAIL_SLOTS = 3
.const NUM_ROWS = 26
.const VISIBLE_COLS = 40
.const TAIL_WORDS     = TAIL_SLOTS * 2      // gotox + char for each slot
.const TAIL_OFF	= VISIBLE_COLS * 2 // tail starts AFTER 40 visible cols = 80 bytes
.const TAIL_LEN	= TAIL_SLOTS * 4   // 3 slots * 4 bytes = 12 

.const LOGICAL_COLS = VISIBLE_COLS + TAIL_WORDS 
.const LOGICAL_ROW_SIZE = LOGICAL_COLS * 2 // 43*2 = 86 bytes per row in RAM2

.const MARKER0 = $98 // colour tail byte0: enables GOTOX + rowmask + transparency as used by this method
.const SLOT0		= 0						// bytes 0..3
.const SLOT1		= 4						// bytes 4..7
.const SLOT2		= 8						// bytes 8..11

.const CHR_TL		= 0 // top left
.const CHR_TR		= 1 // top right
.const CHR_BL		= 2 // bottom left
.const CHR_BR		= 3 // bottom right 

.const SLOT0_GOTOX = 0   		// gotox word at 0/1, char at 2/3
.const SLOT1_GOTOX = 4   		// gotox word at 4/5, char at 6/7
.const BALL_CHAR_BASE = 4         

* = $02 "Basepage" virtual
	byte_02:		.byte $00
	byte_03:		.byte $00
	byte_04:		.byte $00
	byte_05:		.byte $00
	byte_06:		.byte $00
	byte_07:		.byte $00
	byte_ypos:		.byte $00
	x2_lo:			.byte $00
	x2_hi:			.byte $00
	rowsToDraw:	.byte $00
	charToDraw:	.byte $00
	ScreenVector:	.word $0000
	
BasicUpstart65(Entry)
* = $2016 "Basic Entry"

Entry: {
		sei 
		lda #$35
		sta $01

		enable40Mhz()
		enableVIC4Registers()

		//Disable CIA interrupts
		lda #$7f
		sta $dc0d
		sta $dd0d

		//Disable C65 rom protection using
		//hypervisor trap (see mega65 manual)
		lda #$70
		sta $d640
		eom
		
		//Unmap C65 Roms $d030 by clearing bits 3-7
		lda #%11111000
		trb $d030

		//Disable IRQ raster interrupts
		//because C65 uses raster interrupts in the ROM
		lda #$00
		sta $d01a

		//Change VIC2 stuff here to save having to disable hot registers
		lda #%00000111
		trb $d016

		cli


		//Now setup VIC4
		lda #$20			// enable SEAM.
		sta $d031

		lda #%00000101		//Set bit2=FCM for chars >$ff,  bit0=16 bit char indices
		sta $d054

		//Set logical row width
		//bytes per screen row (16 bit value in $d058-$d059)
		lda #<LOGICAL_ROW_SIZE
		sta $d058
		lda #>LOGICAL_ROW_SIZE
		sta $d059

		//Set number of chars per row
		lda #VISIBLE_COLS
		sta $d05e
		//Set number of rows
		lda #$1a
		sta $d07b 

		//Relocate screen RAM using $d060-$d063
		lda #<SCREEN_BASE 
		sta $d060 
		lda #>SCREEN_BASE 
		sta $d061
		lda #$00
		sta $d062
		sta $d063

		lda #$00
		sta $d020
		lda #$05
		sta $d021

		//Move top border
		lda #$58
		sta $d048
		lda #$00
		sta $d049

		//Move bottom border
		lda #$f8
		sta $d04a
		lda #$01
		sta $d04b

		//Move Text Y Chargen position 
		lda #$58
		sta $d04e
		lda #$00
		sta $d04f	

		jsr CopyPalette
		jsr CopyColors

loop:
		//wait for raster
		lda #$fe
		cmp $d012 
		bne *-3 
		lda #$ff 
		cmp $d012 
		bne *-3 

		jsr RRBSprites
		jmp loop
}


RRBSprites: {
	
		//jsr ClearRRBTails_ScreenDMA
		//jsr ClearRRBTails_ColorDMA
		//jsr MoveBall
		//jsr DrawQuad16
		rts
}

BallX:
	.word $0000
BallY:
	.byte $00

MoveBall: {
		inc BallY

		inc BallX + 0
		bne !+
		lda BallX + 1
		eor #$01 
		sta BallX + 1
	!:
		rts
}

// Helper: compute sub + yposbits + coarse row

// byte_06 = sub (0..7)
// ypos    = sub<<5 (bits 5..7)
// X       = coarse row (BallY>>3)
CalcY:
    lda BallY
    and #$07
    sta byte_06

    lda byte_06
    asl
    asl
    asl
    asl
    asl
    sta byte_ypos

    lda BallY
    lsr
    lsr
    lsr
    tax
    rts

// Helper: compute X+8 (16-bit) into x2_lo/x2_hi
CalcXPlus8:
    lda BallX+0
    clc
    adc #8
    sta x2_lo
    lda BallX+1
    adc #0
    sta x2_hi
    rts
	
// Helper: write color marker+mask to SLOT0 or SLOT1
// IN: Z = slot offset (0 for SLOT0, 4 for SLOT1)
// IN: A = mask byte to write (TopMask[sub] or BotMask[sub])
WriteColorMask:
    pha
    lda #MARKER0
    sta ((byte_02)),z        // marker at slot+0
    inz
    pla
    sta ((byte_02)),z        // mask at slot+1
    rts


DrawQuad16:
    jsr CalcY
    jsr CalcXPlus8

    // --------------------------
    // ROW X (top 8px)
    // --------------------------
    cpx #NUM_ROWS
    lbcs dq_done

    // Screen ptr for row X
    lda RRBRowTableLo,x
    sta ScreenVector+0
    lda RRBRowTableHi,x
    sta ScreenVector+1

    // Color ptr for row X (32-bit color RAM base + row ofs)
    lda ColorRowOfsLo,x
    sta byte_02+0
    lda ColorRowOfsHi,x
    sta byte_02+1
    lda #((COLOR_RAM >> 16) & $ff)
    sta byte_02+2
    lda #((COLOR_RAM >> 24) & $ff)
    sta byte_02+3

    // mask = TopMask[sub]
    ldy byte_06
    lda TopMask,y

    // Write color masks for BOTH slots on this row
    ldz #SLOT0
    jsr WriteColorMask
    ldz #SLOT1
    jsr WriteColorMask

    // --- SLOT0 (top-left) ---
    ldy #SLOT0+0
    lda BallX+0
    sta (ScreenVector),y
    iny
    lda BallX+1
    and #%00000011
    ora #%00010000
    ora byte_ypos
    sta (ScreenVector),y

    ldy #SLOT0+2
    lda #< (BALL_CHAR_BASE + CHR_TL)
    sta (ScreenVector),y
    iny
    lda #> (BALL_CHAR_BASE + CHR_TL)
    sta (ScreenVector),y

    // --- SLOT1 (top-right) at X+8 ---
    ldy #SLOT1+0
    lda x2_lo
    sta (ScreenVector),y
    iny
    lda x2_hi
    and #%00000011
    ora #%00010000
    ora byte_ypos
    sta (ScreenVector),y

    ldy #SLOT1+2
    lda #< (BALL_CHAR_BASE + CHR_TR)
    sta (ScreenVector),y
    iny
    lda #> (BALL_CHAR_BASE + CHR_TR)
    sta (ScreenVector),y

    // --------------------------
    // ROW X+1 (bottom 8px)
    // --------------------------
    inx
    cpx #NUM_ROWS
    lbcs dq_done

    // Screen ptr for row X+1
    lda RRBRowTableLo,x
    sta ScreenVector+0
    lda RRBRowTableHi,x
    sta ScreenVector+1

    // Color ptr for row X+1
    lda ColorRowOfsLo,x
    sta byte_02+0
    lda ColorRowOfsHi,x
    sta byte_02+1
    lda #((COLOR_RAM >> 16) & $ff)
    sta byte_02+2
    lda #((COLOR_RAM >> 24) & $ff)
    sta byte_02+3

    // mask = BotMask[sub]
    ldy byte_06
    lda BotMask,y

    // Write color masks for BOTH slots on this row
    ldz #SLOT0
    jsr WriteColorMask
    ldz #SLOT1
    jsr WriteColorMask

    // --- SLOT0 (bottom-left) ---
    ldy #SLOT0+0
    lda BallX+0
    sta (ScreenVector),y
    iny
    lda BallX+1
    and #%00000011
    ora #%00010000
    ora byte_ypos
    sta (ScreenVector),y

    ldy #SLOT0+2
    lda #< (BALL_CHAR_BASE + CHR_BL)
    sta (ScreenVector),y
    iny
    lda #> (BALL_CHAR_BASE + CHR_BL)
    sta (ScreenVector),y

    // --- SLOT1 (bottom-right) ---
    ldy #SLOT1+0
    lda x2_lo
    sta (ScreenVector),y
    iny
    lda x2_hi
    and #%00000011
    ora #%00010000
    ora byte_ypos
    sta (ScreenVector),y

    ldy #SLOT1+2
    lda #< (BALL_CHAR_BASE + CHR_BR)
    sta (ScreenVector),y
    iny
    lda #> (BALL_CHAR_BASE + CHR_BR)
    sta (ScreenVector),y

dq_done:
    rts



ClearRRBTails_ScreenDMA: {
    RunDMAJob(Job)
    rts
Job:
    DMAHeader($00, $00)

    .for (var r=0; r<NUM_ROWS; r++) {
        .var chain = (r != (NUM_ROWS-1))
        DMACopyJob(
            TailScreenTemplate,
            SCREEN_BASE + TAIL_OFF + r*LOGICAL_ROW_SIZE,
            TAIL_LEN,
            chain,
            false
        )
    }
}

ClearRRBTails_ColorDMA: {
    RunDMAJob(Job)
    rts
Job:
    DMAHeader($00, COLOR_RAM >> 20)   // colour RAM bank for $FF80000 is $F8

    .for (var r=0; r<NUM_ROWS; r++) {
        .var chain = (r != (NUM_ROWS-1))
        DMACopyJob(
            TailColorTemplate,
            COLOR_RAM + TAIL_OFF + r*LOGICAL_ROW_SIZE,
            TAIL_LEN,
            chain,
            false
        )
    }
}


customPaletteTbl_1_Start:
Red:
.byte $00,$13,$15,$e5,$76,$e7,$6e,$fe,$5f,$59,$bf,$ff,$ff,$3b,$ff,$00 // 00 - 15
customPaletteTbl_1_End:

Green:
.byte $00,$b1,$d2,$53,$a3,$75,$15,$c6,$c7,$57,$c8,$89,$7a,$d9,$cc,$00 // 00 - 15

Blue:
.byte $00,$29,$8a,$1b,$7b,$2c,$00,$00,$00,$dc,$00,$00,$62,$bd,$08,$00 // 00 - 15


CopyPalette: {	
	lda #%00000110 //Edit=%00, Text = %00, Sprite = %01, Alt = %10
	sta $d070
	
	ldx #customPaletteTbl_1_End-customPaletteTbl_1_Start // size of our palette.
paletteLoop:
	lda Red,x     	// load & store red component
	sta $d100,x
	lda Green,x    // load & store green component
	sta $d200,x
	lda Blue,x     // load & store blue component
	sta $d300,x
	dex
	bpl paletteLoop
	rts
}



CopyColors: {
		RunDMAJob(Job)
		rts 
	Job:
		DMAHeader($00, COLOR_RAM>>20)
		DMACopyJob(COLORS, COLOR_RAM, LOGICAL_ROW_SIZE * NUM_ROWS, false, false)
}



* = $4000
SCREEN_BASE: {
	.for(var r=0; r<NUM_ROWS; r++) {
		.for(var c=0; c<VISIBLE_COLS; c++) {
			.byte $00,$02

      // to do
			/*.if(mod(r,2)==0) {
				.if(random() < 0.1) {
					.byte $02,$02
				} else {
					.byte $00,$02
				}
			} else {
				.byte $01,$02
			}*/
		}
		// Tail slots (3 chars = 12 bytes)
    .byte $00,$00, $06,$02   // slot0
    .byte $00,$00, $06,$02
    .byte $40,$01, $06,$02 
	}
}


COLORS: {
	.for(var r=0; r<NUM_ROWS; r++) {
		// Background: exactly BG_COLS cells
        .for (var c=0; c<VISIBLE_COLS; c++) {
            .byte $00,$00     // whatever you want for “full FCM background”
			
        }
		// Tail slots default (marker + “normal” byte1)
      .byte $90,$00,  $00,$00   // slot0
      .byte $90,$00,  $00,$00   // slot1
      .byte $90,$00,  $00,$00   // slot2
			
	}
}


* = $8000 "Sprites"  //Index = $0200
	.import binary "sprites.bin"
	.fill 64,0


TopMask:
  .byte %11111111
  .byte %11111110
  .byte %11111100
  .byte %11111000
  .byte %11110000
  .byte %11100000
  .byte %11000000
  .byte %10000000
BotMask:
  .byte %00000000
  .byte %00000001
  .byte %00000011
  .byte %00000111
  .byte %00001111
  .byte %00011111
  .byte %00111111
  .byte %01111111
	

RRBRowTableLo:
    .fill NUM_ROWS, <[SCREEN_BASE + i * LOGICAL_ROW_SIZE + TAIL_OFF]
RRBRowTableHi:
    .fill NUM_ROWS, >[SCREEN_BASE + i * LOGICAL_ROW_SIZE + TAIL_OFF]

ColorRowOfsLo:
    .fill NUM_ROWS, <[i * LOGICAL_ROW_SIZE + TAIL_OFF]
ColorRowOfsHi:
    .fill NUM_ROWS, >[i * LOGICAL_ROW_SIZE + TAIL_OFF]


TailScreenTemplate:
    // slot0: gotox(0) + char(blank)
    .byte $00,$00, $06,$02
	// slot1: gotox(0) + char(blank)
	.byte $00,$00, $06,$02
    // slot2: gotox(end) + char(blank)
    .byte $40,$01, $06,$02

TailColorTemplate:
    .byte $90,$00, $00,$00   // slot0
    .byte $90,$00, $00,$00   // slot1
    .byte $90,$00, $00,$00   // slot2


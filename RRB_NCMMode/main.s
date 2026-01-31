// Demonstrates RRB via NCM mode using Masks. Borrows from Shallan's example delivered during a livestream
// https://github.com/smnjameson/M65_Examples/tree/main/2-NybbleMode
// https://www.youtube.com/watch?v=FgpIOo7b-NM

// This technique for implementing RRB via masking is described here.
// https://retrocogs.mega65.com/2025/08/14/vic-iv-graphics-using-rrb-for-pixies/

.cpu _45gs02
#import "mega65defs.s"	
#import "m65macros.s"

.const COLOR_RAM = $ff80000
.const NUM_ROWS = 26
.const ROW_SIZE = 26
.const LOGICAL_ROW_SIZE = ROW_SIZE * 2
.const MARKER0 = $98 // colour tail byte0: enables GOTOX + rowmask + transparency as used by this method

.const SLOT0 = 0            // bytes 0..3
.const SLOT1 = 4            // bytes 4..7
.const SLOT0_GOTOX = 0      // gotox word at 0/1, char at 2/3
.const SLOT1_GOTOX = 4   		// gotox word at 4/5, char at 6/7
.const BALL_CHAR_BASE = 4 

.const TAIL_OFF = 40          // 20 chars * 2 bytes
.const TAIL_LEN = 12          

* = $02 "Basepage" virtual
  byte_02:		  .byte $00
  byte_03:		  .byte $00
  byte_04:		  .byte $00
  byte_05:		  .byte $00
  byte_06:		  .byte $00
  byte_07:		  .byte $00
  ypos:         .byte $00
  rowsToDraw:   .byte $00
  charToDraw:   .byte $00
  ScreenVector: .word $0000
	
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
  //lda #%10100000		//Clear bit7=40 column, bit5=disable extended attribute
  //trb $d031
  lda #$20				// enable SEAM.
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
  lda #ROW_SIZE
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
	
  jsr ClearRRBTails_ScreenDMA
  jsr ClearRRBTails_ColorDMA
  jsr MoveBall
  jsr DrawRRBSprites
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


DrawRRBSprites:

  /////////////////////
  // Ball first half //
  /////////////////////

  // ------------------------------------------------------------
  // sub = BallY & 7  (0..7)
  // ypos = (sub << 5)  -> bits 5..7 for screen byte1
  // ------------------------------------------------------------
  lda BallY
  and #$07
  sta byte_06              // sub
  
  lda byte_06
  asl
  asl
  asl
  asl
  asl
  sta ypos                 // bits5..7 = sub<<5 

  // coarse row = BallY >> 3
  lda BallY
  lsr
  lsr
  lsr
  tax                      // X = coarse row
  
  // =========================
  // TOP ROW (row X): char 4
  // =========================
  cpx #NUM_ROWS
  lbcs done
  
  lda RRBRowTableLo,x
  sta ScreenVector+0
  lda RRBRowTableHi,x
  sta ScreenVector+1


	lda ColorRowOfsLo,x
	sta byte_02+0
	lda ColorRowOfsHi,x
	sta byte_02+1
	lda #((COLOR_RAM >> 16) & $ff)
	sta byte_02+2
	lda #((COLOR_RAM >> 24) & $ff)
	sta byte_02+3
	

    // Color tail slot0: marker + TopMask[sub]
	ldz #SLOT0+0
	lda #MARKER0
	sta ((byte_02)),z
	ldy byte_06
	lda TopMask,y
	ldz #SLOT0+1
	sta ((byte_02)),z
	
  // Screen tail slot0: gotox word
  ldy #SLOT0+0
  lda BallX+0
  sta (ScreenVector),y
  iny
  lda BallX+1
  and #%00000011
  ora #%00010000           // fcm_yoffs_dir = 1  (the “subtract” direction)
  ora ypos                 // bits5..7 = fine Y (sub<<5)
  sta (ScreenVector),y

  // Screen tail slot0: char word (top)
  ldy #SLOT0+2
  lda #BALL_CHAR_BASE      // 4
  sta (ScreenVector),y
  iny
  lda #$02
  sta (ScreenVector),y

	
  // =========================
  // BOTTOM ROW (row X+1): char 5
  // =========================
  inx
  cpx #NUM_ROWS
  lbcs done
  
  lda RRBRowTableLo,x
  sta ScreenVector+0
  lda RRBRowTableHi,x
  sta ScreenVector+1
  
  lda ColorRowOfsLo,x
  sta byte_02+0
  lda ColorRowOfsHi,x
  sta byte_02+1
  lda #((COLOR_RAM >> 16) & $ff)
  sta byte_02+2
  lda #((COLOR_RAM >> 24) & $ff)
  sta byte_02+3

  // Color tail slot0: marker + TopMask[sub]
  ldz #SLOT0+0
  lda #MARKER0
  sta ((byte_02)),z
  ldy byte_06
  lda BotMask,y
  ldz #SLOT0+1
  sta ((byte_02)),z
  
  // Screen tail slot0: gotox again (same xhi bits, same yoffs)
  ldy #SLOT0+0
  lda BallX+0
  sta (ScreenVector),y
  iny
  lda BallX+1
  and #%00000011
  ora #%00010000
  ora ypos
  sta (ScreenVector),y
  
  // Screen tail slot0: char word (bottom)
  ldy #SLOT0+2
  lda #BALL_CHAR_BASE+1    // 5
  sta (ScreenVector),y
  iny
  lda #$02
  sta (ScreenVector),y

  //////////////////////
  // Ball second half //
  //////////////////////

  // ------------------------------------------------------------
  // sub = BallY & 7  (0..7)
  // ypos = (sub << 5)  -> bits 5..7 for screen byte1
  // ------------------------------------------------------------
  lda BallY
  clc
  adc #8
  sta byte_07
  and #7
  sta byte_06
  
  lda byte_06
  asl
  asl
  asl
  asl
  asl
  sta ypos                 // bits5..7 = sub<<5 
  
  // coarse row = BallY >> 3
  lda byte_07
  lsr
  lsr
  lsr
  tax
  
  // =========================
  // TOP ROW (row X): 
  // =========================
  cpx #NUM_ROWS
  lbcs done
  
  lda RRBRowTableLo,x
  sta ScreenVector+0
  lda RRBRowTableHi,x
  sta ScreenVector+1
  
  lda ColorRowOfsLo,x
  sta byte_02+0
  lda ColorRowOfsHi,x
  sta byte_02+1
  lda #((COLOR_RAM >> 16) & $ff)
  sta byte_02+2
  lda #((COLOR_RAM >> 24) & $ff)
  sta byte_02+3
  
  
  // Color tail slot1: marker + TopMask[sub]
  ldz #SLOT1+0
  lda #MARKER0
  sta ((byte_02)),z
  ldy byte_06
  lda TopMask,y
  ldz #SLOT1+1
  sta ((byte_02)),z
	
	
  // Screen tail slot0: gotox word
  ldy #SLOT1+0
  lda BallX+0
  sta (ScreenVector),y
  iny
  lda BallX+1
  and #%00000011
  ora #%00010000           // fcm_yoffs_dir = 1  (the “subtract” direction)
  ora ypos                 // bits5..7 = fine Y (sub<<5)
  sta (ScreenVector),y
  
  // Screen tail slot0: char word (top)
  ldy #SLOT1+2
  lda #BALL_CHAR_BASE+1      // 4
  sta (ScreenVector),y
  iny
  lda #$02
  sta (ScreenVector),y
  
  
  
  // =========================
  // BOTTOM ROW (row X+1): 
  // =========================
  inx
  cpx #NUM_ROWS
  lbcs done
  
  lda RRBRowTableLo,x
  sta ScreenVector+0
  lda RRBRowTableHi,x
  sta ScreenVector+1

	
	lda ColorRowOfsLo,x
	sta byte_02+0
	lda ColorRowOfsHi,x
	sta byte_02+1
	lda #((COLOR_RAM >> 16) & $ff)
	sta byte_02+2
	lda #((COLOR_RAM >> 24) & $ff)
	sta byte_02+3

  // Color tail slot1: marker + BotMask[sub]
  ldz #SLOT1+0
  lda #MARKER0
  sta ((byte_02)),z
  ldy byte_06
  lda BotMask,y
  ldz #SLOT1+1
  sta ((byte_02)),z
  
  // Screen tail slot1: gotox again (same xhi bits, same yoffs)
  ldy #SLOT1+0
  lda BallX+0
  sta (ScreenVector),y
  iny
  lda BallX+1
  and #%00000011
  ora #%00010000
  ora ypos
  sta (ScreenVector),y
  
  // Screen tail slot1: char word (bottom)
  ldy #SLOT1+2
  lda #BALL_CHAR_BASE+2    // 5
  sta (ScreenVector),y
  iny
  lda #$02
  sta (ScreenVector),y

done:
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


CopyPalette: {
		//Bit pairs = CurrPalette, TextPalette, SpritePalette, AltPalette
		lda #%00000110 //Edit=%00, Text = %00, Sprite = %01, Alt = %10
		sta $d070 

		ldx #$00
	!:
		lda Palette + $000, x 
		sta $d100, x //red
		lda Palette + $100, x 
		sta $d200, x //green
		lda Palette + $200, x 
		sta $d300, x //blue
		inx 
		bne !-
		rts
}


Palette:
	.import binary "sprite_palred.bin"
	.import binary "sprite_palgrn.bin"
	.import binary "sprite_palblu.bin"


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
		.for(var c=0; c<20; c++) {
			.if(mod(r,2)==0) {
				.if(random() < 0.1) {
					.byte $02,$02
				} else {
					.byte $00,$02
				}
			} else {
				.byte $01,$02
			}
		}
		//GOTOX position
		.byte $00,$00
		//Character (blank to start)
		.byte $06,$02
		
		//GOTOX position
		.byte $00,$00
		//Character (blank to start)
		.byte $06,$02

		//GOTOX position
		.byte $40,$01	// end of the line.
		//Character blank to start)
		.byte $06,$02
	
	}
}


COLORS: {
	.for(var r=0; r<NUM_ROWS; r++) {
		.for(var c=0; c<20; c++) {
			.byte $08,$00		//Byte0Bit3 = enable NCM mode
		}
		//GOTOX marker - Byte0bit4=GOTOXMarker, Byte0Bit7=Transparency
		.byte $90,$00 
		.byte $08,$00 //Byte0Bit3 = enable NCM mode, color index 0

		//GOTOX marker - Byte0bit4=GOTOXMarker, Byte0Bit7=Transparency
		.byte $90,$00
		.byte $08,$00	//Byte0Bit3 = enable NCM mode, color index 0	
		
		//GOTOX marker - Byte0bit4=GOTOXMarker, Byte0Bit7=Transparency
		.byte $90,$00
		.byte $08,$00	//Byte0Bit3 = enable NCM mode, color index 0	
			
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
  .fill NUM_ROWS, <[SCREEN_BASE + i * LOGICAL_ROW_SIZE + 40]
RRBRowTableHi:
  .fill NUM_ROWS, >[SCREEN_BASE + i * LOGICAL_ROW_SIZE + 40]


ColorRowOfsLo:
    .fill NUM_ROWS, <[i * LOGICAL_ROW_SIZE + 40]
ColorRowOfsHi:
    .fill NUM_ROWS, >[i * LOGICAL_ROW_SIZE + 40]


TailScreenTemplate:
  // slot0: gotox(0) + char(blank)
  .byte $00,$00, $06,$02
  // slot1: gotox(0) + char(blank)
  .byte $00,$00, $06,$02
  // slot2: gotox(end) + char(blank)
  .byte $40,$01, $06,$02

TailColorTemplate:
  // slot0: 
  .byte $90,$00, $08,$00
  // slot1: 
  .byte $90,$00, $08,$00
  // slot2: 
  .byte $90,$00, $08,$00


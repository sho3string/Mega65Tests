from pathlib import Path

# Input file produced by your editor/build (32 glyphs * 64 bytes = 2048 bytes)
SPRITES_in = Path("sprites.bin")
SPRITES_out = Path("sprites_patched.bin")
# In this format, each 8x8 glyph is 64 bytes (8 rows * 8 pixels, 1 byte per pixel/index)
GLYPH_BYTES = 64

# Your known indices for the ball:
# TL = 4 (unchanged)
# TR = 5 (must swap with BL for FCM)
# BL = 20
# BR = 21 (unchanged)
TR_INDEX = 5
BL_INDEX = 20

# Read the whole binary into a mutable bytearray so we can edit in-place
data = bytearray(SPRITES_in.read_bytes())

# sanity checks so we don't silently corrupt a wrong file
if len(data) % GLYPH_BYTES != 0:
    raise RuntimeError(
        f"File size {len(data)} is not a multiple of {GLYPH_BYTES} bytes/glyph"
    )

glyph_count = len(data) // GLYPH_BYTES
print(f"Loaded {glyph_count} glyphs from {SPRITES_in}")

if TR_INDEX >= glyph_count or BL_INDEX >= glyph_count:
    raise RuntimeError(
        f"Glyph index out of range. File has {glyph_count} glyphs."
    )

# Helper: return (start,end) byte offsets for glyph i inside the file
def glyph_slice(i: int) -> tuple[int, int]:
    start = i * GLYPH_BYTES
    end = start + GLYPH_BYTES
    return start, end

# Compute byte ranges for TR and BL glyph blocks
tr_s, tr_e = glyph_slice(TR_INDEX)
bl_s, bl_e = glyph_slice(BL_INDEX)

print(f"Swapping glyph {TR_INDEX} (TR) <-> glyph {BL_INDEX} (BL)")

# Swap the 64-byte blocks:
tmp = data[tr_s:tr_e]               # copy TR glyph bytes
data[tr_s:tr_e] = data[bl_s:bl_e]   # overwrite TR with BL
data[bl_s:bl_e] = tmp               # overwrite BL with old TR

# Write the modified file back out
SPRITES_out.write_bytes(data)
print("Done.")


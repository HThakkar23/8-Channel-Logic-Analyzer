#!/usr/bin/env python3
"""
Works out how much of the XC7Z007S block RAM the capture buffer needs, and
why 4096 samples deep was the chosen depth rather than something bigger.

capture_buffer is a true dual port memory, DEPTH entries by 8 bits, one bit
per probe channel. The 7 series fabric builds block RAM out of 18 Kb tiles,
two of which can be packed into a 36 Kb tile, and Vivado does that packing
automatically. This script checks a handful of candidate depths against
both tile sizes to see where the jump to a second tile happens.
"""

RAMB18_BITS = 18 * 1024
RAMB36_BITS = 36 * 1024

# XC7Z007S fabric total, per Xilinx 7 series data sheet (36 Kb tiles)
TOTAL_RAMB36_TILES = 50

WIDTH = 8
CANDIDATE_DEPTHS = [512, 1024, 2048, 4096, 8192, 16384]
CHOSEN_DEPTH = 4096


def tiles_needed(bits, tile_bits):
    full = bits // tile_bits
    remainder = bits % tile_bits
    return full + (1 if remainder else 0)


def main():
    print("capture_buffer block RAM budget, XC7Z007S (50 x RAMB36 tiles available)\n")

    header = (f"{'depth':>7} | {'bits':>8} | {'RAMB18 tiles':>12} | "
              f"{'RAMB36 tiles':>12} | {'tile fill':>9}")
    print(header)
    print("-" * len(header))
    for depth in CANDIDATE_DEPTHS:
        bits = depth * WIDTH
        t18 = tiles_needed(bits, RAMB18_BITS)
        t36 = tiles_needed(bits, RAMB36_BITS)
        fill_pct = bits / (t36 * RAMB36_BITS) * 100
        marker = "  <- chosen" if depth == CHOSEN_DEPTH else ""
        print(f"{depth:>7} | {bits:>8} | {t18:>12} | {t36:>12} | "
              f"{fill_pct:>8.1f}%{marker}")

    print()
    chosen_bits = CHOSEN_DEPTH * WIDTH
    chosen_t36 = tiles_needed(chosen_bits, RAMB36_BITS)
    device_pct = chosen_t36 / TOTAL_RAMB36_TILES * 100
    fill_pct = chosen_bits / (chosen_t36 * RAMB36_BITS) * 100
    print(f"chosen depth: {CHOSEN_DEPTH} samples x {WIDTH} bits = {chosen_bits} bits")
    print(f"  fits in {chosen_t36} RAMB36 tile, {fill_pct:.1f}% full")
    print(f"  that tile is {device_pct:.1f}% of the {TOTAL_RAMB36_TILES} tiles on the device")
    print()
    next_depth = CHOSEN_DEPTH * 2
    next_bits = next_depth * WIDTH
    next_t36 = tiles_needed(next_bits, RAMB36_BITS)
    print(f"doubling depth to {next_depth} would need {next_t36} RAMB36 tiles instead of "
          f"{chosen_t36}, and every depth above {CHOSEN_DEPTH} needs at least two.")
    print(f"4096 was picked because it is the largest depth that still fits in a")
    print(f"single RAMB36 tile. That keeps the whole capture buffer in one block")
    print(f"RAM primitive, with the ring buffer's address wraparound a plain")
    print(f"unsigned overflow, instead of spreading one logical memory across")
    print(f"tiles for a window that is not twice as useful at twice the cost.")


if __name__ == "__main__":
    main()

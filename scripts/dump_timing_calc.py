#!/usr/bin/env python3
"""
Works out how long it actually takes to get a captured waveform off the
board and onto the host, since that time adds directly to how often the
instrument can be re-armed for the next capture.

A DUMP sends the whole 4096 byte capture buffer back over the UART link,
one byte per frame. Each 8N1 frame is 10 bit times: a start bit, 8 data
bits, a stop bit. At the board's default 115200 baud that frame time sets
a hard floor on the transfer, no matter how fast the FPGA side is.

The other half of the story is how long the capture itself takes to fill,
which depends on the sample rate chosen with OP_SET_DIVIDER. This script
combines both halves into a total round trip time: arm, wait for the
buffer to fill, then dump, which is what actually limits how many full
waveforms per second a host application can pull down.
"""

CLK_HZ = 100_000_000
DEPTH = 4096
BITS_PER_FRAME = 10  # start + 8 data + stop, no parity

BOARD_BAUD = 115200
COMPARISON_BAUDS = [9600, 38400, 57600, 115200, 230400, 460800, 921600]

SAMPLE_RATES_HZ = [1_000, 10_000, 100_000, 1_000_000, 10_000_000]


def dump_seconds(baud):
    return (DEPTH * BITS_PER_FRAME) / baud


def capture_seconds(sample_rate_hz):
    return DEPTH / sample_rate_hz


def format_duration(seconds):
    if seconds >= 1.0:
        return f"{seconds:.3f} s"
    if seconds >= 1e-3:
        return f"{seconds*1e3:.3f} ms"
    return f"{seconds*1e6:.3f} us"


def main():
    print(f"capture depth       : {DEPTH} bytes")
    print(f"frame size          : {BITS_PER_FRAME} bits (8N1)")
    print()
    print("dump transfer time by baud rate")
    header = f"{'baud':>8} | {'dump time':>12} | {'dumps / sec':>12}"
    print(header)
    print("-" * len(header))
    for baud in COMPARISON_BAUDS:
        t = dump_seconds(baud)
        marker = "  <- board default" if baud == BOARD_BAUD else ""
        print(f"{baud:>8,} | {format_duration(t):>12} | {1/t:>12,.1f}{marker}")

    print()
    board_dump_time = dump_seconds(BOARD_BAUD)
    print(f"at the board's default {BOARD_BAUD:,} baud, one full dump takes "
          f"{format_duration(board_dump_time)}.")
    print()
    print("round trip time: arm, wait for the buffer to fill at a given")
    print("sample rate, then dump it back, at the board's default baud rate")
    header2 = (f"{'sample rate':>12} | {'fill time':>12} | {'dump time':>12} | "
               f"{'round trip':>12} | {'captures / sec':>14}")
    print(header2)
    print("-" * len(header2))
    for rate in SAMPLE_RATES_HZ:
        fill = capture_seconds(rate)
        dump = board_dump_time
        total = fill + dump
        print(f"{rate:>12,} | {format_duration(fill):>12} | {format_duration(dump):>12} | "
              f"{format_duration(total):>12} | {1/total:>14,.2f}")

    print()
    print("at low sample rates the fill time dominates, since the instrument")
    print("is simply waiting for enough real time to pass to collect 4096")
    print("samples. at high sample rates the fill finishes almost instantly")
    print("and the fixed cost of the UART dump takes over, which is why the")
    print("round trip time stops shrinking much past 1 Msa/s even though the")
    print("sample rate keeps climbing. pulling the dump off at a higher baud")
    print("rate than 115200 would lower that floor, at the cost of needing a")
    print("faster or more carefully tuned baud tick generator on both ends.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Works out the real sample rate sample_rate_gen produces for a given divider
value, and what that rate means for the capture as a whole.

sample_rate_gen counts up to the divider value on the 100 MHz system clock
and emits one sample_tick each time it rolls over, so the achievable rates
are CLK_HZ divided by a whole number. This script prints the divider needed
for a handful of round target rates, and for each one works out how much
real time the 4096 sample capture buffer actually covers, since that is
what decides whether a given rate can catch the event the user cares about.
"""

CLK_HZ = 100_000_000
DEPTH = 4096
PRETRIGGER = 2048

TARGET_RATES_HZ = [100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 50_000_000]


def divider_for(rate_hz):
    ideal = CLK_HZ / rate_hz
    div = max(1, round(ideal))
    actual_rate = CLK_HZ / div
    error_pct = (actual_rate - rate_hz) / rate_hz * 100
    return div, actual_rate, error_pct


def format_duration(seconds):
    if seconds >= 1.0:
        return f"{seconds:.3f} s"
    if seconds >= 1e-3:
        return f"{seconds*1e3:.3f} ms"
    if seconds >= 1e-6:
        return f"{seconds*1e6:.3f} us"
    return f"{seconds*1e9:.3f} ns"


def main():
    print(f"system clock        : {CLK_HZ/1e6:.0f} MHz")
    print(f"capture depth       : {DEPTH} samples ({PRETRIGGER} pre-trigger, "
          f"{DEPTH-PRETRIGGER} post-trigger)")
    print()
    header = (f"{'target rate':>12} | {'divider':>8} | {'actual rate':>12} | "
              f"{'error':>7} | {'sample period':>14} | {'full window':>12}")
    print(header)
    print("-" * len(header))
    for rate in TARGET_RATES_HZ:
        div, actual, err = divider_for(rate)
        period = 1.0 / actual
        window = period * DEPTH
        print(f"{rate:>12,} | {div:>8} | {actual:>12,.1f} | {err:>+6.2f}% | "
              f"{format_duration(period):>14} | {format_duration(window):>12}")

    print()
    print("divider = 1 is the fastest this design can sample: one sample")
    print("every system clock edge, 100 Msa/s, a 10 ns sample period. At")
    print("that rate the whole 4096 sample buffer covers 40.96 us, which is")
    print("the shortest total time window the instrument can ever show.")
    print()
    print("the other end of the useful range is set by how long the user is")
    print("willing to wait for an event: a 1 kHz sample rate stretches the")
    print("same 4096 samples out to just over 4 seconds of real time, good")
    print("for catching something slow and irregular like a button bounce")
    print("or a sensor that only toggles once in a while.")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""
Host side client for the logic analyzer. Talks to cmd_protocol.v over a
plain serial port using the binary protocol documented at the top of
that file: one opcode byte, an optional payload, and a single ACK or
NACK byte back, except DUMP, which streams the whole capture buffer with
no framing of its own.

This needs pyserial, which is not installed on the machine this was
written on (no simulator or Vivado here either), so it has never
actually been run against a real board. The protocol handling below
follows cmd_protocol.v's state machine exactly, opcode for opcode, and
the framing matches what every testbench in sim/ already exercises
against that same state machine. Install pyserial with
`pip install pyserial` on whatever machine has the board and a USB to
serial adapter attached, then run this for real.
"""

import argparse
import csv
import time

try:
    import serial
except ImportError:
    serial = None

CLK_HZ = 100_000_000
DEPTH = 4096

OP_ARM         = 0x01
OP_SET_DIVIDER = 0x02
OP_SET_TRIGGER = 0x03
OP_STATUS      = 0x04
OP_DUMP        = 0x05

RESP_ACK  = 0xAA
RESP_NACK = 0x00

TRIG_MODES = {
    "rising":  0b00,
    "falling": 0b01,
    "level":   0b10,
    "free":    0b11,
}


class ProtocolError(Exception):
    pass


class LogicAnalyzer:
    """One open serial link to the board, plus the five commands
    cmd_protocol.v understands. Every command that is not DUMP sends one
    byte and reads exactly one byte back, so the plumbing for those four
    is shared in _command(); DUMP gets its own method since it streams a
    fixed 4096 bytes back with no per-byte framing."""

    def __init__(self, port, baud=115200, timeout=2.0):
        if serial is None:
            raise RuntimeError(
                "pyserial is not installed. Run 'pip install pyserial' on "
                "the machine with the board attached, then try again."
            )
        self.link = serial.Serial(port, baudrate=baud, timeout=timeout)
        # the board's own reset_sync releases within a handful of clock
        # cycles, but giving the USB adapter a moment to settle after
        # opening the port avoids the first command landing on a half
        # configured link
        time.sleep(0.1)

    def close(self):
        self.link.close()

    def _command(self, opcode, payload=b""):
        self.link.write(bytes([opcode]) + payload)
        reply = self.link.read(1)
        if len(reply) != 1:
            raise ProtocolError(
                f"no reply to opcode 0x{opcode:02X}, check wiring and baud rate"
            )
        return reply[0]

    def arm(self):
        reply = self._command(OP_ARM)
        if reply != RESP_ACK:
            raise ProtocolError(f"ARM rejected, got 0x{reply:02X} instead of ACK")

    def set_divider(self, divider):
        if not (0 <= divider <= 0xFFFF):
            raise ValueError("divider must fit in 16 bits")
        payload = bytes([(divider >> 8) & 0xFF, divider & 0xFF])
        reply = self._command(OP_SET_DIVIDER, payload)
        if reply != RESP_ACK:
            raise ProtocolError(f"SET_DIVIDER rejected, got 0x{reply:02X}")

    def set_trigger(self, channel, mode):
        if not (0 <= channel <= 7):
            raise ValueError("channel must be 0 to 7")
        if mode not in TRIG_MODES:
            raise ValueError(f"mode must be one of {list(TRIG_MODES)}")
        packed = (channel << 5) | (TRIG_MODES[mode] << 3)
        reply = self._command(OP_SET_TRIGGER, bytes([packed]))
        if reply != RESP_ACK:
            raise ProtocolError(f"SET_TRIGGER rejected, got 0x{reply:02X}")

    def status(self):
        reply = self._command(OP_STATUS)
        return {
            "armed":     bool(reply & 0b001),
            "triggered": bool(reply & 0b010),
            "done":      bool(reply & 0b100),
        }

    def dump(self):
        self.link.write(bytes([OP_DUMP]))
        data = self.link.read(DEPTH)
        if len(data) != DEPTH:
            raise ProtocolError(
                f"dump returned {len(data)} bytes, expected {DEPTH}, "
                "check the baud rate and serial timeout"
            )
        return data

    def wait_done(self, timeout=5.0, poll_interval=0.02):
        deadline = time.time() + timeout
        while time.time() < deadline:
            st = self.status()
            if st["done"]:
                return st
            time.sleep(poll_interval)
        raise TimeoutError(
            f"capture did not finish within {timeout} s, trigger condition "
            "may never have been met"
        )

    def capture(self, rate_hz, channel, mode, timeout=5.0):
        """One full cycle: pick a sample rate, arm with the given trigger,
        wait for it to fire and the post-trigger half to fill, then pull
        the result back. Returns the raw 4096 byte capture."""
        divider = max(1, round(CLK_HZ / rate_hz))
        self.set_divider(divider)
        self.set_trigger(channel, mode)
        self.arm()
        self.wait_done(timeout=timeout)
        return self.dump()


def save_csv(path, samples):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["sample"] + [f"ch{i}" for i in range(8)])
        for i, byte in enumerate(samples):
            writer.writerow([i] + [(byte >> ch) & 1 for ch in range(8)])


def print_ascii(samples, channels, width=240):
    """A plain text waveform view, one row per channel, downsampled to
    fit a terminal width instead of printing all 4096 columns. Good
    enough to eyeball a trigger edge without needing a plotting
    library installed."""
    step = max(1, len(samples) // width)
    for ch in channels:
        row = []
        for i in range(0, len(samples), step):
            bit = (samples[i] >> ch) & 1
            row.append("#" if bit else ".")
        print(f"ch{ch}: " + "".join(row))


def main():
    parser = argparse.ArgumentParser(description="Logic analyzer host client")
    parser.add_argument("--port", required=True, help="serial port, e.g. COM5 or /dev/ttyUSB0")
    parser.add_argument("--baud", type=int, default=115200)
    parser.add_argument("--rate", type=float, default=1_000_000, help="target sample rate in Hz")
    parser.add_argument("--channel", type=int, default=0, help="trigger channel, 0 to 7")
    parser.add_argument("--mode", choices=list(TRIG_MODES), default="rising")
    parser.add_argument("--timeout", type=float, default=5.0, help="seconds to wait for the trigger")
    parser.add_argument("--out", default="capture.csv", help="CSV file to write the capture to")
    parser.add_argument("--ascii-channels", default="0,1,2,3",
                         help="comma separated channel list to print as ASCII waveforms")
    args = parser.parse_args()

    la = LogicAnalyzer(args.port, baud=args.baud)
    try:
        print(f"arming at {args.rate:,.0f} Hz, trigger on channel {args.channel}, mode {args.mode}")
        samples = la.capture(args.rate, args.channel, args.mode, timeout=args.timeout)
        print(f"captured {len(samples)} bytes")

        save_csv(args.out, samples)
        print(f"wrote {args.out}")

        channels = [int(c) for c in args.ascii_channels.split(",") if c.strip() != ""]
        print_ascii(samples, channels)
    finally:
        la.close()


if __name__ == "__main__":
    main()

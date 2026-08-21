#!/usr/bin/env python3
"""Кодирует строку для _BufferCodec.reveal([...])."""
import sys

KEY = [0xA7, 0x3E, 0x91, 0x5C, 0xD2]

def encode(value: str) -> list[int]:
    return [ord(c) ^ KEY[i % len(KEY)] for i, c in enumerate(value)]

if __name__ == "__main__":
    if len(sys.argv) != 2:
        print(f"Usage: {sys.argv[0]} \"string to encode\"", file=sys.stderr)
        sys.exit(1)
    encoded = encode(sys.argv[1])
    print(encoded)

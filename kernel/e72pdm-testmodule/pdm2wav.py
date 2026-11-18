#!/usr/bin/env python3
"""Decode an e72pdm capture (2 bits per clock: bit0 = after rising edge,
bit1 = after falling edge, LSB first) into two 16 kHz WAV files, one per
edge (= one per microphone: primary B2100 L/R=GND, secondary B2104 L/R=VDD).

usage: pdm2wav.py capture.bin clock_khz [out_prefix]
clock_khz = the average rate e72pdm printed. Simple 4th order CIC + DC block;
good enough to hear whether the mics work, not for final quality.
"""
import sys, wave
import numpy as np

def cic(bits, R, order=4):
    x = bits.astype(np.int64) * 2 - 1
    for _ in range(order):
        x = np.cumsum(x)
    x = x[R - 1::R]
    for _ in range(order):
        x = np.diff(x, prepend=0)
    return x / float(R ** order)

def main():
    raw = np.fromfile(sys.argv[1], dtype=np.uint8)
    fclk = float(sys.argv[2]) * 1000
    pre = sys.argv[3] if len(sys.argv) > 3 else 'pdm'
    bits = np.unpackbits(raw, bitorder='little')
    for name, edge in (('rise', bits[0::2]), ('fall', bits[1::2])):
        R = max(1, int(round(fclk / 16000)))
        y = cic(edge, R)
        y -= np.convolve(y, np.ones(256) / 256, mode='same')   # crude DC block
        y = y / (np.max(np.abs(y)) + 1e-9) * 0.9
        ones = edge.mean()
        with wave.open('%s_%s.wav' % (pre, name), 'wb') as w:
            w.setnchannels(1); w.setsampwidth(2); w.setframerate(int(fclk / R))
            w.writeframes((y * 32767).astype('<i2').tobytes())
        print('%s: density of ones %.3f (0.5 = live mic, 0/1 = stuck), %d samples at %d Hz'
              % (name, ones, len(y), int(fclk / R)))

if __name__ == '__main__':
    main()

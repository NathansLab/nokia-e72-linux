#!/bin/sh
# E72 audio bring-up probe (DRAFT, never run). busybox i2cget/i2cset/devmem on the phone.
#   probe   read-only: pad mux, clock gates, codec/amp/ALS/FM register reads        (silent)
#   clock   codec PLL + left DAC + beep generator with HP drivers OFF, reads flags    (silent)
#   beep    as clock, then HPL/HPR on at low gain: ~0.5 s 1 kHz in the EARPIECE       (AUDIBLE)
#   loop    EANC digital mics -> ADC -> DAC loopback into the earpiece (no I2S)        (AUDIBLE, may howl)
#   off     codec back to ISASW's parked state (HP off, DAC/ADC/PLL off, AVDD LDO off)
# Codec sequences follow ISASW hw_audio_aic3254.c (aic3254_isasw_sequence.txt); beep/loopback
# bits from TI SLAA408A (P0 R71-79 beep needs PRB_P25; P0 R29 bit 4 = ADC -> DAC loopback).
set -e
MODE=${1:-probe}
# i2c bus of the hs-i2c controller at 0x20032500
BUS=
for d in /sys/bus/i2c/devices/i2c-*; do
  case "$(readlink -f $d/of_node 2>/dev/null)" in
    *i2c@20032500) BUS=${d##*i2c-} ;;
  esac
done
[ -n "$BUS" ] || { echo "no i2c bus for 20032500"; exit 1; }
C=0x18
w() { i2cset -y $BUS $C $(printf 0x%02x $1) $2; }               # codec write (current page)
r() { i2cget -y $BUS $C $(printf 0x%02x $1); }
pg() { w 0x00 $1; }

probe() {
  echo "== pad mux words 0x20031810..0x200318f0 (decode with padmux.py dump)"
  a=$((0x20031810)); while [ $a -le $((0x200318f0)) ]; do printf '%08x ' $a; devmem $a 32; a=$((a+16)); done
  echo "== cgc gate regs (+0x180 +0x1b0 +0x1d0 +0x1e0 +0x280)"
  for o in 0x180 0x1b0 0x1d0 0x1e0 0x280; do printf 'cgc%s ' $o; devmem $((0x20032f00+o)) 32; done
  echo "== gpio 104 (EANC_RST) / 37 (AVPaEn) out latch banks 3 and 1"
  devmem $((0x20031990+0x30)) 32; devmem $((0x20031990+0x10)) 32
  echo "== codec 0x18 page 0 regs 0..127 / page 1 regs 0..127"
  pg 0; i2cdump -y -r 0-127 $BUS $C b || true
  pg 1; i2cdump -y -r 0-127 $BUS $C b || true; pg 0
  echo "== headphone amp 0x60 regs 1..4 (TPA6130A2 map: ver = reg4 & 0xf)"
  for x in 1 2 3 4; do i2cget -y $BUS 0x60 $x || true; done
  echo "== ALS 0x29 (TSL2563): id 0x8a, control 0x80, timing 0x81"
  for x in 0x8a 0x80 0x81; do i2cget -y $BUS 0x29 $x || true; done
  echo "== FM 0x22 (BCM2048 FM): reg 0 / 0x01 (may NACK while the BT chip keeps FM off)"
  for x in 0x00 0x01; do i2cget -y $BUS 0x22 $x || true; done
}

codec_on() {          # ISASW c6307e18 + c63079c8 + c6307a5e (reset is assumed done by Symbian/park)
  pg 0; w 1 0x01; sleep 1
  pg 1; w 1 0x00; w 2 0x28; w 123 0x01; w 10 0x63; w 11 0x00
  pg 0; w 55 0x04; w 53 0x10
  pg 1; w 2 0x21; usleep 2000 2>/dev/null || sleep 1; w 1 0x08
  pg 0; w 4 0x03; w 6 0x05; w 7 0x1d; w 8 0xb0; w 5 0xa1        # PLL 110.592 MHz from 38.4 MHz MCLK
}
dac_on() {            # DAC 48 kHz, PRB_P25 (beep capable), left DAC only, -30 dB digital
  pg 0; w 13 0x00; w 14 0x80; w 60 0x19; w 11 0x82; w 12 0x89
  w 65 0xc4; w 63 0x90; w 64 0x04
}
beep() {              # 1 kHz @ 48 kHz: sin = 0x10b5, cos = 0x7ee7 (Q15); 0.5 s = 24000 samples, -40 dB
  pg 0; w 76 0x10; w 77 0xb5; w 78 0x7e; w 79 0xe7
  w 73 0x00; w 74 0x5d; w 75 0xc0; w 72 0x80; w 71 0xa8          # bit 7 self-clears when done
}
hp_on() { pg 1; w 16 0x3a; w 17 0x3a; w 12 0x08; w 13 0x10; w 9 0x30; pg 0; }   # -6 dB, bridge
hp_off() { pg 1; w 9 0x00; w 12 0x00; w 13 0x00; pg 0; }
flags() { pg 0; echo "P0 R36 adc flags $(r 36)  R37 dac flags $(r 37)  R38 $(r 38)  R71 beep $(r 71)"; }
off() {
  hp_off; pg 0; w 64 0x0c; w 63 0x02; w 11 0x02; w 12 0x09; w 82 0x88; w 81 0x02; w 52 0x00; w 29 0x00
  w 5 0x00; pg 1; w 1 0x00; w 2 0x28; pg 0; w 55 0x04
}

case $MODE in
probe) probe;;
clock) codec_on; dac_on; sleep 1; flags; beep; flags; sleep 1; flags; off
       echo "expect R37 bit 7 (left DAC up) set and R71 bit 7 back to 0 -> MCLK + PLL + DAC run";;
beep)  [ "$2" = "--audible" ] || { echo "add --audible"; exit 1; }
       codec_on; dac_on; hp_on; sleep 1; beep; sleep 1; flags; off;;
loop)  [ "$2" = "--audible" ] || { echo "add --audible"; exit 1; }
       # needs VDigimic (inferred: gazoo dev1 reg 0x10 bit 4, ISASW c6307afa) - not set here
       codec_on; dac_on; pg 0; w 60 0x0c; w 65 0xb0
       # ADC_CLK = DAC_CLK (NADC off), MADC 18 -> 3.072 MHz mic clock, AOSR 64 -> 48 kHz;
       # PRB_R1 with AOSR 64: check SLAA408A filter table before use
       w 18 0x00; w 19 0x92; w 20 0x40; w 61 0x01; w 83 0x00; w 84 0x00
       w 52 0x28; w 82 0x08; w 81 0xde; w 29 0x10                    # left ADC -> DAC, right muted
       hp_on; sleep 3; flags; off;;
tone)  [ "$2" = "--audible" ] || { echo "add --audible"; exit 1; }
       # 3 s, DAC 0 dB, beep volume ${3:-0x14} (-20 dB default); polls the beep flag
       codec_on; dac_on; pg 0; w 65 0x00; hp_on; sleep 1
       pg 0; w 76 0x10; w 77 0xb5; w 78 0x7e; w 79 0xe7; w 73 0x02; w 74 0x32; w 75 0x80
       w 72 0x80; w 71 $(printf 0x%02x $(( 0x80 | ${3:-0x14} )))
       for i in 1 2 3 4 5; do flags; sleep 1; done; off;;
off)   off;;
esac

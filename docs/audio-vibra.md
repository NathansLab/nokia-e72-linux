# Audio and vibra

Status 2026-11-18. Everything here comes from static analysis of a RAM image of the running phone. None of it has run on the device yet.

## Vibra

- The motor sits on the Gazoo PMIC outputs VibraP/VibraN. The modem software's production test switches it through Gazoo device 2, register 0x10: bit 0 and bits 2:1 = 1 enable the driver, bit 5 drives VibraP, bit 4 VibraN. On = 0x23 in mask 0x37, off = 0. Never set bits 4 and 5 together. The other bits belong to accessory detection among others and are left alone.
- In normal use Symbian lets the DSP pulse the motor (strength -100..100 %). The Linux driver uses the DC path of the test only, so there is one strength.
- Driver: `kernel/patches/0008-input-e72-vibra.patch`, node `vibra` in `e72.dts`. Interfaces: force feedback (FF_RUMBLE) and `/sys/devices/platform/soc/soc:vibra/pulse_ms` (duration in ms, 0 = off). It switches off after 2 s at the latest and at shutdown. Shortcut: `vib [ms]`.

## Microphones

- Two digital PDM microphones share one data line (GPIO 39) and one clock (GPIO 72); their supply comes from the Gazoo. Under Symbian the DSP serves them; the ARM side has no register code for them.
- Silent first test: `kernel/e72pdm-testmodule/`. `mode=0` only reads both lines and counts level changes. `mode=1` bit-bangs the clock, samples the data and offers it as `/dev/e72pdm`; `pdm2wav.py` turns that into a WAV file. If the mic supply is off, the data line stays constant.
- Open: whether the mic supply is on under Linux and how to switch it; whether the pads are in GPIO mode. Bit-banging is too expensive for continuous use.

## Playback

- Earpiece: TLV320AIC3254 codec (I2C 2, address 0x18, reset on GPIO 104, I2S on GPIO 78-81).
- Headset: TPA6130A2 amplifier (I2C address 0x60), fed by the Gazoo.
- Speaker: class-D stage inside the Gazoo; its registers are not decoded.
- Under Symbian all PCM goes through the DSP. Whether the earpiece codec can be fed from the ARM side over I2S is not determined.

## Sound without the DSP (second analysis, 2026-11-18)

- No serial audio block that the ARM side can program is known. The candidates (`0x20020500`, `0x20020700`, `0x20020b00`, with DMA request lines next to the SPI blocks) are not touched by any ARM code; their layout and reachability are not determined. So there is no ALSA driver yet.
- The earpiece codec can make sound on its own over I2C, needing only its 38.4 MHz clock: its beep generator, or a loop from its own digital microphones to the earpiece. The modem software's full register sequence is in `audio/aic3254_isasw_sequence.txt`, the test script in `audio/e72-audio-probe.sh` (`probe` and `clock` are silent, `beep` and `loop` require `--audible`). Whether the clock runs under Linux is open. Nothing of this has run.
- Headphone amplifier (0x60): the RAM image holds a detection response that does not fit a TPA6130A2. Read its registers before trusting the mainline driver. Its input comes only from the Gazoo.
- Pad mux found: a 4-bit field per pin in the word at `0x20031810 + (pin>>3)*0x10` (set +4, clear +8); `audio/padmux.py` converts.
- The sensor at 0x29 is a TSL2563 ambient light sensor. Driver and node are in the kernel; `e72-lights` sets display brightness and keyboard light from it. Not yet run.
- The FM radio is the BCM2048 inside the Bluetooth chip; kernel 6.12 has no driver for it.
- Vibra re-checked: 0x23 in mask 0x37 is the complete "on"; both bridge halves can never be on together.

## On-device test (2026-11-18)

- The codec answers at 0x18. The 38.4 MHz master clock (MCLK) is off under Linux; bits 6 and 7 of cgc+0x180 switch it on: `devmem 0x20033084 32 0xc0`, off with `devmem 0x20033088 32 0xc0`. Never write 0x20033080 itself.
- Even with the clock on, the beep bit (P0 R71 bit 7) does not clear; whether a tone is audible is open.
- Headphone amplifier 0x60 and FM chip 0x22 do not answer when idle.
- Vibra: the driver loads, the register switches to 0x23 and back to 0.
- busybox `i2cset` on the phone rejects some decimal numbers; the script converts register numbers to hex. New mode `tone` (3 s, louder).

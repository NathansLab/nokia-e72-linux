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

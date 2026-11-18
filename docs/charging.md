# Battery and charging

Verified on the device on 2026-11-18 (RM-530, firmware 091.004): with a USB host attached, Linux charges the battery (about +390 mA into the cell at 3.9 V while WLAN and SSH are running).

## Hardware

| Part | Value | Source |
| --- | --- | --- |
| Charger | TI bq24151 (N3301), I2C address 0x6b | ISASW chip check, live RAM dump; Linux reports `chip bq24151, revision 1.3` |
| Bus | ISASW HS-I2C port 3 at `0x20032500`, same clock and pad setup as the Nokia E6 | ISASW port table |
| Sense resistor | 68 mOhm | matches the firmware's current encoding (550 mA + 100 mA steps) |
| OTG pin | strapped low, no enable GPIO | |
| Battery | BP-4L, 1500 mAh nominal | |
| Measurement | Gazoo ADC over CBUS (same as the E5) | |

What the Symbian firmware programs: 4.16 V regulation voltage (4.06 V outside 15-39 °C), 550 mA charge current from a USB host, 500 mA input limit after enumeration, 150 mA termination, 3.4 V weak-battery threshold. It never writes the safety-limit register. It stops charging below 5 °C and above 54 °C.

## What Linux does

- `e72.dts` adds the I2C port and a `ti,bq24151` node: 4.1 V, 550 mA, 500 mA input limit, 150 mA termination. 4.1 V is below the firmware's own value on purpose.
- The upstream `bq2415x` driver (with the changes from the E6 port) only charges when the USB gadget is enumerated with a 500 mA budget and the battery is between 5 and 40 °C. It services the chip's 32 s watchdog; if Linux hangs, the chip falls back to its defaults by itself.
- Patch 0007 makes `g_cdc` a bus-powered gadget. As a self-powered gadget it asked the host for 0 mA and the driver never started charging.
- Patch 0005 adds the E72 calibration to `rapuyama-battery.c`: voltage `mV = 2.06353 * raw + 2731.84`, the NTC table, the 18-point capacity curve and the 3300 mV power-off limit. All four come from running the firmware's own scaler and reading its battery-monitor table. The E5 calibration reads 68 mV low on the E72.

```
cat /sys/class/power_supply/battery/{status,voltage_now,capacity,temp,current_now}
cat /sys/class/power_supply/bq24151-0/{mode,charge_status,fault_status}
```

## Not done

- A wall charger on the USB socket is not detected (no enumeration, so no charging).
- The 2 mm barrel jack charges through the Gazoo PMIC, not the bq24151. That path is not analysed; do not rely on it under Linux.
- The battery's internal resistance (`ibat_mohm`) is still the E5's value, so the percentage sags a little under load.

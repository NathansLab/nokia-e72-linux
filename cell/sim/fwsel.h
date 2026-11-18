/* Firmware selection for the e5rt runtime (sim/ sources). Default: Nokia E5 fw 101.003 (unchanged build).
 * -DE72_FW091004: Nokia E72 (RM-530) fw 091.004, addresses from e72_fw091004.h, and before any patch or
 * call e72_fw_check() compares every mapped code address with the bytes of the fw 091.004 dump
 * (e72_fw091004_check.h); a mismatch is a clean refusal to start ("unsupported firmware").
 * FW(e5, e72) picks the value; the unused argument is never evaluated. */
#ifndef FWSEL_H
#define FWSEL_H
#ifdef E72_FW091004
#include "e72_fw091004.h"
#define FW(e5, e72) (e72)
#define FW_E72 1
#define FW_DEVICE "E72"
#else
#define FW(e5, e72) (e5)
#define FW_E72 0
#define FW_DEVICE "E5"
#endif
/* measurement tap (meas_tap.h): built into the E72 runtime, off unless E5RT_MEAS_TAP is set */
#ifndef MEAS_TAP
#define MEAS_TAP FW_E72
#endif
#endif

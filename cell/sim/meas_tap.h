/* Measurement tap (waterfall groundwork): copies of chosen DSP->AP frames out of the MDI pump.
 * Off by default. E5RT_MEAS_TAP=<file or FIFO> turns it on; E5RT_MEAS_FILTER=dev:res[,dev:res..] picks the
 * frames by the Phonet-like header of the DSP payload (byte 2 = sender device, byte 3 = resource; '*' = any;
 * "all" = every rx descriptor), default 7c:38 (DSP L1 measurement results, msg 0x15 among them).
 * The pump only memcpy's into a lock-free ring (no syscall, no lock, never blocks the DSP link); a separate
 * thread writes the records. Ring full or no reader on the FIFO yet: the record is dropped and counted.
 *
 * Stream format (version 1, little-endian, records back to back, each 4-byte aligned):
 *   off size field
 *    0   4   magic      0x544d3545 ("E5MT")
 *    4   1   version    1
 *    5   1   flags      bit0 = payload copied from the DSP window, bit1 = payload truncated to MEAS_TAP_CAP
 *    6   2   hdr_len    48 (payload starts here; readers skip unknown header growth with it)
 *    8   4   seq        record number since start (gaps = records dropped by a full ring)
 *   12   4   dropped    records dropped so far
 *   16   8   t_us       CLOCK_MONOTONIC in microseconds when the pump read the descriptor
 *   24  16   desc[4]    the raw MDI rx descriptor (desc[3] = DSP address of the payload)
 *   40   2   len        payload bytes in this record
 *   42   2   orig_len   payload length from the frame header (bytes 4..5 LE + 6), 0 if unknown
 *   44   1   dev        payload byte 2 (sender device, 0x7c = DSP), 0xff if no payload
 *   45   1   res        payload byte 3 (resource)
 *   46   1   msg        payload byte 6 (first body byte), 0xff if no payload
 *   47   1   reserved   0
 *   48  len  payload    the frame as the firmware got it (Phonet-like header + ISI body), then 0..3 pad bytes
 * A viewer resyncs on the magic. No IMEI/IMSI-bearing resources are in the default filter; with "all" the
 * file may contain subscriber data and stays private. */
#ifndef E5RT_MEAS_TAP_H
#define E5RT_MEAS_TAP_H
#include <stdint.h>
#define MEAS_TAP_MAGIC 0x544d3545u
#define MEAS_TAP_VERSION 1
#define MEAS_TAP_HDR 48
#define MEAS_TAP_CAP 1008	/* payload bytes per record */
#define MEAS_TAP_SLOTS 64	/* ring: 64 x 1056 bytes */
struct meas_tap_hdr {
	uint32_t magic;
	uint8_t version, flags;
	uint16_t hdr_len;
	uint32_t seq, dropped;
	uint64_t t_us;
	uint32_t desc[4];
	uint16_t len, orig_len;
	uint8_t dev, res, msg, reserved;
};
_Static_assert(sizeof(struct meas_tap_hdr) == MEAS_TAP_HDR, "meas tap header layout");
/* from the environment; returns 0 when off (then meas_tap_frame is a no-op) */
int meas_tap_init(void);
/* pump side: desc = rx descriptor, payload = its bytes in the private DSP window or NULL, avail = bytes readable there */
void meas_tap_frame(const uint32_t desc[4], const uint8_t *payload, uint32_t avail, uint64_t t_us);
/* flush what is queued and stop the writer (atexit) */
void meas_tap_close(void);
#endif

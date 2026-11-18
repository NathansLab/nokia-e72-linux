/* Nokia E72 (RM-530) fw 091.004: the E5 fw 101.003 addresses the e5rt runtime uses, mapped to the
 * E72 ISASW. Derived from a RAM dump of the running Symbian (2026-11-18, dump1) with the E72 page
 * tables, the thumb call graph and the E5 runtime's own byte checks. NOT phone-tested.
 * Confidence per line: C = confirmed (exact E5 byte check, unique semantics or exact caller count),
 * I = inferred (region delta of confirmed neighbours + plausible shape), N = not determined (0).
 * The E72 ISASW is NOT the E5 one shifted by one delta: code deltas run from +0x1738 (task 28) over
 * +0x4f88..+0x5944 to +0x76e4 (KASUMI) and +0xcaec (const tables); data deltas +0x2c..+0x5c8.
 * Full table with evidence: cell/e72-addr-table.tsv.
 * Physical layout = E5 with the top of RAM at 0x18000000 instead of 0x20000000 (RY_TOP), except the
 * code size, the SIM patch window and the SBIF RAM drives. */
#ifndef E72_FW091004_H
#define E72_FW091004_H

/* images (e5mem/e72mem debugfs names = physical addresses) */
#define E72_CODE		0xc6300000u	/* C pa 0x10480000 */
#define E72_CODE_SIZE		0x3bb000u	/* C (E5 0x3ae000), code end c66bb000 */
#define E72_DATA		0xc6800000u	/* C pa 0x17d50000 (E5 0x1fd50000) */
#define E72_DATA_PA		0x17d50000u
#define E72_DATA_SIZE		0x280000u	/* C */
#define E72_SECURE		0xc6b00000u	/* C pa 0x17fe0000, 0x10000 */
#define E72_SIM_PATCH_PA	0x100db000u	/* C va c60f0000 (E5 pa 0x100ec000), 0x2000 */
#define E72_SIM_PATCH_END	0xc60f0db0u	/* C end of code in the SIM patch window (E5 c60f0db8): the blob ends with ARM
					   ldr pc veneers into the ISASW, highest referenced entry c60f0ca9, then zeros/state */
#define E72_TOP_PA		0x17b60000u	/* C 0x180000, holds DSP pool 2 at pa 0x17c90000 (va cb580000) */
#define E72_RAMDRIVES_PA	0x11300000u	/* C va cb600000, 0xfc000 (E5 pa 0x11200000), below Linux RAM */
#define E72_DSP_BUF		0xcb500000u	/* C pa 0x10140000, 0x80000 (same as E5) */
#define E72_MDI_AP		0xc601bce0u	/* C pa 0x30003ce0 (same) */
#define E72_MDI_DSP		0xc601bdf0u	/* C pa 0x30003df0 (same) */
#define E72_MDI_STATE		0xc683aa08u	/* C E5 c683a440 */
#define E72_SWD_STACK		0xe4000u	/* I data offset, PA_SWD parked sp c68e9e6c (E5 0xd2000) */

/* core (e5rt-sim.c) */
#define E72_FW_ALLOCATE		0xc63cbd41u	/* C E5 c63c646d */
#define E72_FW_RELEASE		0xc63cc293u	/* C E5 c63c69bf, 3031 callers */
#define E72_FW_SEND		0xc636056fu	/* C E5 c635b4e3 */
#define E72_FW_TO_HOST		0xc6360549u	/* C E5 c635b4bd */
#define E72_FW_RECEIVE		0xc63c4829u	/* C E5 c63bef51 */
#define E72_FW_SCHEDULE		0xc63c230fu	/* I E5 c63bca37 */
#define E72_FW_CURRENT_TASK	0xc63c34a1u	/* C E5 c63bdbc9 */
#define E72_FW_SEND_TASK	0xc63c34bcu	/* C E5 c63bdbe4, entry f0b5 85b0 0446 0d46 */
#define E72_FW_MDI_RX_IRQ	0xc63ce841u	/* C E5 c63c8f6d, irq 0x13 */
#define E72_FW_MDI_TX_IRQ	0xc63ce905u	/* C E5 c63c9031, irq 0x15 */
#define E72_FW_MDI_EVENT_IRQ	0xc63ce6e1u	/* C E5 c63c8e0d, irq 0x17 */
#define E72_FW_RING_DUMP	0xc63cf604u	/* C E5 c63c9d30 */
#define E72_FW_ASSERT		0xc63de19cu	/* I E5 c63d8864, (expr, file, line) */
#define E72_FW_RESET		0xc63dd4ecu	/* C E5 c63d7be4 */
#define E72_RESET_A_SITE	0xc6359a7au	/* C E5 c6354a02: movs r0,#0xa; bl reset */
#define E72_STACK_GUARDS	0xc667f050u	/* C E5 c6672564 */
#define E72_TASK_TABLE		0xc667f50cu	/* C E5 c6672a20, 48 x 16 */
#define E72_SCHED		0xc6836204u	/* C E5 c6835c3c */
#define E72_HOST_QUEUE		0xc6836e00u	/* I E5 c6836838 (queue array c6836820 + 0x2f * 0x20) */
#define E72_TASK26_ENTRY	0xc63cf939u	/* C E5 c63ca065 */
#define E72_TASK28_ENTRY	0xc632aac1u	/* C E5 c6329389 */
#define E72_TASK34_ENTRY	0xc63ce429u	/* C E5 c63c8b75 */

/* patches() */
#define E72_CRIT_EXIT		0xc63ddcf4u	/* C E5 c63d83cc */
#define E72_CRIT_ENTER		0xc63ddd02u	/* C E5 c63d83da */
#define E72_C6033340_HELPER	0xc63bf592u	/* C E5 c63b9d16 */
#define E72_INTC_NOP_1		0xc63bf436u	/* C E5 c63b9bba */
#define E72_INTC_NOP_2		0xc63bf576u	/* C E5 c63b9cfa */
#define E72_GET_CPSR		0xc66603c4u	/* C E5 c6658ce4 (ARM) */
#define E72_CACHE_BARRIER	0xc6660484u	/* C E5 c6658da4 (ARM) */
#define E72_DSP_INVALIDATE	0xc66604acu	/* C E5 c6658dcc (thumb veneer -> slot 0x68) */
#define E72_HOST_SVC_58		0xc63f10ccu	/* C E5 c63ec10c; 5c c63f10fe, 60 c63f113c, 64 c63f117a, 68 c63f11b8 */
#define E72_HOST_SVC_MOVS0	0xc63f141cu	/* I E5 c63ec494 (last wrapper, slot 0x74 here) */
#define E72_HOST_IRQ_BIND	0xc63f0f04u	/* C E5 c63ebf44; check bytes f8b5 0446 0d46 dc4f (E5 d44f) */
#define E72_HOST_V2P		0xc63f0f7au	/* I E5 c63ebfba (slot 3) */

/* sim_runtime.c */
#define E72_IRQ_REGISTER	0xc63ddd10u	/* C E5 c63d83e8 */
#define E72_IRQ_ENABLE		0xc63ddd6au	/* C E5 c63d8442 */
#define E72_IRQ_DISABLE		0xc63ddd88u	/* C E5 c63d8460 */
#define E72_DELAY		0xc63dd412u	/* I E5 c63d7ace */
#define E72_SIM_TIMER_CREATE	0xc63dc7c0u	/* I E5 c63d6ec0 */
#define E72_SIM_TIMER_CANCEL	0xc63dc8bau	/* I E5 c63d6fba */
#define E72_SIM_TIMER_REMAINING	0xc63dc984u	/* I E5 c63d7084 */
#define E72_ADC_READ		0xc63f14bcu	/* C E5 c63ec534 */
#define E72_ADC_MAP_LITERAL	0xc63f1568u	/* C E5 c63ec5e0 -> map c66840ec, byte-identical */
#define E72_PMIC_WRITE		0xc63f15d2u	/* C E5 c63ec64a */
#define E72_PMIC_READ		0xc63f1638u	/* C E5 c63ec6b0 */
#define E72_PMIC_IRQ_TABLE	0xc683d7c8u	/* C E5 c683d280 */
#define E72_SIM_OWNER_DONE	0xc63917fcu	/* I E5 c638bfa0 */
#define E72_SIM_TXN_DONE	0xc6391ad0u	/* I E5 c638c270 */
#define E72_SIM_START		0xc639257fu	/* I E5 c638cd1f */
#define E72_SIM_WAKE		0xc6392777u	/* I E5 c638cf17 */
#define E72_SIM_WAKE_SITE	0xc6392796u	/* C E5 c638cf36 */
#define E72_SIM_COLD_RESET	0xc63928cbu	/* I E5 c638d06b */
#define E72_SIM_POOL		0xc6392aa0u	/* C E5 c638d240 (6 handlers, same values) */
#define E72_SIM_CTX_LITERAL	0xc6392cccu	/* I E5 c638d46c */
/* SIM IRQ callbacks (b3 c60f07db, b4 c60f0361, b6 c60f03d9, b5 c60f048d) and PMIC SIM ids 13/14/15
 * (c60f08f3/0aed/094b): identical values on the E72 (C) */

/* os_timer_runtime.c: 237 ids, 240 pool slots, owners/ids identical to the E5 (C) */
#define E72_OS_TABLE		0xc6833454u	/* C E5 c6832e8c */
#define E72_COPIED_POOL		0xc6834f34u	/* C E5 c683496c */
#define E72_OS_START		0xc63bff13u	/* I E5 c63ba68f */
#define E72_OS_STOP		0xc63c01d3u	/* I E5 c63ba94f */
#define E72_OS_ELAPSED		0xc63bfcb8u	/* I E5 c63ba434 */
#define E72_OS_REBASE		0xc63c10c2u	/* I E5 c63bb852 */
#define E72_TIMER_CREATE	0xc63c1120u	/* C E5 c63bb89c */
#define E72_TIMER_CANCEL	0xc63c11d8u	/* C E5 c63bb954 */
#define E72_TIMER_REMAINING	0xc63c12e4u	/* C E5 c63bba60 */
#define E72_TIMER_NEXT_REMAINING 0xc63c1422u	/* I E5 c63bbb9e */

/* identity_runtime.c (the IMEI comes from E5RT_IMEI_FILE only, never from Symbian) */
#define E72_IDENTITY_READER	0xc636f79eu	/* C E5 c636a06e, 12-byte check exact */
#define E72_SECURE_CALL		0xc6371128u	/* C E5 c636b908, 8-byte check exact */
#define E72_SECURE_ITEM_SIZE	0xc636fde4u	/* C E5 c636a9e6 (module 0x12): caller c6368114 (E5 c6363064) -> reader
					   c6368000 -> this stub; its title literal c6678b60 names module 0x12;
					   entry fe b5 05 46 0e 46 60 4c 5e 48 a0 60 (E5: 9a 4c 9b 48) */
#define E72_SECURE_TABLE_PTR	0xc68316ccu	/* C E5 c6831104 */

/* kasumi_runtime.c: whole block +0x76e4 (C) */
#define E72_KASUMI_F8_WRAPPER	0xc665cab9u
#define E72_KASUMI_SELECTOR	0xc665cb0au
#define E72_KASUMI_BL8_SITE	0xc665cb1cu
#define E72_KASUMI_HW_BLOCK8	0xc665cb24u	/* I */
#define E72_KASUMI_F9		0xc665cbabu
#define E72_KASUMI_F9_BLO	0xc665cbecu
#define E72_KASUMI_BL9_SITE	0xc665cc00u
#define E72_KASUMI_HW_BLOCK9	0xc665cc08u	/* I */
#define E72_KASUMI_F8_BATCH	0xc665d190u
#define E72_KASUMI_CIPHER	0xc665d37fu
#define E72_KASUMI_KEYSCHED	0xc665d3f3u
#define E72_KASUMI_SW_F8	0xc665d53du
#define E72_KASUMI_SW_F9	0xc665d5f7u

/* SBIF */
#define E72_SBIF_API		0xc634bce7u	/* I E5 c6346c37 */
#define E72_SBIF_CONTROL	0xc682c034u	/* I E5 c682baa4 */
#define E72_RAMDRIVE_TABLE	0xc6823f68u	/* C E5 c6823f3c */

/* debug only, not determined: fw trace flags (E5 c685978c), fw trace sink I c635a34c (E5 c63552d4),
 * soak diagnostics (E5 c636b107, c6563b85, c6564083) */
#define E72_FW_TRACE_SINK	0xc635a34cu	/* I */

/* added for the FW() switch (fwsel.h) */
#define E72_CODE_END		0xc66bb000u	/* C end of the contiguous code mapping (E5 c66ae000) */
#define E72_SECURE_PA		0x17fe0000u	/* C */
#define E72_POOL2_PA		0x17c90000u	/* C DSP pool 2 (va cb580000) = E72_TOP_PA + 0x130000 */
#define E72_HOST_SVC_5C		0xc63f10feu	/* C */
#define E72_HOST_SVC_60		0xc63f113cu	/* C */
#define E72_HOST_SVC_64		0xc63f117au	/* C */
#define E72_HOST_SVC_68		0xc63f11b8u	/* C */
#define E72_RAMDRIVES_DUMP_OFF	0x100000u	/* drives at pa 0x11300000 = low-11200000.bin + 0x100000 */
#define E72_SIM_TX_ZALLOC	0xc63d911au	/* I zero-filled allocation (alloc c63d90d4 + memset), freed by c63d912c ->
					   release; the SIM server takes its per-transaction tx buffer (ctx+4) from it */
/* HS-I2C HAL (hal_i2c_hsi2c.c): port 3 = pa 0x20032500 = Linux i2c3 (bq24151 0x6b), port 2 = pa 0x20032300.
   Port 3 clients: em_hal_cha.c charger read/write c633229a/c633231e (0x6b, 0x6a), sensor_srv.c (0x29),
   hw_audio_aic3254 (0x18), hw_radio_bcm2048/tea5761 (0x22), test code (0x60). The six request entries
   (same prologue ff b5 85 b0 04 46 16 46 1f 46) are stubbed to return the HAL's own "queue full" status 2
   (c63eefd4) without touching the controller: e5rt never gets the real bus. */
#define E72_I2C_REQ_1		0xc63eedfau	/* C 13 callers (sensor, audio, radio, charger write) */
#define E72_I2C_REQ_2		0xc63eee7cu	/* C 5 callers */
#define E72_I2C_REQ_3		0xc63eeedcu	/* C 4 callers */
#define E72_I2C_REQ_4		0xc63eef3au	/* C no direct callers */
#define E72_I2C_REQ_5		0xc63eef98u	/* C 11 callers (charger read, sensor, audio, radio) */
#define E72_I2C_REQ_6		0xc63eeff6u	/* C no direct callers */
#define E72_I2C_QUEUE_FULL	2u
/* debug-only hooks, not mapped: disabled in the E72 build (E5RT_FW_TRACE, the --os-soak fw/secure/dsp-get
   diagnostics and the hs-trace veneer selftest are refused or skipped) */
#define E72_FW_TRACE_FLAGS	0u		/* N */
#define E72_SOAK_DEVLOCK	0u		/* N (E5 c636b107) */
#define E72_SOAK_INVALIDATE	0u		/* N (E5 c6564083) */
#define E72_SOAK_PRINT_A5	0u		/* N (E5 c6563b85) */
#endif

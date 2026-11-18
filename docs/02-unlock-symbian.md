# 2. Allow self-signed apps on Symbian

LinuxE72 and the diagnostic apps load their own kernel-side driver (LDD) and need all capabilities. They are signed with your own self-signed certificate, and a stock Symbian 9.3 refuses to install them. The phone needs RomPatcher+ with the **Install Server** patch.

On firmware 091.004 **HelloOX does not work** (Nokia closed that hole after 023.002). This project used the **Trend Micro Mobile Security method**, which needs no SIM card, as described in the LPC wiki page [Jailbreaking S60 devices](https://lpcwiki.miraheze.org/wiki/Jailbreaking_S60_devices) (Nokia section). Get the files from the download folder linked on that page; they are third-party software and are not part of this repository:

- X-plore for S60 3rd edition (`x-plore_s60_3rd_1_64.sisx`)
- `tmquarantine.zip`
- `Mobile Security.sis` (Trend Micro)
- `RomPatcherPlus_3.1_LiteVersion.sisx`

Follow the wiki if it differs from the summary below; this is the sequence that worked on the E72 used here:

1. **Settings in the App manager:** Software installation: **All**.
2. **Install X-plore.** If it fails with a certificate error, set the phone's date to 2022 and try again.
3. In X-plore: **Tools → Configuration**, tick the two topmost options (shows the system drives `C:` and `Z:`).
4. Extract `tmquarantine.zip` to `C:\` with X-plore. The result must be `C:\tmquarantine\`.
5. Set the date to **31.12.2012**, install `Mobile Security.sis`, **decline the restart**.
6. Start Mobile Security → **Options → Quarantine list → Restore all files**. Then uninstall Mobile Security.
7. Install **RomPatcher+**, start it, apply **Install Server RP+** and **Open4All RP+**, and choose **Add to Auto** for both (green tick).
8. Set the date back to today. App manager → settings: **Online certificate check: Off**.

## Check

Install any self-signed `.sis` you built in step 3 (for example `e72logs.sis`). If Symbian says **"file corrupted"**:

- Check the signature first. A certificate with RSA 2048 / SHA-256 produced exactly this message here; RSA 1024 / SHA-1 works (see [03-build.md](03-build.md#signing-certificate)).
- Check that both patches have a green tick in RomPatcher+.

Always install to the **phone memory (C:)**, not to the memory card.

Next: [3. Build](03-build.md)

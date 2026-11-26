# PayDay — recurring payments on autopilot

**Reactive Omni Buildathon** (Reactive Network × DoraHacks) — Track: **Set It and Forget It**.
Deadline submit: **5 Des 2026, 20:00 UTC = 6 Des 03:00 WIB**. Hadiah track: $2.000 juara / $250 runner-up (dibayar REACT).

Buat sekali, lupakan: pemilik membuat rencana pembayaran berulang (penerima + jumlah ETH + interval), dana escrow di Base Sepolia. Reactive contract di Lasna mengecek rencana yang jatuh tempo tiap tick CRON100 (~2 menit) dan meminta callback ke `PayDayPayer` di Base Sepolia, yang membayar penerima dari escrow. Tanpa bot, tanpa server, tanpa keeper.

## Arsitektur

```
CRON100 tick (Lasna, ~2 mnt)
  → PayDayReactive.react()               (Reactive Lasna, chain 5318007)
  → SYSTEM.requestCallbackV_1_0
  → PayDayPayer.pay()                    (Base Sepolia, chain 84532)
  → ETH sampai ke penerima (event Paid)
```

| Kontrak | Chain | Peran |
| --- | --- | --- |
| `PayDayReactive` | Reactive Lasna (5318007) | Subscribe CRON100, cek rencana jatuh tempo, minta callback |
| `PayDayPayer` | Base Sepolia (84532) | Terima callback, bayar penerima dari escrow |

## Kontrak live (testnet)

| | Alamat | Explorer |
| --- | --- | --- |
| PayDayReactive | `0x47800f60e6b135813Ff3fa68fe3cD3AF50C6264f` | https://lasna.reactscan.net/address/0x47800f60e6b135813Ff3fa68fe3cD3AF50C6264f |
| PayDayPayer | `0x68be47672e809c7803c508451f66ba2907f210d5` | https://sepolia.basescan.org/address/0x68be47672e809c7803c508451f66ba2907f210d5 |

Deploy tx: Reactive `0xbbc020d74151f4c2e838086d48709f5ade4a1b4b43f9bb5f3c26c5aa05252917` (Lasna) · Payer `0x031f16b3b10be37876d08bf90690d7d7a5335d8b5387db3ba74d78c0510ed9b6` (Base Sepolia) · wiring `setPayer()` `0xccdc25e537a1a62feeb299d5b99f26c5416cfbc49bfaf7b70e1f9249a924d0dd`.
**Sourcify: keduanya `exact_match`.**

## Loop penuh — terbukti on-chain

Plan demo #2: penerima wallet agen, **0,00002 ETH tiap 60 detik** (create tx `0x201f08fcdc637992cbcb028978c2035e1ea13538f12b969e27a3ac806795155d`, Lasna blok 9269888).

| Langkah | Tx | Blok |
| --- | --- | --- |
| CRON100 tick → react (from relayer `0x038E…`, BUKAN wallet agen) | `0x588a597a9a8da80d8a24e54aedaf97b4aed2fd68096000ccae23665541653e5d` | Lasna 9270001 |
| Callback → **Paid 0,00002 ETH** (from relayer `0xF9F6…` ke callback proxy) | `0x7ecbf58491a50637f35b9daa13511672f9c4075dc7b790894598e70f353fc47d` | Base Sepolia 63726005 |

Plan #2 dibayar **4× total** (0,00008 ETH): `0x7ecbf584…`, `0x475991e4eab38dd15aec93ce1f96e417dcf896ee9bd3282f8579a8b370ecb64e`, `0x8bd6d95251200c423ea273fa3d69a6eee4b3c2fc52d5c1326553f19407bcecee`, `0x28f0a6d680081c44c74d3bd6497c1cba3af9c34dbe9adbdeb84dbe0ccfbaed9e`. Escrow akhir 0,0000138 ETH; automation di-`pause()` setelah demo (tx `0x5c9e051c01fde90b66c4a632c85a3820c0a3ec96386f3a3bc27fa1e52d65ff6c`, Lasna blok 9270307).

Loop tahap 2 (plan #0, 0,0001 ETH): react `0x62b7e1c9913b048df4bfbd893ed09a9670082f4717b1ab2e9e709fae8e507f5c` → callback `0x362325428f019954604d91abe8c796a53ad5eb8c5106bf08a8cb0ffaad950dfe` → Paid. Detail lengkap: `NOTES.md` §8.

## Video demo

`video/payday-demo.mp4` — **2 menit 8 detik** (< 3 menit), narasi Inggris, alur nyata: buat plan → tunggu tick CRON → pembayaran masuk. Link YouTube (untuk form submit) akan ditambahkan setelah upload.

## Frontend

`frontend/` — halaman statis (ethers v6, di-vendor): alamat kontrak + link explorer, daftar plan on-chain, buat plan (MetaMask), saldo escrow, status automation, aktivitas terbaru. Jalankan lokal:

```bash
python3 -m http.server 8123   # dari root repo
# buka http://127.0.0.1:8123/frontend/index.html
```

Terverifikasi lokal 26 Nov: 0 console error, 0 failed request, data kontrak kebaca (escrow, saldo lREACT, plan, aktivitas Paid/Skipped/PaymentRequested).

## Status

- ✅ Tahap 1 (26 Nov): aturan terverifikasi, konsep PayDay, scaffold.
- ✅ Tahap 2 (26 Nov): `forge build` hijau, `forge test` **11/11 PASS**, deploy Lasna + Base Sepolia, loop penuh 3× Paid terbukti.
- ✅ Tahap 3 (26 Nov): frontend + uji lokal lolos, video demo 2:08 + narasi, README + SUBMIT-READY.md, commit lokal.
- Registrasi DoraHacks **SELESAI** (akun jepee, track Set It and Forget It, solo).
- ⏳ Sisa sebelum submit (5 Des): buat repo GitHub publik `payday-reactive` + upload, upload video demo ke YouTube (Unlisted/Publik), isi form Submit Build di DoraHacks.

## Perintah

```bash
forge build
forge test
# Deploy (urutan penting):
# 1. PayDayReactive ke Lasna → catat alamatnya
# 2. PayDayPayer ke Base Sepolia (bawa alamat proxy + alamat reactive)
# 3. setPayer() di reactive
# 4. Fund keduanya (reactive: lREACT via faucet; payer: escrow ETH Base Sepolia)
# 5. Verifikasi Sourcify keduanya
```

## Faucet lREACT

Kirim Sepolia ETH ke `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` (Eth Sepolia) atau `0x2afaFD298b23b62760711756088F75B7409f5967` (Base Sepolia). Kurs 1 ETH → 100 lREACT, maks 5 ETH/tx.

## Submit (DoraHacks)

Repo publik + alamat kontrak ter-deploy + tx hash loop penuh (origin event → callback) + video demo <3 menit. Paket lengkap: `SUBMIT-READY.md`.

## Lisensi

MIT.

# Certificate Toolkit

[![tests](https://github.com/4625tracker/CSRG-GUI/actions/workflows/tests.yml/badge.svg)](https://github.com/4625tracker/CSRG-GUI/actions/workflows/tests.yml)

A focused GUI + CLI for the certificate workflow that Windows does not make
convenient: **build a CSR with the right EKU and SAN**, then **merge the
CA-issued certificate back with your private key** into a PFX or a combined PEM.

It is a single-folder PowerShell application — no installation, no build step,
no dependencies beyond PowerShell itself.

[中文说明](README.zh-CN.md) · [使用说明 (详细中文手册)](使用说明.txt)

---

## Why this exists

Issuing a certificate on Windows involves two separate, error-prone steps:

1. `certreq -new` writes the private key into a **key container** — but there is
   no certificate yet, so the key is *orphaned*. Its container name is a random
   `tq-<GUID>` and nothing records which CSR it belongs to.
2. The CA returns a `.cer` that contains **only the public key**. You must merge
   it with that hidden private key before IIS, nginx, or an mTLS client can use it.

This toolkit handles both steps, and it can find that orphaned key again by
comparing public keys against every container on the machine.

## Features

- **CSR generation with multiple EKU** — the multi-EKU INF encoding that actually
  works (`[EnhancedKeyUsageExtension]`, one `OID=` per line); comma-joined or
  repeated lines are rejected by `certreq`.
- **SAN support** — `dns`, `ipaddress`, `email`, `upn`, `URL`, including UPN as
  `otherName`, built as hand-written DER so it behaves identically everywhere.
- **Two CSR backends**
  - `certreq` (default on Windows) — private key stays in the local key container.
  - `.NET` (**portable mode**) — the key is generated in-process and written to
    `<name>-key.pem`; nothing is written to any certificate store.
- **Merge / split**
  - certificate + local private key → PFX
  - certificate + key file → PFX
  - certificate + key file → combined PEM (for nginx/apache)
  - PFX → certificate PEM + key PEM (+ optional DER)
- **Orphan key recovery** — scans CSP key containers and matches by public key,
  so a CSR generated weeks ago can still be merged.
- **PFX private keys stay re-exportable** — the Windows build uses a named
  `PROV_RSA_AES` CSP container, which is the only reliable way to keep the
  private key exportable after a PFX round-trip on .NET Framework.
- **Bilingual UI** — 中文 / English, switched live from the menu.
- **Real validation** — X.500 length limits, forbidden DN characters, country and
  email sanity checks, SAN/IP parsing.

## Compatibility

| Component | Windows | Linux | macOS |
|---|---|---|---|
| `CertToolkit.ps1` (GUI) | ✅ PS 5.1, PS 7+ | — (no WinForms) | — |
| `csrtool.ps1` (CLI) | ✅ PS 5.1, PS 7+ | ✅ PS 7+ | ✅ PS 7+ |
| certreq backend | ✅ Windows only | — | — |
| Portable (`.NET`) backend | ✅ | ✅ | ✅ |
| Certificate store / key containers | ✅ Windows only | — | — |

Minimum versions: **Windows PowerShell 5.1** (.NET Framework 4.7.2+ for
`CertificateRequest`) or **PowerShell 7.0+**. Python, OpenSSL and `certreq`
are *not* required — the CLI does all crypto with .NET.

## Quick start

### GUI (Windows)

```bat
启动证书工具箱.bat
```

or:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\CertToolkit.ps1
```

There are two tabs: **Generate CSR** and **Merge / Split**. Use the
**Language** menu to switch between 中文 and English — the window
rebuilds immediately.

### CLI (any platform)

```bash
chmod +x ./start-cert-toolkit.sh   # once
./start-cert-toolkit.sh
```

or call the script directly:

```powershell
pwsh ./csrtool.ps1                      # interactive menu
pwsh ./csrtool.ps1 --help
```

## CLI reference

| Command | Purpose |
|---|---|
| `new-csr` | generate a CSR and (optionally) a private key |
| `merge-pfx` | certificate + key → PFX |
| `merge-pem` | certificate + key → combined PEM |
| `split-pfx` | PFX → certificate PEM + key PEM |
| `info` | print certificate details |
| `verify` | check that a key matches a certificate |
| `export-key` | export the private key for a certificate |
| `scan-keys` | list local key containers (Windows only) |
| `serve` | interactive menu (default with no arguments) |

Global options: `-Language zh|en`, `-Help`, `-Version`, `-Force`.

### Examples

```powershell
# CSR for an mTLS client, key written to a file (portable, works everywhere)
pwsh ./csrtool.ps1 new-csr -CN NAS-Monitor-I -KeyOut ./nas-monitor.key -Out ./nas-monitor.req

# Server certificate with SAN, key kept in the Windows key container
pwsh ./csrtool.ps1 new-csr -CN nas.example.com `
     -San dns=nas.example.com,ipaddress=10.0.0.5 `
     -Eku 1.3.6.1.5.5.7.3.1 -Out ./nas.req -Backend certreq

# Merge the issued certificate with the key file
pwsh ./csrtool.ps1 merge-pfx -Cert issued.cer -Key ./nas-monitor.key `
     -Out ./nas-monitor.pfx -Password 'change-me'

# No key file? Let it scan the local store and key containers
pwsh ./csrtool.ps1 merge-pfx -Cert issued.cer -Out ./nas.pfx -Password 'change-me'

# Split a PFX back into PEM files
pwsh ./csrtool.ps1 split-pfx ./nas.pfx -Password 'change-me' -Out ./nas -Der

# Inspect / verify
pwsh ./csrtool.ps1 info -Cert ./issued.cer
pwsh ./csrtool.ps1 verify -Cert ./issued.cer -Key ./nas-monitor.key
```

## How the tricky parts work

**Multi-EKU INF.** Only this form is accepted by `certreq`:

```ini
[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.2
OID=1.3.6.1.5.5.7.3.1
```

`2.5.29.37 = "{text}A&{text}B"`, repeated `[Extensions]` lines, and
`OID=A,B` all fail with different errors. SAN is the opposite: it *does* accept
`&` joining. The two extensions are asymmetric — that asymmetry is a common trap.

**Re-exportable PFX.** `RSACryptoServiceProvider` created without a named
container produces a PFX whose private key cannot be exported again
(`ExportParameters(true)` → "The requested operation is not supported"). The fix
is a named container with `ProviderType = 24` (`PROV_RSA_AES`). On .NET Core
this is not needed, and on Linux/macOS there is no CSP at all — the code picks
the right strategy per platform.

**.NET Framework vs .NET Core.** `X509SubjectAlternativeNameExtension` and
`RSA.ExportPkcs8PrivateKey` do **not** exist in .NET Framework 4.8, and
`EphemeralKeySet` imports keys that cannot be exported again. The toolkit checks
the runtime instead of assuming, and builds PKCS#8 wrapping by hand from ASN.1
primitives when the API is missing.

**Encoding rules** (this project depends on them):

| File type | Encoding | Why |
|---|---|---|
| `*.ps1` | UTF-8 **with BOM** | without BOM, Windows PowerShell 5.1 reads it as ANSI and every Chinese string breaks |
| `*.bat` | ASCII, **no BOM** | `cmd.exe` treats a BOM as part of the first command |
| `*.txt` / `*.md` | UTF-8 (BOM for `.txt`) | Notepad compatibility |

## Project layout

```
CertToolkit.ps1          GUI (Windows, PS 5.1 + PS 7)
csrtool.ps1              CLI (all platforms)
CertHelper.ps1           loader — keeps the old function names working
lib/
  CertI18n.ps1           zh/en strings, language detection
  CertCore.ps1           ASN.1/DER, PEM, RSA, CSR, PFX, certificate I/O
  CertWindows.ps1        certreq, certificate store, key containers
tests/
  selftest.ps1           library self-test (both PS versions)
  clitest.ps1            CLI end-to-end test (both PS versions)
启动证书工具箱.bat        Windows GUI launcher
Start-CertToolkit.bat    same, ASCII file name
start-cert-toolkit.sh    Linux/macOS launcher (CLI)
CSR-Generator.ps1        legacy single-page tool, kept for reference
```

## Tests

```powershell
# library: CSR, PFX round-trip, PEM, DN/SAN encoding, i18n coverage
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tests\selftest.ps1

# CLI end-to-end (runs under both runtimes automatically)
pwsh -NoProfile -File .\tests\clitest.ps1

# GUI functional smoke test (drives the real UI code paths)
pwsh -NoProfile -STA -File .\CertToolkit.ps1 -SelfTest
```

All three suites are expected to report `0 failed`.

## Contributing

Contributions are welcome. This codebase has a few **non-obvious hard rules** —
file encodings are functional, both PowerShell runtimes must work, and every UI
string has to exist in both languages. They are all documented in
[CONTRIBUTING.md](CONTRIBUTING.md), together with the traps we already hit
(`$IsWindows` in 5.1, `EphemeralKeySet` on .NET Framework, PowerShell flattening
nested `byte[]`, and so on).

- [Code of Conduct](CODE_OF_CONDUCT.md) — Contributor Covenant 2.1
- [Security Policy](SECURITY.md) — report vulnerabilities **privately**, never in a public issue
- [Issue templates](.github/ISSUE_TEMPLATE) and a [PR checklist](.github/PULL_REQUEST_TEMPLATE.md)
- CI must be green; `settings → Secrets` are not needed to run the suites

## Security notes

- The private key never goes into the CSR file — a `.req`/`.csr` is safe to send.
- Exported `-key.pem` files are **unencrypted**. They are your identity: do not
  email them, do not commit them (see `.gitignore`), store them accordingly.
- The GUI does not install certificates unless you explicitly tick
  *"Allow certreq -accept auto-pairing"*.
- Portable mode touches no certificate store at all.

## License

MIT — see [LICENSE](LICENSE).

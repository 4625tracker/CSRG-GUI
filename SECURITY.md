# 安全策略 · Security Policy

这个工具会生成、读取并写出**私钥**。安全问题在这里的后果比一般项目更直接，
所以请按下面的方式私下报告。

> 中文在前，英文在后。 / Chinese first, English below.

---

## 支持范围 · Supported versions

| 版本 | 状态 |
|---|---|
| `2.x`（当前 `main`） | ✅ 接受安全报告并修复 |
| `1.x`（旧版单页工具 `CSR-Generator.ps1`） | ❌ 仅作参考保留，不再修复 |

## 如何私下报告 · How to report

**请不要开公开 issue。**

1. 首选：GitHub 的私下报告入口
   → <https://github.com/4625tracker/CSRG-GUI/security/advisories/new>
   （仓库 Security 标签页里的 *Report a vulnerability*）
2. 如果该入口不可用，请通过 GitHub 私信维护者
   [@4625tracker](https://github.com/4625tracker)。

### 报告里请包含

- 受影响版本（GUI 启动日志里会显示，或 `csrtool.ps1 -Version`）
- 操作系统与 `$PSVersionTable` 的 `PSEdition` / `PSVersion`
- 用的是哪个组件：GUI / CLI / `lib/` 函数
- 用的是哪个 CSR 后端：`certreq` 还是 `.NET 可移植模式`
- 复现步骤、期望结果、实际结果
- 如果涉及文件写出：文件被写到了哪里、权限如何

### 请**不要**包含

- 真实私钥、PFX、口令、生产证书
- 主机名、内网 IP、证书序列号等可识别信息

需要复现材料时，请用**自签证书**和临时生成的密钥。如果漏洞必须依赖真实材料才能说明，
请先只描述机制，我们会在需要时给出安全的交换方式。

## 响应预期 · What to expect

这是一个**业余时间维护**的项目，没有 7×24 的值守，但会认真对待每一份报告：

- 尽力在 **7 天内**给出初次回应
- 确认后会在修复可用时协调披露；默认倾向 **90 天内**公开，若修复先就绪可提前
- 修复会出现在 `main` 与 Release notes 里，并在公告中致谢（除非你要求匿名）

## 哪些算安全问题 · In scope

- **私钥泄露到非预期位置**：私钥被写进日志、控制台、临时文件，且未清理或权限过宽
- **私钥被写到用户没有指定的路径**
- **密钥匹配判断错误**：`verify` / `Test-KeyMatchesCert` 把不匹配的私钥报告为"匹配"
  （这会直接导致用错密钥部署，属于严重问题）
- **PFX 口令处理不当**：例如声称已加密实则空口令；或口令被拼进命令行参数、
  出现在进程列表里
- **命令注入**：`CN`、文件名、SAN 值等用户输入进入 `certreq.exe` 调用后
  能影响命令构造
- **文案/格式化注入**：多语言文案的格式化路径能被用户输入利用，导致异常或信息泄露
- **证书链/扩展解析**：恶意构造的 DER 能让工具崩溃或误判（例如把非证书内容当成证书）

## 哪些**不**算安全问题 · Out of scope

以下行为是**设计如此**，不是漏洞：

- **私钥可以被导出**。工具的目的就是让你把私钥备份成 `-key.pem`；
  `导出私钥` 是明确功能。
- **扫描本机所有密钥容器**。孤立私钥找回会遍历容器并按公钥比对，这一过程**只读**、
  不修改任何容器；它需要能读到对应容器（机器容器需要管理员），行为是预期的。
- **生成 CSR 时私钥留在本机密钥容器**（`certreq` 后端的既有行为）。
- 用户自己把 `-key.pem`、PFX 或口令发给第三方。
- `certreq.exe`、`certutil.exe`、Windows 证书存储本身的行为或缺陷。
- CA 端的签发策略、AIA/OCSP/CRL 配置问题。
- 已经停止维护的 `1.x` / `CSR-Generator.ps1`。

## 安全使用建议 · Safe usage

- 导出的 `-key.pem` 是**明文私钥**，等同身份凭证：不要外发、不要提交进仓库、
  存放在访问受限的位置。
- 提交前看一眼 `git status`；`.gitignore` 会挡住常见扩展名，但不是保险箱。
- 除非你明确勾选「允许 certreq -accept 自动配对」，GUI **不会**往证书存储里装东西；
  可移植模式完全不写证书存储。
- 在共享机器上运行时注意：用户密钥容器里的私钥，同账号下的其它程序也读得到。

---

## English

### Supported versions

`2.x` (current `main`) receives security fixes. `1.x`, including the legacy
`CSR-Generator.ps1`, is kept for reference only and is **not** fixed.

### Reporting

**Do not open a public issue.** Use GitHub's private reporting:
<https://github.com/4625tracker/CSRG-GUI/security/advisories/new>.
If that is unavailable, send a GitHub direct message to
[@4625tracker](https://github.com/4625tracker).

Please include: affected version, OS and `$PSVersionTable` (`PSEdition`/`PSVersion`),
which component (GUI / CLI / `lib/`), which CSR backend (`certreq` or the portable
`.NET` one), reproduction steps, expected vs actual behaviour, and — for anything
that writes files — where files were written and with what permissions.

Please **do not** include real private keys, PFX files, passwords or production
certificates, nor hostnames, internal IPs or certificate serial numbers. Use
self-signed material to reproduce.

### Expectations

This is a best-effort, spare-time project. We aim to acknowledge a report within
**7 days**, coordinate a fix, and prefer disclosure within **90 days** (sooner if a
fix ships). Fixes land on `main` and in release notes, with credit unless you ask
to stay anonymous.

### In scope

- Private keys leaking to logs, console, temp files, or unexpected paths
- Keys being written somewhere the user did not ask for
- `verify` / `Test-KeyMatchesCert` reporting a match for a non-matching key
  (this leads directly to deploying the wrong key)
- PFX password mishandling: claiming encryption while writing an empty password, or
  putting the password into a command line where it is visible in the process list
- Command injection through `CN`, file names or SAN values passed to `certreq.exe`
- Format-string / i18n injection reachable from user input
- Malicious DER that crashes the tool or makes it misidentify content as a certificate

### Out of scope (by design)

- **Private keys are exportable.** Exporting `-key.pem` is a deliberate feature —
  it is the backup mechanism.
- **Scanning every key container** to recover an orphaned key. The scan is
  read-only, matches by public key, and modifies nothing; machine containers
  require administrator rights. This is expected behaviour.
- Keys staying in the local key container when the `certreq` backend is used.
- Users sharing their own `-key.pem`, PFX or password.
- Bugs in `certreq.exe`, `certutil.exe`, or the Windows certificate store.
- CA-side issuance policy, AIA/OCSP/CRL configuration.
- Unmaintained `1.x` / `CSR-Generator.ps1`.

### Safe usage

Exported `-key.pem` files are **unencrypted** and are your identity: never share
them, never commit them, keep them on restricted storage. Portable mode writes to
no certificate store; the GUI installs nothing unless you explicitly enable
`certreq -accept` auto-pairing. On a shared machine, remember that other programs
running as you can read keys in your user key containers.

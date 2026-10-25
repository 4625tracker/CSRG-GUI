# 贡献指南 · Contributing

感谢你愿意改进这个工具。它是**一个处理私钥的程序**，所以下面这些规则不是形式主义 ——
每一条都对应一个真实踩过的坑。

> Issues 和 Pull Request 用中文或英文都可以。文档和界面文案保持**中英双语**。

- [开始之前](#开始之前)
- [项目结构](#项目结构)
- [运行测试](#运行测试)
- [硬性规则一：文件编码](#硬性规则一文件编码)
- [硬性规则二：跨 PowerShell 版本](#硬性规则二跨-powershell-版本)
- [硬性规则三：文案与 i18n](#硬性规则三文案与-i18n)
- [常见改动怎么做](#常见改动怎么做)
- [兼容性承诺](#兼容性承诺)
- [安全与隐私](#安全与隐私)
- [提交与 PR](#提交与-pr)
- [English summary](#english-summary)

---

## 开始之前

- **不需要** Python、OpenSSL、Node.js。这个项目只依赖 PowerShell 本身。
- 需要能跑 **Windows PowerShell 5.1** 和 **PowerShell 7+** 两个运行时。
  Windows 上两者都有；Linux/macOS 只有 `pwsh`（命令行版本可用，图形界面不可用）。
- 建议开一个分支再动手：`git switch -c fix/pfx-password`。

## 项目结构

```
CertToolkit.ps1       图形界面 (Windows, WinForms)
csrtool.ps1           命令行入口 (所有平台)
CertHelper.ps1        加载器 —— 必须有它才能用 lib/ 里的函数
lib/CertCore.ps1      跨平台核心: ASN.1/DER、PEM、RSA、CSR、PFX、证书读写
lib/CertWindows.ps1   Windows 专属: certreq、证书存储、密钥容器
lib/CertI18n.ps1      中英文文案与语言探测
tests/selftest.ps1    库自检
tests/clitest.ps1     命令行端到端
.github/workflows/    CI (Windows + Linux)
使用说明.txt           中文手册 (面向用户)
README.md / README.zh-CN.md
```

`CertToolkit.ps1` 与 `csrtool.ps1` 都通过 `. CertHelper.ps1` 取得全部函数。

## 运行测试

三个套件，缺一不可：

```powershell
# 1) 库自检 —— 在两个运行时上都要跑
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tests\selftest.ps1

# 2) 命令行端到端 (会自动在两个运行时各跑一遍)
pwsh -NoProfile -File .\tests\clitest.ps1

# 3) 图形界面功能自测 (改动 UI 或生成/合并流程时必须跑)
pwsh -NoProfile -STA -File .\CertToolkit.ps1 -SelfTest
powershell -NoProfile -ExecutionPolicy Bypass -STA -File .\CertToolkit.ps1 -SelfTest
```

全部应为 `0 failed`。CI 还会在 `ubuntu-latest` 上跑前两个套件（命令行版）。

测试用**自签证书**在本机临时目录里生成，不会写进证书存储，也不会碰你的真实密钥。
`-SelfTest` 不会弹任何对话框。

## 硬性规则一：文件编码

这个项目的文件编码是**功能的一部分**。测试会检查，PR 违反就会被 CI 拦下。

| 文件 | 编码 | 为什么 |
|---|---|---|
| `*.ps1` | **UTF-8 带 BOM** | 没有 BOM 时，Windows PowerShell 5.1 按 ANSI 读文件，所有中文变乱码 → 语法错误 |
| `*.bat` | **纯 ASCII，无 BOM** | `cmd.exe` 会把 BOM 当成第一条命令的一部分，报 `'锘緻echo' 不是内部或外部命令` |
| `*.sh` | **LF 换行** | CRLF 会让 `#!/usr/bin/env bash` 失效，Linux/macOS 上直接执行失败 |
| `*.txt` | UTF-8 带 BOM + CRLF | 记事本 |
| `*.md` / `*.yml` | UTF-8 无 BOM，LF | GitHub |

⚠️ **很多编辑器/工具会把 BOM 去掉**（包括某些自动改写脚本的流程）。
改完 `.ps1` 后请确认 BOM 还在：

```powershell
$b = [System.IO.File]::ReadAllBytes('.\CertToolkit.ps1')
"{0:X2} {1:X2} {2:X2}" -f $b[0], $b[1], $b[2]   # 应该是 EF BB BF
```

## 硬性规则二：跨 PowerShell 版本

代码要在 **.NET Framework 4.8（PS 5.1）** 和 **.NET 8/10（PS 7）** 上都能跑。
下面这些坑都真实踩过：

| 现象 | 原因 | 正确写法 |
|---|---|---|
| 5.1 里 `$IsWindows` 报变量不存在 | 5.1 没有这组自动变量 | 用 `Test-IsWindowsHost` / `Test-IsCoreEdition` |
| `if (...)` 一行写法报语法错误 | 5.1 不支持三元 `? :` 和 `??` | 老老实实写 `if/else` |
| 数组长度的判断永远为假 | 5.1 里单个 `PSCustomObject` 的 `.Count` 是 `$null` | 用 `@($x).Count` |
| DER 结构错位、莫名丢字节 | `@(...)` 会把嵌套 `byte[]` 拍平成字节序列 | 用 `Join-Bytes` 拼字节，参数刻意是 `[object[]]` |
| `New-Object X509Certificate2($bytes)` 失败 | PowerShell 把数组展开了 | 用 `[X509Certificate2]::new([byte[]]$bytes)` |
| 找不到 SAN 扩展类型 | 4.8 没有 `X509SubjectAlternativeNameExtension` | 手写 DER（见 `New-SanExtensionDer`） |
| 没有 `ExportPkcs8PrivateKey` | 4.8 该 API 不存在 | 用 `ConvertTo-Pkcs8Rsa` 手工拼 PrivateKeyInfo |
| 回读 PFX 后私钥导不出来 | 4.8 上 `EphemeralKeySet` 导入的密钥不可再导出 | 用 `Get-PfxLoadFlags`，它按运行时分支 |
| 生成的 PFX 私钥以后导不出来 | 用了临时 CSP 容器 | 用 `New-RsaWithCspContainer`（`PROV_RSA_AES` 命名容器） |
| `ChangeExtension($p, $null)` 留下尾点 | .NET 行为（`issued.cer` → `issued.`） | 手动拼 `-key.pem` 文件名 |
| `$Cert.PrivateKey` 取不到 | .NET Core 上该属性会抛 `PlatformNotSupportedException` | 用 `Get-RsaFromCert`（已含 try/catch 回退） |

原则：**先探测能力，再决定实现**（`Test-IsCoreEdition`、`Get-Command`、`-as [type]`），
不要假设某个 API 一定存在。

## 硬性规则三：文案与 i18n

- 所有面向用户的字符串都走 `Get-CertText 'key'`（GUI 里可简写 `T 'key'`），
  **不要**把中英文直接写在界面代码里。
- 每个 key 必须在 [lib/CertI18n.ps1](lib/CertI18n.ps1) 里**同时**给出中文和英文。
- `{0}` / `{1}` 占位符在两种语言里**数量必须一致**，否则格式化会失败。
- 需要换行时在文案里写 `` `n ``（反引号 + n），`Get-CertText` 会还原成真正的换行。
- 自检会扫描代码里出现的所有字面 key，**缺 key 或漏一个语言都会让测试失败**。

新增文案的最小步骤：

```powershell
# lib/CertI18n.ps1
'csr.chk.myoption' = @('我的选项', 'My option')
```

```powershell
# 使用处
$cb.Text = Get-CertText 'csr.chk.myoption'
```

## 常见改动怎么做

**加一个 EKU**
1. `CertToolkit.ps1` 的 `$script:EkuDefs` 加一行（含 OID 与是否默认勾选）
2. `lib/CertI18n.ps1` 加 `eku.xxx`
3. 如该用途常用，顺手更新 `使用说明.txt` 的常用组合说明

**加一种 SAN 类型**
1. `CertToolkit.ps1` 的 `$script:SanTypes` 加显示名与前缀
2. `lib/CertCore.ps1` 的 `New-SanExtensionDer` 里处理该前缀（注意 `GeneralName` 的隐式标签）
3. `lib/CertI18n.ps1` 加 `csr.san.xxx`
4. 在 `tests/selftest.ps1` 的 SAN 用例里加一条

**加一个命令行命令**
1. `csrtool.ps1` 里写 `Invoke-Xxx` 函数，并在末尾的 dispatch 里登记
2. `lib/CertI18n.ps1` 补 `cli.usage`、`cli.help.xxx`
3. 在 `tests/clitest.ps1` 加端到端用例（含退出码断言）

**加一个公共函数**
- 跨平台的放 `lib/CertCore.ps1`；碰 certreq / 证书存储 / 密钥容器的放 `lib/CertWindows.ps1`
  （后者只在 Windows 上加载，**函数里不要假设它一定存在**）
- 参数尽量显式类型；错误用 `throw (Get-CertText 'err.xxx' ...)` 而不是英文硬编码

## 兼容性承诺

- **不要删除或改写 `CertHelper.ps1` 里已有的公共函数名**。它们是给旧脚本用的，
  语义可以扩展，但名字和主要行为要保住。要改就新增函数。
- 旧的启动入口（两个 `.bat`）要保持可用。
- **不要静默改变默认行为**。例如 Windows 上默认仍走 certreq 后端；
  想换默认值，请在 README、使用说明和 PR 里明确说明理由。
- 新增能力优先做成**可选开关**，而不是替换老路径。

## 安全与隐私

- **绝不要**把私钥、PFX、真实证书、口令提交进仓库。`.gitignore` 已经挡住常见扩展名，
  但它不是保险箱 —— 提交前请自己看一眼 `git status`。
- 测试请用**自签证书**或临时生成的密钥；仓库里不应出现任何真实环境材料。
- Issue / 日志里贴输出时，去掉路径、主机名、指纹、序列号等可识别信息。
- 发现安全问题时**不要开公开 issue**，请按 [SECURITY.md](SECURITY.md) 私下报告。

## 提交与 PR

提交信息用前缀开头，说明"为什么"而不只是"改了什么"：

```
feat: 支持 ECDSA 私钥导入
fix:  PS 5.1 上 PFX 口令为空时读取失败
docs: 补充孤立私钥的排查步骤
test: 增加 SAN 里 IPv6 的用例
```

PR 请填写 [PR 模板](.github/PULL_REQUEST_TEMPLATE.md)，并在描述里贴上测试输出摘要。
涉及行为变化的，请说明是否影响向后兼容、是否需要更新文档。

CI 必须绿。如果只是文档改动，注明一下即可，不必强求本地跑全套。

## English summary

This is a certificate/private-key tool, so the rules below are load-bearing:

1. **File encodings are functional requirements.** `*.ps1` must be UTF-8 **with BOM**
   (Windows PowerShell 5.1 reads BOM-less files as ANSI and every Chinese string breaks);
   `*.bat` must be ASCII **without BOM**; `*.sh` must use **LF**.
   The self-test enforces all three.
2. **Both PowerShell runtimes must work**: 5.1 (.NET Framework 4.8) and 7+ (.NET 8/10).
   No ternaries, no `??`, no `$IsWindows` (use `Test-IsWindowsHost`), and remember that
   `X509SubjectAlternativeNameExtension`, `ExportPkcs8PrivateKey` and reliable
   `EphemeralKeySet` behaviour are **not** available on 4.8.
3. **All user-facing strings go through `Get-CertText`**, with both `zh` and `en` filled in
   and identical `{n}` placeholders.
4. **Never commit key material.** Test with self-signed certificates.
5. **Keep `CertHelper.ps1`'s public function names working** — old scripts depend on them.
6. Run the three suites (`tests/selftest.ps1`, `tests/clitest.ps1`, `CertToolkit.ps1 -SelfTest`)
   and keep CI green.

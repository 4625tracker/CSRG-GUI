# 证书工具箱 Certificate Toolkit

一个专注做两件事的小工具：**带正确 EKU / SAN 地生成 CSR**，以及
**把 CA 签发的证书和你的私钥重新合并**成 PFX 或合并 PEM。

单个文件夹即用，不需要安装、不需要编译，除了 PowerShell 本身没有其它依赖。

[English](README.md) · [使用说明 (详细中文手册)](使用说明.txt)

---

## 为什么需要它

在 Windows 上签发一张证书，要跨过两个很容易踩坑的步骤：

1. `certreq -new` 会把私钥写进 **密钥容器 (key container)** —— 但那一刻还没有
   证书，所以私钥是"孤立"的。容器名是自动生成的 `tq-<GUID>`，没有任何地方
   记录它属于哪一次 CSR。
2. CA 返回的 `.cer` 里**只有公钥**。必须把它和那把藏起来的私钥合并，
   IIS / nginx / mTLS 客户端才能用。

本工具把两步都做了，并且能通过**比较公钥**的方式，在本机所有容器里把那把
孤立私钥重新认回来 —— 哪怕 CSR 是几周前生成的。

## 功能

- **多 EKU 的 CSR** —— 使用真正能被 `certreq` 接受的写法
  （`[EnhancedKeyUsageExtension]` + 每行一个 `OID=`）。逗号拼接、重复行都会被拒。
- **SAN** —— 支持 `dns` / `ipaddress` / `email` / `upn` / `URL`，
  其中 UPN 用 `otherName` 写法；全部手写 DER 编码，各平台行为一致。
- **两种 CSR 后端**
  - `certreq`（Windows 默认）—— 私钥留在本机密钥容器。
  - `.NET`（**可移植模式**）—— 进程内生成密钥并写成 `<名字>-key.pem`，
    完全不碰任何证书存储。
- **合并 / 拆解**
  - 证书 + 本机私钥 → PFX
  - 证书 + 私钥文件 → PFX
  - 证书 + 私钥文件 → 合并 PEM（给 nginx / apache）
  - PFX → 证书 PEM + 私钥 PEM（+ 可选 DER）
- **孤立私钥找回** —— 扫描 CSP 密钥容器并按公钥匹配。
- **PFX 的私钥仍然可再导出** —— Windows 下使用命名的 `PROV_RSA_AES` CSP 容器；
  这是在 .NET Framework 上让 PFX 往返之后私钥还能导出的唯一可靠做法。
- **中英双语界面** —— 菜单里直接切换，窗口立即重建。
- **真正做校验** —— X.500 长度上限、DN 禁用字符、国家代码与邮箱格式、
  SAN 与 IP 解析。

## 兼容性

| 组件 | Windows | Linux | macOS |
|---|---|---|---|
| `CertToolkit.ps1`（图形界面） | ✅ PS 5.1、PS 7+ | —（无 WinForms） | — |
| `csrtool.ps1`（命令行） | ✅ PS 5.1、PS 7+ | ✅ PS 7+ | ✅ PS 7+ |
| certreq 后端 | ✅ 仅 Windows | — | — |
| 可移植（`.NET`）后端 | ✅ | ✅ | ✅ |
| 证书存储 / 密钥容器 | ✅ 仅 Windows | — | — |

最低版本：**Windows PowerShell 5.1**（需要 .NET Framework 4.7.2+ 以提供
`CertificateRequest`）或 **PowerShell 7.0+**。
**不需要** Python、不需要 OpenSSL、命令行版本也不依赖 `certreq`。

## 快速开始

### 图形界面（Windows）

```bat
启动证书工具箱.bat
```

或者：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File .\CertToolkit.ps1
```

两个标签页：**生成 CSR** 与 **合并 / 拆解**。
顶部菜单可以切换 中文 / English，窗口会立即重建。

### 命令行（任意平台）

```bash
chmod +x ./start-cert-toolkit.sh   # 只需一次
./start-cert-toolkit.sh
```

或者直接调用：

```powershell
pwsh ./csrtool.ps1                      # 交互菜单
pwsh ./csrtool.ps1 --help
```

## 命令行参考

| 命令 | 作用 |
|---|---|
| `new-csr` | 生成 CSR，并（可选）导出私钥 |
| `merge-pfx` | 证书 + 私钥 → PFX |
| `merge-pem` | 证书 + 私钥 → 合并 PEM |
| `split-pfx` | PFX → 证书 PEM + 私钥 PEM |
| `info` | 显示证书详情 |
| `verify` | 验证私钥与证书是否匹配 |
| `export-key` | 导出证书对应的私钥 |
| `scan-keys` | 列出本机密钥容器（仅 Windows） |
| `serve` | 交互菜单（无参数时的默认行为） |

通用选项：`-Language zh|en`、`-Help`、`-Version`、`-Force`。

### 示例

```powershell
# mTLS 客户端证书, 私钥写成文件 (可移植, 任何系统都行)
pwsh ./csrtool.ps1 new-csr -CN NAS-Monitor-I -KeyOut ./nas-monitor.key -Out ./nas-monitor.req

# 服务器证书带 SAN, 私钥留在 Windows 密钥容器
pwsh ./csrtool.ps1 new-csr -CN nas.example.com `
     -San dns=nas.example.com,ipaddress=10.0.0.5 `
     -Eku 1.3.6.1.5.5.7.3.1 -Out ./nas.req -Backend certreq

# 用私钥文件合并 CA 签发的证书
pwsh ./csrtool.ps1 merge-pfx -Cert issued.cer -Key ./nas-monitor.key `
     -Out ./nas-monitor.pfx -Password 'change-me'

# 没有私钥文件? 让它去本机证书存储和密钥容器里找
pwsh ./csrtool.ps1 merge-pfx -Cert issued.cer -Out ./nas.pfx -Password 'change-me'

# 把 PFX 拆回 PEM
pwsh ./csrtool.ps1 split-pfx ./nas.pfx -Password 'change-me' -Out ./nas -Der

# 查看 / 校验
pwsh ./csrtool.ps1 info -Cert ./issued.cer
pwsh ./csrtool.ps1 verify -Cert ./issued.cer -Key ./nas-monitor.key
```

## 几个关键实现细节

**多 EKU 的 INF 写法。** `certreq` 只接受这一种：

```ini
[EnhancedKeyUsageExtension]
OID=1.3.6.1.5.5.7.3.2
OID=1.3.6.1.5.5.7.3.1
```

`2.5.29.37 = "{text}A&{text}B"`、重复的 `[Extensions]` 行、`OID=A,B`
都会以不同的错误失败。而 SAN 恰恰相反，它**可以**用 `&` 连接 ——
这两个扩展不对称，是很常见的坑。

**可再导出的 PFX。** 用无参 `RSACryptoServiceProvider` 创建密钥，
打包出的 PFX 私钥以后**导不出来**（`ExportParameters(true)` 报
"The requested operation is not supported"）。正确做法是指定
`ProviderType = 24`（`PROV_RSA_AES`）的命名容器。.NET Core 上不需要这么绕，
Linux/macOS 上根本没有 CSP —— 代码按平台自动选择。

**.NET Framework 与 .NET Core 的差异。** `X509SubjectAlternativeNameExtension`
和 `RSA.ExportPkcs8PrivateKey` 在 .NET Framework 4.8 里**不存在**；
`EphemeralKeySet` 导入的私钥也**不可再导出**。工具会先探测运行时能力，
缺 API 时用自己拼的 ASN.1 补上（例如 PKCS#8 包装）。

**编码规则**（这个项目依赖它们）：

| 文件类型 | 编码 | 原因 |
|---|---|---|
| `*.ps1` | UTF-8 **带 BOM** | 无 BOM 时 Windows PowerShell 5.1 按 ANSI 读，中文全乱码并导致语法错误 |
| `*.bat` | ASCII，**无 BOM** | `cmd.exe` 会把 BOM 当成第一条命令的一部分 |
| `*.txt` / `*.md` | UTF-8（`.txt` 带 BOM） | 记事本才认得出中文 |

## 项目结构

```
CertToolkit.ps1          图形界面 (Windows, PS 5.1 + PS 7)
csrtool.ps1              命令行 (所有平台)
CertHelper.ps1           加载器 —— 保留旧函数名, 老调用方式仍可用
lib/
  CertI18n.ps1           中英文文案与语言探测
  CertCore.ps1           ASN.1/DER、PEM、RSA、CSR、PFX、证书读写
  CertWindows.ps1        certreq、证书存储、密钥容器
tests/
  selftest.ps1           库自检 (两个 PS 版本)
  clitest.ps1            CLI 端到端测试 (两个 PS 版本)
启动证书工具箱.bat        Windows 图形界面启动器
Start-CertToolkit.bat     同上 (英文文件名)
start-cert-toolkit.sh     Linux/macOS 启动器 (命令行)
CSR-Generator.ps1         旧版单页工具, 仅作参考保留
```

## 测试

```powershell
# 库: CSR、PFX 往返、PEM、DN/SAN 编码、多语言覆盖
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tests\selftest.ps1

# CLI 端到端 (会自动在两个运行时各跑一遍)
pwsh -NoProfile -File .\tests\clitest.ps1

# 图形界面功能冒烟测试 (真实驱动界面代码路径)
pwsh -NoProfile -STA -File .\CertToolkit.ps1 -SelfTest
```

三个套件都应报告 `0 failed`。

## 安全提示

- 私钥**不会**写进 CSR 文件 —— `.req` / `.csr` 随便传都没事。
- 导出的 `-key.pem` 是**明文私钥**，等于你的身份：不要外发、不要提交
  （见 `.gitignore`），存放要当心。
- 除非你主动勾选「允许 certreq -accept 自动配对」，图形界面**不会**往证书存储里装东西。
- 可移植模式完全不碰任何证书存储。

## 许可证

MIT —— 见 [LICENSE](LICENSE)。

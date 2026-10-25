# ============================================================
#  CertHelper.ps1  —  加载器 (向后兼容入口)
#  ------------------------------------------------------------
#  早期版本里本文件是"底层库"本身; 2.0 起拆成 lib/ 下的模块,
#  这里只负责按顺序加载, 并保留所有旧函数名:
#
#      .\CertHelper.ps1        <- 老调用方式仍然有效
#      Get-CertificateFromFile / New-PfxFromCertAndKey / ...
#
#  模块划分:
#      lib/CertI18n.ps1      中英文文案
#      lib/CertCore.ps1      跨平台 ASN.1 / PEM / RSA / CSR / PFX
#      lib/CertWindows.ps1   Windows 专属 (密钥容器 / certreq / 证书存储)
# ============================================================

$script:CertLibDir = $PSScriptRoot

# ★ 用 Join-Path 逐级拼接, 而不是写 'lib\X.ps1':
#   在 Linux / macOS 上反斜杠是普通文件名字符, 不是目录分隔符。
$libDir   = Join-Path $script:CertLibDir 'lib'
$i18nPath = Join-Path $libDir 'CertI18n.ps1'
$corePath = Join-Path $libDir 'CertCore.ps1'
$winPath  = Join-Path $libDir 'CertWindows.ps1'

if (-not (Test-Path -LiteralPath $i18nPath)) {
    throw "Missing module: $i18nPath (keep the lib/ folder next to CertHelper.ps1)"
}
if (-not (Test-Path -LiteralPath $corePath)) {
    throw "Missing module: $corePath (keep the lib/ folder next to CertHelper.ps1)"
}

. $i18nPath
. $corePath

if (Test-IsWindowsHost) {
    if (Test-Path -LiteralPath $winPath) { . $winPath }
}

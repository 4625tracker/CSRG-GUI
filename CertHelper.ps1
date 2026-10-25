# ============================================================
#  CertHelper.ps1  —  加载器 (向后兼容入口)
#  ------------------------------------------------------------
#  早期版本里本文件是"底层库"本身; 2.0 起拆成 lib\ 下的模块,
#  这里只负责按顺序加载, 并保留所有旧函数名:
#
#      .\CertHelper.ps1        <- 老调用方式仍然有效
#      Get-CertificateFromFile / New-PfxFromCertAndKey / ...
#
#  模块划分:
#      lib\CertI18n.ps1      中英文文案
#      lib\CertCore.ps1      跨平台 ASN.1 / PEM / RSA / CSR / PFX
#      lib\CertWindows.ps1   Windows 专属 (密钥容器 / certreq / 证书存储)
# ============================================================

$script:CertLibDir = $PSScriptRoot

$i18nPath = Join-Path $script:CertLibDir 'lib\CertI18n.ps1'
$corePath = Join-Path $script:CertLibDir 'lib\CertCore.ps1'
$winPath  = Join-Path $script:CertLibDir 'lib\CertWindows.ps1'

if (-not (Test-Path -LiteralPath $i18nPath)) { throw "Missing module: $i18nPath" }
if (-not (Test-Path -LiteralPath $corePath)) { throw "Missing module: $corePath" }

. $i18nPath
. $corePath

if (Test-IsWindowsHost) {
    if (Test-Path -LiteralPath $winPath) { . $winPath }
}

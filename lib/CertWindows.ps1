# ============================================================
#  CertWindows.ps1  —  Windows 专属能力
#  ------------------------------------------------------------
#  · certreq 后端 (生成 CSR / 接受证书)
#  · 本机证书存储 (Cert:\CurrentUser\My / LocalMachine\My)
#  · 密钥容器扫描 —— 找回 certreq 生成的"孤立私钥"
#  · PFX 导出用的 CSP 命名容器
#
#  在非 Windows 平台上, 本文件不会被加载。
# ============================================================

if (-not (Get-Command Get-CertText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'CertI18n.ps1')
}
if (-not (Get-Command Test-IsWindowsHost -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'CertCore.ps1')
}

# ------------------------------------------------------------
#  环境探测
# ------------------------------------------------------------
function Test-IsAdministrator {
    try {
        $id = [System.Security.Principal.WindowsIdentity]::GetCurrent()
        $pr = New-Object System.Security.Principal.WindowsPrincipal($id)
        return $pr.IsInRole([System.Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Test-CertReqAvailable {
    if (-not (Test-IsWindowsHost)) { return $false }
    return [bool](Get-Command certreq.exe -ErrorAction SilentlyContinue)
}

function Get-CertStoreLocations {
    return @('Cert:\CurrentUser\My', 'Cert:\LocalMachine\My')
}

function Get-RequestStoreLocations {
    return @('Cert:\CurrentUser\Request', 'Cert:\LocalMachine\Request')
}

# ------------------------------------------------------------
#  CSP 命名容器 —— 生成"可再导出"的 PFX 必需
#  (无参数 RSACryptoServiceProvider 会落到临时容器, 私钥以后导不出来)
# ------------------------------------------------------------
function New-RsaWithCspContainer {
    param(
        [string]$ContainerName,
        [int]$ProviderType = 24,   # PROV_RSA_AES
        [int]$KeyNumber = 1        # AT_KEYEXCHANGE
    )
    if (-not $ContainerName) { $ContainerName = 'CertToolkit-' + [guid]::NewGuid().ToString('N') }

    $csp = New-Object System.Security.Cryptography.CspParameters
    $csp.ProviderType = $ProviderType
    $csp.KeyContainerName = $ContainerName
    $csp.KeyNumber = $KeyNumber
    return (New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList @($csp))
}

# ------------------------------------------------------------
#  certreq INF 生成与调用
# ------------------------------------------------------------
function ConvertTo-AnsiOrUnicodeBytes {
    <# certreq 的 INF 需要 ANSI 或 Unicode。
       能无损转成 ANSI 就用 ANSI, 否则写 UTF-16LE (带 BOM)。 #>
    param([string]$Text)
    $ansi = [System.Text.Encoding]::GetEncoding([System.Globalization.CultureInfo]::CurrentCulture.TextInfo.ANSICodePage)
    $bytes = $ansi.GetBytes($Text)
    if ($ansi.GetString($bytes) -eq $Text) {
        return [PSCustomObject]@{ Bytes = $bytes; Encoding = 'ansi' }
    }
    $unicode = New-Object System.Text.UnicodeEncoding($false, $true)
    return [PSCustomObject]@{ Bytes = $unicode.GetBytes($Text); Encoding = 'utf16' }
}

function Build-InfContent {
    param(
        [hashtable]$Subject,
        [string[]]$EkuOids = @(),
        [int]$KeyLength = 2048,
        [string]$HashAlg = 'SHA256',
        [bool]$Exportable = $true,
        [bool]$MachineKeySet = $false,
        [string[]]$SanLines = @()
    )
    $sb = New-Object System.Text.StringBuilder
    $parts = @()
    foreach ($k in @('C', 'S', 'L', 'O', 'OU', 'CN', 'E')) {
        $v = [string]$Subject[$k]
        if ($v -ne '') { $parts += ($k + '=' + $v) }
    }

    [void]$sb.AppendLine('[NewRequest]')
    [void]$sb.AppendLine('Subject = "' + ($parts -join ', ') + '"')
    [void]$sb.AppendLine('KeyLength = ' + $KeyLength)
    [void]$sb.AppendLine('HashAlgorithm = ' + $HashAlg)
    [void]$sb.AppendLine('Exportable = ' + $Exportable.ToString().ToUpperInvariant())
    [void]$sb.AppendLine('MachineKeySet = ' + $MachineKeySet.ToString().ToUpperInvariant())
    [void]$sb.AppendLine('RequestType = PKCS10')

    # EKU: 每行一个 OID —— certreq 唯一支持的多 EKU 写法
    if (@($EkuOids).Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('[EnhancedKeyUsageExtension]')
        foreach ($oid in @($EkuOids)) { [void]$sb.AppendLine('OID=' + $oid) }
    }
    # SAN: 用 & 连接
    if (@($SanLines).Count -gt 0) {
        [void]$sb.AppendLine('')
        [void]$sb.AppendLine('[Extensions]')
        [void]$sb.AppendLine('2.5.29.17 = "{text}' + (@($SanLines) -join '&') + '"')
    }
    return $sb.ToString()
}

function Invoke-CertReqNative {
    <# 调用 certreq.exe, 把 stdout/stderr 合并成一条记录 #>
    param([string[]]$Arguments)
    $so = Join-Path ([System.IO.Path]::GetTempPath()) ('certreq_o_' + [guid]::NewGuid().ToString('N') + '.txt')
    $se = Join-Path ([System.IO.Path]::GetTempPath()) ('certreq_e_' + [guid]::NewGuid().ToString('N') + '.txt')
    $out = ''
    $code = -1
    try {
        $p = Start-Process -FilePath 'certreq.exe' -ArgumentList $Arguments -PassThru `
                           -WindowStyle Hidden -Wait -RedirectStandardOutput $so -RedirectStandardError $se
        if (Test-Path -LiteralPath $so) { $out += (Get-Content -LiteralPath $so -Raw -ErrorAction SilentlyContinue) }
        if (Test-Path -LiteralPath $se) { $out += (Get-Content -LiteralPath $se -Raw -ErrorAction SilentlyContinue) }
        $code = $p.ExitCode
    } catch {
        return [PSCustomObject]@{ Ok = $false; ExitCode = -1; Output = $_.Exception.Message }
    } finally {
        Remove-Item -LiteralPath $so, $se -Force -ErrorAction SilentlyContinue
    }
    if ($null -eq $out) { $out = '' }
    return [PSCustomObject]@{ Ok = ($code -eq 0); ExitCode = $code; Output = ([string]$out).Trim() }
}

function New-CsrViaCertReq {
    <# 用 certreq 生成 CSR。私钥会留在本机密钥容器里 (tq-<GUID>)。
       返回 @{ Ok; Output; InfPath } #>
    param(
        [string]$OutFile,
        [string]$InfContent,
        [switch]$KeepInf
    )
    if (-not (Test-CertReqAvailable)) { throw (Get-CertText 'err.certreq.missing') }

    $infFile = [System.IO.Path]::ChangeExtension($OutFile, '.inf')
    $enc = ConvertTo-AnsiOrUnicodeBytes $InfContent
    [System.IO.File]::WriteAllBytes($infFile, $enc.Bytes)
    if (Test-Path -LiteralPath $OutFile) { Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue }

    $r = Invoke-CertReqNative @('-new', $infFile, $OutFile)
    if (-not $KeepInf) { Remove-Item -LiteralPath $infFile -Force -ErrorAction SilentlyContinue }

    return [PSCustomObject]@{
        Ok      = (Test-Path -LiteralPath $OutFile)
        Output  = $r.Output
        InfPath = $infFile
        InfEnc  = $enc.Encoding
    }
}

function Install-CertificateFromFile {
    <# certreq -accept: 把证书装进本机证书存储, 并和已存在的私钥配对。
       ★ 这是唯一会写证书存储的动作, 由用户显式勾选后才调用。 #>
    param([string]$CertPath)
    if (-not (Test-CertReqAvailable)) {
        return [PSCustomObject]@{ Ok = $false; Message = (Get-CertText 'err.certreq.missing') }
    }
    $r = Invoke-CertReqNative @('-accept', $CertPath)
    $okMsg = ($r.Output -match '已安装|installed|Installed') -or ($r.Ok -and $r.Output -notmatch '失败|错误|Error|error')
    return [PSCustomObject]@{ Ok = [bool]$okMsg; Message = $r.Output; Raw = $r.Output }
}

# ------------------------------------------------------------
#  证书存储
# ------------------------------------------------------------
function Get-CertificatesFromStore {
    param([string[]]$Locations, [switch]$WithPrivateKey)
    $out = @()
    foreach ($loc in @($Locations)) {
        try {
            foreach ($c in @(Get-ChildItem -Path $loc -ErrorAction SilentlyContinue)) {
                if ($WithPrivateKey -and -not $c.HasPrivateKey) { continue }
                $out += $c
            }
        } catch { }
    }
    return $out
}

function Find-CertWithPrivateKey {
    <# 在证书存储里找与给定证书配对的私钥。
       先按指纹, 再退一步按公钥 (证书重签发过的情况)。 #>
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
    if (-not $Cert) { return $null }
    $stores = Get-CertStoreLocations

    foreach ($s in $stores) {
        $hit = Get-ChildItem -Path $s -ErrorAction SilentlyContinue | Where-Object {
            $_.HasPrivateKey -and ($_.Thumbprint -eq $Cert.Thumbprint)
        } | Select-Object -First 1
        if ($hit) { return $hit }
    }

    $pub = $null
    try { $pub = $Cert.GetPublicKey() } catch { }
    if (-not $pub) { return $null }
    foreach ($s in $stores) {
        $hit = Get-ChildItem -Path $s -ErrorAction SilentlyContinue | Where-Object {
            if (-not $_.HasPrivateKey) { return $false }
            try { return (Test-BytesEqual $_.GetPublicKey() $pub) } catch { return $false }
        } | Select-Object -First 1
        if ($hit) { return $hit }
    }
    return $null
}

# ------------------------------------------------------------
#  密钥容器扫描 —— 找回孤立私钥
#  ------------------------------------------------------------
#  certreq -new 把私钥写进密钥容器, 但那时还没有证书, 所以私钥是"孤立"的:
#  它不在 Cert:\...\My 里, 只能靠比较公钥认回来。
#  容器名是证书服务自动生成的 (tq-<GUID>), 没有任何索引记录它属于哪个 CSR。
# ------------------------------------------------------------
function Get-KeyContainerNames {
    <# 列出密钥容器名。certutil -key 输出形如:
         Microsoft Strong Cryptographic Provider:
           tq-7a488002-1240-4759-8346-139328bef03f      <- 容器名 (2 空格缩进)
           fc6b9604d6262c41beaa9c3fbfa3a479_<GUID>      <- 密钥文件名 (跳过)
           RSA                                          <- 类型 (跳过)
             AT_SIGNATURE                               <- 用途 (跳过)
       -Machine 用机器存储 (需要管理员, 否则拿不到) #>
    param([switch]$Machine)
    if (-not (Test-IsWindowsHost)) { return @() }

    $args2 = @()
    if (-not $Machine) { $args2 += '-user' }
    $args2 += '-key'

    $raw = @()
    try { $raw = & certutil.exe @args2 2>&1 } catch { return @() }

    $names = @()
    foreach ($l in $raw) {
        $s = [string]$l
        if ($s -notmatch '^  (\S.*)$') { continue }
        $v = $Matches[1].Trim()
        if ($v -match '^(RSA|DSA|ECDSA|ECDH|ECC|DH)$') { continue }
        if ($v -match '_[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$') { continue }
        if ($v -match '^AT_') { continue }
        $names += $v
    }
    return $names
}

function Get-RsaParamsFromContainer {
    <# 用容器名把密钥读出来。KeyNumber: 1 = AT_KEYEXCHANGE, 2 = AT_SIGNATURE
       (certreq 生成的签名密钥是 AT_SIGNATURE, 所以默认 2) #>
    param(
        [string]$Container,
        [int]$KeyNumber = 2,
        [int]$ProviderType = 1,
        [switch]$Machine,
        [switch]$Private
    )
    $csp = New-Object System.Security.Cryptography.CspParameters
    $csp.ProviderType = $ProviderType
    $csp.KeyContainerName = $Container
    $csp.KeyNumber = $KeyNumber

    $flags = [System.Security.Cryptography.CspProviderFlags]::UseExistingKey
    if ($Machine) { $flags = $flags -bor [System.Security.Cryptography.CspProviderFlags]::UseMachineKeyStore }
    $csp.Flags = $flags

    $rsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider -ArgumentList @($csp)
    try {
        return $rsa.ExportParameters([bool]$Private)
    } finally {
        try { $rsa.Dispose() } catch { }
    }
}

function Find-OrphanKeyContainer {
    <# 在密钥容器里找出与 $Cert 公钥相同的那一个 (只读)。
       找到 -> @{ Container; KeyNumber; ProviderType; Machine }
       找不到 -> $null #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [switch]$IncludeMachine
    )
    if (-not $Cert -or -not (Test-IsWindowsHost)) { return $null }

    $target = Get-RsaPublicParameters $Cert
    if (-not $target) { return $null }

    $machines = @($false)
    if ($IncludeMachine) { $machines += $true }

    foreach ($machine in $machines) {
        foreach ($n in (Get-KeyContainerNames -Machine:$machine)) {
            foreach ($kn in @(2, 1)) {
                try {
                    $p = Get-RsaParamsFromContainer -Container $n -KeyNumber $kn -Machine:$machine
                    if ($p -and $p.Modulus -and (Test-BytesEqual $p.Modulus $target.Modulus)) {
                        return [PSCustomObject]@{
                            Container    = $n
                            KeyNumber    = $kn
                            ProviderType = 1
                            Machine      = [bool]$machine
                        }
                    }
                } catch { }
            }
        }
    }
    return $null
}

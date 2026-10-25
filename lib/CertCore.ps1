# ============================================================
#  CertCore.ps1  —  跨平台证书 / 密钥核心库
#  ------------------------------------------------------------
#  纯 .NET 实现, 不依赖 certreq / openssl / 平台证书存储。
#  在 Windows PowerShell 5.1 (.NET Framework 4.8) 与
#  PowerShell 7+ (.NET 6/8/10, Windows / Linux / macOS) 上均可运行。
#
#  上层调用者:  CertHelper.ps1 (加载器) -> CertToolkit.ps1 (GUI)
#                                       -> csrtool.ps1     (CLI)
# ============================================================

# i18n 是硬依赖; 允许单独引用本文件时自动补载
if (-not (Get-Command Get-CertText -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'CertI18n.ps1')
}

$script:CertToolVersion = '2.0.0'

# ------------------------------------------------------------
#  平台 / 运行时探测
# ------------------------------------------------------------
function Test-IsCoreEdition {
    return ([string]$PSVersionTable.PSEdition -eq 'Core')
}

function Test-IsWindowsHost {
    if (Test-IsCoreEdition) { return [bool]$IsWindows }
    return ([System.Environment]::OSVersion.Platform -eq [System.PlatformID]::Win32NT)
}

function Get-CertToolVersion { return $script:CertToolVersion }

function Get-PlatformLabel {
    if (Test-IsWindowsHost) { $os = 'Windows' }
    elseif ($IsMacOS) { $os = 'macOS' }
    elseif ($IsLinux) { $os = 'Linux' }
    else { $os = [System.Environment]::OSVersion.Platform.ToString() }
    $ed = if (Test-IsCoreEdition) { 'PowerShell ' + $PSVersionTable.PSVersion } else { 'Windows PowerShell ' + $PSVersionTable.PSVersion }
    return "$os / $ed"
}

# ------------------------------------------------------------
#  通用工具
# ------------------------------------------------------------
function Test-BytesEqual {
    param([byte[]]$A, [byte[]]$B)
    if ($null -eq $A -or $null -eq $B) { return $false }
    if ($A.Length -ne $B.Length) { return $false }
    for ($i = 0; $i -lt $A.Length; $i++) { if ($A[$i] -ne $B[$i]) { return $false } }
    return $true
}

function Join-Bytes {
    <# 把若干 byte[] 拼成一个 byte[]。
       ★ 参数刻意用 [object[]] 而不是 [byte[][]]:
         PowerShell 在 @(...) 里会自动展开嵌套数组, 甚至把 byte[] 拆成单个 byte;
         这里递归规范化, 无论传进来的是 byte / byte[] / 混合数组都能拼对。 #>
    param([object[]]$Parts)

    $acc = New-Object System.Collections.Generic.List[byte]
    Add-BytesInto $acc $Parts
    return ,([byte[]]$acc.ToArray())
}

function Add-BytesInto {
    param($Acc, $Item)
    if ($null -eq $Item) { return }
    if ($Item -is [byte[]]) {
        foreach ($b in $Item) { $Acc.Add($b) }
        return
    }
    if ($Item -is [byte]) { $Acc.Add($Item); return }
    if ($Item -is [char]) { $Acc.Add([byte][int]$Item); return }
    if ($Item -is [int] -or $Item -is [long] -or $Item -is [uint32]) { $Acc.Add([byte]$Item); return }
    if ($Item -is [System.Collections.IEnumerable] -and -not ($Item -is [string])) {
        foreach ($x in $Item) { Add-BytesInto $Acc $x }
        return
    }
    foreach ($b in [byte[]]$Item) { $Acc.Add($b) }
}

function Get-FileText {
    <# 读取文本文件; 自动跳过 UTF-8 BOM, 对二进制内容容错 #>
    param([string]$Path)
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    return (Get-BytesAsText $bytes)
}

function Get-BytesAsText {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return '' }
    if ($Bytes.Length -ge 3 -and $Bytes[0] -eq 0xEF -and $Bytes[1] -eq 0xBB -and $Bytes[2] -eq 0xBF) {
        return [System.Text.Encoding]::UTF8.GetString($Bytes, 3, $Bytes.Length - 3)
    }
    if ($Bytes.Length -ge 2 -and $Bytes[0] -eq 0xFF -and $Bytes[1] -eq 0xFE) {
        return [System.Text.Encoding]::Unicode.GetString($Bytes, 2, $Bytes.Length - 2)
    }
    try { return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($Bytes) }
    catch { return [System.Text.Encoding]::ASCII.GetString($Bytes) }
}

function Write-TextFileNoBom {
    param([string]$Path, [string]$Text)
    $dir = [System.IO.Path]::GetDirectoryName($Path)
    if ($dir -and -not [System.IO.Directory]::Exists($dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    [System.IO.File]::WriteAllText($Path, $Text, (New-Object System.Text.UTF8Encoding($false)))
}

# ------------------------------------------------------------
#  ASN.1 DER 读取
# ------------------------------------------------------------
function Read-DerElement {
    param([byte[]]$Data, [ref]$Pos)
    $p = $Pos.Value
    if ($p -ge $Data.Length) { throw (Get-CertText 'err.der.overflow') }
    $tag = $Data[$p]; $p++
    if ($p -ge $Data.Length) { throw (Get-CertText 'err.der.overflow') }
    $len = $Data[$p]; $p++
    if ($len -band 0x80) {
        $n = $len -band 0x7F
        if ($n -gt 4) { throw (Get-CertText 'err.der.length.too.long') }
        $len = 0
        for ($i = 0; $i -lt $n; $i++) {
            if ($p -ge $Data.Length) { throw (Get-CertText 'err.der.overflow') }
            $len = ($len -shl 8) -bor $Data[$p]; $p++
        }
    }
    if (($p + $len) -gt $Data.Length) { throw (Get-CertText 'err.der.content.overflow') }
    $val = New-Object byte[] $len
    [System.Array]::Copy($Data, $p, $val, 0, $len)
    $Pos.Value = $p + $len
    return [PSCustomObject]@{ Tag = $tag; Length = $len; Value = $val }
}

function ConvertFrom-DerInteger {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { return ,([byte[]]@(0)) }
    $i = 0
    while ($i -lt ($Bytes.Length - 1) -and $Bytes[$i] -eq 0) { $i++ }
    $out = New-Object byte[] ($Bytes.Length - $i)
    [System.Array]::Copy($Bytes, $i, $out, 0, $out.Length)
    return ,$out
}

# ------------------------------------------------------------
#  ASN.1 DER 构造
# ------------------------------------------------------------
function ConvertTo-DerLength {
    param([int]$Len)
    if ($Len -lt 0x80) { return ,([byte[]]@($Len)) }
    $bytes = New-Object System.Collections.Generic.List[byte]
    $v = $Len
    while ($v -gt 0) { $bytes.Insert(0, [byte]($v -band 0xFF)); $v = $v -shr 8 }
    $head = New-Object System.Collections.Generic.List[byte]
    $head.Add([byte](0x80 -bor $bytes.Count))
    foreach ($b in $bytes) { $head.Add($b) }
    return ,([byte[]]$head.ToArray())
}

function ConvertTo-DerInteger {
    param([byte[]]$Bytes)
    if ($null -eq $Bytes -or $Bytes.Length -eq 0) { $Bytes = [byte[]]@(0) }
    $i = 0
    while ($i -lt ($Bytes.Length - 1) -and $Bytes[$i] -eq 0) { $i++ }
    $v = New-Object byte[] ($Bytes.Length - $i)
    [System.Array]::Copy($Bytes, $i, $v, 0, $v.Length)
    if ($v[0] -band 0x80) {
        $tmp = New-Object byte[] ($v.Length + 1)
        [System.Array]::Copy($v, 0, $tmp, 1, $v.Length)
        $v = $tmp
    }
    return ,(Join-Bytes @([byte[]]@(0x02), (ConvertTo-DerLength $v.Length), $v))
}

function ConvertTo-DerSequence {
    param([object[]]$Parts)
    $body = Join-Bytes $Parts
    return ,(Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $body.Length), $body))
}

function ConvertTo-DerOid {
    param([string]$Oid)
    $text = ([string]$Oid).Trim()
    if ($text -notmatch '^\d+(\.\d+)+$') { throw (Get-CertText 'err.oid.invalid' $text) }
    $parts = $text.Split('.')
    $first = [int]$parts[0]
    $second = [int]$parts[1]
    if ($first -lt 0 -or $first -gt 2) { throw (Get-CertText 'err.oid.invalid' $text) }
    if ($second -lt 0 -or $second -gt 39) { throw (Get-CertText 'err.oid.invalid' $text) }

    $body = New-Object System.Collections.Generic.List[byte]
    $body.Add([byte](($first * 40) + $second))
    for ($i = 2; $i -lt $parts.Length; $i++) {
        $v = [uint64]$parts[$i]
        if ($v -eq 0) { $body.Add([byte]0); continue }
        $stack = New-Object System.Collections.Generic.List[byte]
        while ($v -gt 0) { $stack.Insert(0, [byte]($v -band 0x7F)); $v = $v -shr 7 }
        for ($j = 0; $j -lt $stack.Count - 1; $j++) { $stack[$j] = [byte]($stack[$j] -bor 0x80) }
        foreach ($b in $stack) { $body.Add($b) }
    }
    $arr = [byte[]]$body.ToArray()
    return ,(Join-Bytes @([byte[]]@(0x06), (ConvertTo-DerLength $arr.Length), $arr))
}

function ConvertTo-DerString {
    <# 生成字符串类型 TLV。
       Tag: 0x0C = UTF8String, 0x13 = PrintableString, 0x16 = IA5String,
            外加 0x81/0x82/0x86 等隐式标签的 GeneralName 分支。 #>
    param([string]$Text, [byte]$Tag = 0x0C)
    $value = if ($null -eq $Text) { '' } else { [string]$Text }
    $enc = switch ($Tag) {
        0x13 { [System.Text.Encoding]::ASCII }
        0x16 { [System.Text.Encoding]::ASCII }
        0x81 { [System.Text.Encoding]::ASCII }
        0x82 { [System.Text.Encoding]::ASCII }
        0x86 { [System.Text.Encoding]::ASCII }
        default { New-Object System.Text.UTF8Encoding($false) }
    }
    $b = $enc.GetBytes($value)
    return ,(Join-Bytes @([byte[]]@($Tag), (ConvertTo-DerLength $b.Length), $b))
}

# ------------------------------------------------------------
#  可分辨名称 (DN) 构造 —— 自己做 DER, 避免各平台解析差异
# ------------------------------------------------------------
$script:DnAttributes = @(
    @{ Key = 'C';  Oid = '2.5.4.6';               Tag = 0x13 },
    @{ Key = 'S';  Oid = '2.5.4.8';               Tag = 0x0C },
    @{ Key = 'L';  Oid = '2.5.4.7';               Tag = 0x0C },
    @{ Key = 'O';  Oid = '2.5.4.10';              Tag = 0x0C },
    @{ Key = 'OU'; Oid = '2.5.4.11';              Tag = 0x0C },
    @{ Key = 'CN'; Oid = '2.5.4.3';               Tag = 0x0C },
    @{ Key = 'E';  Oid = '1.2.840.113549.1.9.1';  Tag = 0x16 }
)

function New-DistinguishedNameDer {
    param([hashtable]$Fields)
    $rdns = @()
    foreach ($attr in $script:DnAttributes) {
        $v = [string]$Fields[$attr.Key]
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        $atvBody = Join-Bytes @((ConvertTo-DerOid $attr.Oid), (ConvertTo-DerString $v.Trim() $attr.Tag))
        $atv = Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $atvBody.Length), $atvBody)
        $set = Join-Bytes @([byte[]]@(0x31), (ConvertTo-DerLength $atv.Length), $atv)
        $rdns += , $set
    }
    if ($rdns.Count -eq 0) { throw (Get-CertText 'err.dn.empty') }
    $body = Join-Bytes $rdns
    return ,(Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $body.Length), $body))
}

function Get-DistinguishedNameText {
    <# 把字段拼成 RFC2253 风格的可读字符串 (仅用于显示) #>
    param([hashtable]$Fields)
    $parts = @()
    foreach ($attr in $script:DnAttributes) {
        $v = [string]$Fields[$attr.Key]
        if ([string]::IsNullOrWhiteSpace($v)) { continue }
        $parts += ($attr.Key + '=' + $v.Trim())
    }
    return ($parts -join ', ')
}

# ------------------------------------------------------------
#  主题备用名称 SAN (2.5.29.17) —— 手写 DER, 全平台一致
# ------------------------------------------------------------
function ConvertTo-DerIpAddress {
    param([string]$Ip)
    $addr = $null
    if (-not [System.Net.IPAddress]::TryParse(([string]$Ip).Trim(), [ref]$addr)) {
        throw (Get-CertText 'err.san.ip' $Ip)
    }
    $b = $addr.GetAddressBytes()
    return ,(Join-Bytes @([byte[]]@(0x87), (ConvertTo-DerLength $b.Length), $b))
}

function ConvertTo-DerUpnOtherName {
    <# otherName [0] { type-id 1.3.6.1.4.1.311.20.2.3, value [0] UTF8String } #>
    param([string]$Upn)
    $oid  = ConvertTo-DerOid '1.3.6.1.4.1.311.20.2.3'
    $str  = ConvertTo-DerString $Upn 0x0C
    $wrap = Join-Bytes @([byte[]]@(0xA0), (ConvertTo-DerLength $str.Length), $str)
    $seqBody = Join-Bytes @($oid, $wrap)
    $seq = Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $seqBody.Length), $seqBody)
    return ,(Join-Bytes @([byte[]]@(0xA0), (ConvertTo-DerLength $seq.Length), $seq))
}

function New-SanExtensionDer {
    <# 输入形如 dns=a.com / ipaddress=1.2.3.4 / email=a@b.c / upn=user@dom / URL=https://...
       输出 GeneralNames 的 DER (extension 的 extnValue 内容) #>
    param([string[]]$Entries)
    $names = @()
    foreach ($raw in @($Entries)) {
        $s = ([string]$raw).Trim()
        if ($s -eq '') { continue }
        $i = $s.IndexOf('=')
        if ($i -lt 1) { throw (Get-CertText 'err.san.format' $s) }
        $type = $s.Substring(0, $i).Trim().ToLowerInvariant()
        $val  = $s.Substring($i + 1).Trim()
        if ($val -eq '') { throw (Get-CertText 'err.san.value.empty' $s) }
        switch ($type) {
            'dns'       { $names += , (ConvertTo-DerString $val 0x82) }
            'email'     { $names += , (ConvertTo-DerString $val 0x81) }
            'url'       { $names += , (ConvertTo-DerString $val 0x86) }
            'uri'       { $names += , (ConvertTo-DerString $val 0x86) }
            'ipaddress' { $names += , (ConvertTo-DerIpAddress $val) }
            'ip'        { $names += , (ConvertTo-DerIpAddress $val) }
            'upn'       { $names += , (ConvertTo-DerUpnOtherName $val) }
            default     { throw (Get-CertText 'err.san.type' $type) }
        }
    }
    if ($names.Count -eq 0) { return $null }
    $body = Join-Bytes $names
    return ,(Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $body.Length), $body))
}

function New-EkuExtensionDer {
    <# EnhancedKeyUsage ::= SEQUENCE OF KeyPurposeId(OID) #>
    param([string[]]$Oids)
    $ids = @()
    foreach ($o in @($Oids)) {
        $s = ([string]$o).Trim()
        if ($s -eq '') { continue }
        $ids += , (ConvertTo-DerOid $s)
    }
    if ($ids.Count -eq 0) { return $null }
    $body = Join-Bytes $ids
    return ,(Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $body.Length), $body))
}

# ------------------------------------------------------------
#  PKCS#1 <-> RSAParameters
# ------------------------------------------------------------
function ConvertFrom-Pkcs1Rsa {
    param([byte[]]$Der)
    $pos = 0
    $seq = Read-DerElement $Der ([ref]$pos)
    if ($seq.Tag -ne 0x30) { throw (Get-CertText 'err.pkcs1.structure') }
    $inner = $seq.Value
    $p = 0
    $null = Read-DerElement $inner ([ref]$p)      # version
    $mod = Read-DerElement $inner ([ref]$p)       # modulus
    $exp = Read-DerElement $inner ([ref]$p)       # publicExponent
    $d   = Read-DerElement $inner ([ref]$p)       # privateExponent
    $p1  = Read-DerElement $inner ([ref]$p)       # prime1
    $p2  = Read-DerElement $inner ([ref]$p)       # prime2
    $e1  = Read-DerElement $inner ([ref]$p)       # exponent1
    $e2  = Read-DerElement $inner ([ref]$p)       # exponent2
    $co  = Read-DerElement $inner ([ref]$p)       # coefficient

    $parms = New-Object System.Security.Cryptography.RSAParameters
    $parms.Modulus  = ConvertFrom-DerInteger $mod.Value
    $parms.Exponent = ConvertFrom-DerInteger $exp.Value
    $parms.D        = ConvertFrom-DerInteger $d.Value
    $parms.P        = ConvertFrom-DerInteger $p1.Value
    $parms.Q        = ConvertFrom-DerInteger $p2.Value
    $parms.DP       = ConvertFrom-DerInteger $e1.Value
    $parms.DQ       = ConvertFrom-DerInteger $e2.Value
    $parms.InverseQ = ConvertFrom-DerInteger $co.Value
    return $parms
}

function ConvertTo-Pkcs1Rsa {
    param([System.Security.Cryptography.RSAParameters]$P)
    $parts = @(
        (ConvertTo-DerInteger ([byte[]]@(0)))
        (ConvertTo-DerInteger $P.Modulus)
        (ConvertTo-DerInteger $P.Exponent)
        (ConvertTo-DerInteger $P.D)
        (ConvertTo-DerInteger $P.P)
        (ConvertTo-DerInteger $P.Q)
        (ConvertTo-DerInteger $P.DP)
        (ConvertTo-DerInteger $P.DQ)
        (ConvertTo-DerInteger $P.InverseQ)
    )
    return (ConvertTo-DerSequence $parts)
}

# ------------------------------------------------------------
#  PKCS#8 包装 (PrivateKeyInfo)
#  .NET Framework 4.8 没有 ExportPkcs8PrivateKey, 所以自己拼
# ------------------------------------------------------------
function ConvertTo-Pkcs8Rsa {
    param([System.Security.Cryptography.RSAParameters]$P)
    $pkcs1 = ConvertTo-Pkcs1Rsa $P
    # AlgorithmIdentifier { rsaEncryption, NULL }
    $algId = [byte[]](0x30, 0x0D, 0x06, 0x09, 0x2A, 0x86, 0x48, 0x86, 0xF7, 0x0D, 0x01, 0x01, 0x01, 0x05, 0x00)
    $oct = Join-Bytes @([byte[]]@(0x04), (ConvertTo-DerLength $pkcs1.Length), $pkcs1)
    $inner = Join-Bytes @([byte[]]@(0x02, 0x01, 0x00), $algId, $oct)
    return ,(Join-Bytes @([byte[]]@(0x30), (ConvertTo-DerLength $inner.Length), $inner))
}

function ConvertFrom-Pkcs8Rsa {
    param([byte[]]$Der)
    $pos = 0
    $seq = Read-DerElement $Der ([ref]$pos)
    if ($seq.Tag -ne 0x30) { throw (Get-CertText 'err.pkcs8.structure') }
    $p = 0
    $null = Read-DerElement $seq.Value ([ref]$p)   # version
    $null = Read-DerElement $seq.Value ([ref]$p)   # AlgorithmIdentifier
    $oct = Read-DerElement $seq.Value ([ref]$p)    # privateKey OCTET STRING
    if ($oct.Tag -ne 0x04) { throw (Get-CertText 'err.pkcs8.octet') }
    return (ConvertFrom-Pkcs1Rsa $oct.Value)
}

# ------------------------------------------------------------
#  PEM 读写
# ------------------------------------------------------------
function Get-PemBlocks {
    param([string]$Text)
    $blocks = @()
    if ([string]::IsNullOrEmpty($Text)) { return $blocks }
    $rx = [regex]::new('-----\s*BEGIN\s+([A-Za-z0-9 ]+?)\s*-----(.*?)-----\s*END\s+\1\s*-----', [System.Text.RegularExpressions.RegexOptions]::Singleline)
    foreach ($m in $rx.Matches($Text)) {
        $label = $m.Groups[1].Value.Trim()
        $b64 = ($m.Groups[2].Value -replace '\s', '')
        if ($b64 -eq '') { continue }
        $blocks += [PSCustomObject]@{ Label = $label; Base64 = $b64 }
    }
    return $blocks
}

function ConvertTo-PemBlock {
    param([byte[]]$Der, [string]$Label)
    $b64 = [System.Convert]::ToBase64String($Der)
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append("-----BEGIN $Label-----`n")
    for ($i = 0; $i -lt $b64.Length; $i += 64) {
        [void]$sb.Append($b64.Substring($i, [System.Math]::Min(64, $b64.Length - $i)))
        [void]$sb.Append("`n")
    }
    [void]$sb.Append("-----END $Label-----`n")
    return $sb.ToString()
}

function ConvertTo-PemCertificate {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
    return (ConvertTo-PemBlock $Cert.RawData 'CERTIFICATE')
}

function ConvertFrom-PemPrivateKey {
    <# 支持 PKCS#1 (RSA PRIVATE KEY) 与 PKCS#8 (PRIVATE KEY) #>
    param([string]$PemText)
    $blocks = @(Get-PemBlocks $PemText)
    if ($blocks.Count -eq 0) { throw (Get-CertText 'err.pem.no.block') }

    foreach ($b in $blocks) {
        $label = $b.Label
        if ($label -match 'ENCRYPTED') {
            throw (Get-CertText 'err.key.encrypted')
        }
        if ($label -match 'OPENSSH') {
            throw (Get-CertText 'err.key.openssh')
        }
        if ($label -match '^EC PRIVATE KEY$') {
            throw (Get-CertText 'err.key.ec')
        }
        if ($label -match '^RSA PRIVATE KEY$') {
            return (ConvertFrom-Pkcs1Rsa ([System.Convert]::FromBase64String($b.Base64)))
        }
        if ($label -match '^PRIVATE KEY$') {
            return (ConvertFrom-Pkcs8Rsa ([System.Convert]::FromBase64String($b.Base64)))
        }
    }
    throw (Get-CertText 'err.key.no.rsa')
}

function ConvertTo-PemPrivateKey {
    <# Format: Pkcs1 (默认) 或 Pkcs8 #>
    param(
        [System.Security.Cryptography.RSAParameters]$P,
        [string]$Format = 'Pkcs1'
    )
    if ($Format -eq 'Pkcs8') {
        return (ConvertTo-PemBlock (ConvertTo-Pkcs8Rsa $P) 'PRIVATE KEY')
    }
    return (ConvertTo-PemBlock (ConvertTo-Pkcs1Rsa $P) 'RSA PRIVATE KEY')
}

function Read-PrivateKeyFile {
    <# 读私钥文件: PEM 或裸 DER (PKCS#1 / PKCS#8) #>
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw (Get-CertText 'err.file.notfound' $Path) }
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = Get-BytesAsText $bytes
    if ($text -match '-----BEGIN') {
        return (ConvertFrom-PemPrivateKey $text)
    }
    # 裸 DER: 先按 PKCS#1 试, 再按 PKCS#8
    try { return (ConvertFrom-Pkcs1Rsa $bytes) } catch { }
    try { return (ConvertFrom-Pkcs8Rsa $bytes) } catch { }
    throw (Get-CertText 'err.key.unreadable' $Path)
}

function New-RsaKeyPair {
    param([int]$KeySize = 2048)
    $rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
    try {
        $parms = $rsa.ExportParameters($true)
    } finally { $rsa.Dispose() }
    return $parms
}

# ------------------------------------------------------------
#  哈希算法
# ------------------------------------------------------------
function ConvertTo-HashAlgorithmName {
    param([string]$Name)
    $n = ([string]$Name).ToUpperInvariant().Replace('-', '')
    switch ($n) {
        'SHA1'   { return [System.Security.Cryptography.HashAlgorithmName]::SHA1 }
        'SHA256' { return [System.Security.Cryptography.HashAlgorithmName]::SHA256 }
        'SHA384' { return [System.Security.Cryptography.HashAlgorithmName]::SHA384 }
        'SHA512' { return [System.Security.Cryptography.HashAlgorithmName]::SHA512 }
        default  { throw (Get-CertText 'err.hash.unsupported' $Name) }
    }
}

# ------------------------------------------------------------
#  CSR (PKCS#10) —— 纯 .NET 生成, 跨平台
# ------------------------------------------------------------
function Test-CsrBackendAvailable {
    return [bool]('System.Security.Cryptography.X509Certificates.CertificateRequest' -as [type])
}

function New-CsrRequest {
    param(
        [hashtable]$Fields,
        [string[]]$EkuOids = @(),
        [string[]]$SanEntries = @(),
        [int]$KeySize = 2048,
        [string]$HashAlgorithm = 'SHA256',
        $Rsa = $null
    )
    if (-not (Test-CsrBackendAvailable)) { throw (Get-CertText 'err.no.certificaterequest') }

    $ownKey = $false
    if (-not $Rsa) {
        $Rsa = [System.Security.Cryptography.RSA]::Create($KeySize)
        $ownKey = $true
    }
    try {
        $dnDer = New-DistinguishedNameDer $Fields
        $dn = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new([byte[]]$dnDer)
        $hash = ConvertTo-HashAlgorithmName $HashAlgorithm
        $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $dn, $Rsa, $hash, [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)

        $san = New-SanExtensionDer $SanEntries
        if ($san) {
            [void]$req.CertificateExtensions.Add(
                [System.Security.Cryptography.X509Certificates.X509Extension]::new('2.5.29.17', [byte[]]$san, $false))
        }
        $eku = New-EkuExtensionDer $EkuOids
        if ($eku) {
            [void]$req.CertificateExtensions.Add(
                [System.Security.Cryptography.X509Certificates.X509Extension]::new('2.5.29.37', [byte[]]$eku, $false))
        }

        $der = $req.CreateSigningRequest()
        return [PSCustomObject]@{
            Der     = $der
            Pem     = (ConvertTo-PemBlock $der 'CERTIFICATE REQUEST')
            Rsa     = $Rsa
            OwnsKey = $ownKey
            Extensions = $req.CertificateExtensions.Count
        }
    } catch {
        if ($ownKey -and $Rsa) { try { $Rsa.Dispose() } catch { } }
        throw
    }
}

function Get-CsrSummaryText {
    <# 粗略解析 CSR 的 DN 与扩展 OID, 用于日志核对 #>
    param([byte[]]$Der)
    $lines = @()
    try {
        $pos = 0
        $outer = Read-DerElement $Der ([ref]$pos)
        if ($outer.Tag -ne 0x30) { throw (Get-CertText 'csr.unparsed') }

        $p = 0
        $ci = Read-DerElement $outer.Value ([ref]$p)         # CertificationRequestInfo
        if ($ci.Tag -ne 0x30) { throw (Get-CertText 'csr.unparsed') }

        $q = 0
        $null = Read-DerElement $ci.Value ([ref]$q)          # version
        $subject = Read-DerElement $ci.Value ([ref]$q)       # subject (Name)
        $lines += ((Get-CertText 'csr.subject') + ': ' + (ConvertFrom-DnDer (Get-DerElementRaw $subject)))

        $null = Read-DerElement $ci.Value ([ref]$q)          # subjectPKInfo
        if ($q -lt $ci.Value.Length) {
            $attrs = Read-DerElement $ci.Value ([ref]$q)     # attributes [0] IMPLICIT SET
            if ($attrs.Tag -eq 0xA0) {
                foreach ($oidText in (Get-CsrExtensionOids $attrs.Value)) {
                    $lines += ('  ' + (Get-CertText 'csr.extension') + ': ' + $oidText)
                }
            }
        }
    } catch {
        $lines += (Get-CertText 'csr.unparsed')
    }
    return ($lines -join "`n")
}

function Get-DerElementRaw {
    <# 把 Read-DerElement 的结果还原成完整 TLV (tag + length + value) #>
    param($Element)
    return ,(Join-Bytes @([byte[]]@($Element.Tag), (ConvertTo-DerLength $Element.Length), $Element.Value))
}

function Get-CsrExtensionOids {
    <# 从 CertificationRequestInfo 的 attributes 里取出 extensionRequest 的扩展 OID 列表。
       结构: [0] SET OF Attribute
             Attribute   = SEQUENCE { type OID, values SET OF ANY }
             values      = SET { SEQUENCE OF Extension }
             Extension   = SEQUENCE { extnID OID, [critical], extnValue OCTET STRING } #>
    param([byte[]]$AttributesContent)
    $oids = @()
    if ($null -eq $AttributesContent -or $AttributesContent.Length -eq 0) { return $oids }

    $r = 0
    while ($r -lt $AttributesContent.Length) {
        $attr = Read-DerElement $AttributesContent ([ref]$r)
        if ($attr.Tag -ne 0x30) { continue }

        $a = 0
        $typeOid = Read-DerElement $attr.Value ([ref]$a)
        if ($typeOid.Tag -ne 0x06) { continue }
        if ((ConvertDerOidText $typeOid.Value) -ne '1.2.840.113549.1.9.14') { continue }

        $vals = Read-DerElement $attr.Value ([ref]$a)
        if ($vals.Tag -ne 0x31) { continue }

        $s = 0
        $extensions = Read-DerElement $vals.Value ([ref]$s)
        if ($extensions.Tag -ne 0x30) { continue }

        $e = 0
        while ($e -lt $extensions.Value.Length) {
            $ext = Read-DerElement $extensions.Value ([ref]$e)
            if ($ext.Tag -ne 0x30) { continue }
            $x = 0
            $extOid = Read-DerElement $ext.Value ([ref]$x)
            if ($extOid.Tag -eq 0x06) { $oids += (ConvertDerOidText $extOid.Value) }
        }
    }
    return $oids
}

function ConvertFrom-DnDer {
    <# 把 DN 的 DER 解成 "CN=..., O=..." 便于显示。
       同时接受两种输入: 完整的 RDNSequence (0x30 ...) 或它的内容 (直接以 RDN 的 0x31 开头)。 #>
    param([byte[]]$Der)
    $parts = @()
    if ($null -eq $Der -or $Der.Length -eq 0) { return '' }
    try {
        $content = $Der
        if ($Der[0] -eq 0x30) {
            $pos = 0
            $seq = Read-DerElement $Der ([ref]$pos)
            $content = $seq.Value
        }
        $p = 0
        while ($p -lt $content.Length) {
            $set = Read-DerElement $content ([ref]$p)
            if ($set.Tag -ne 0x31) { break }
            $s = 0
            while ($s -lt $set.Value.Length) {
                $atv = Read-DerElement $set.Value ([ref]$s)
                $a = 0
                $oid = Read-DerElement $atv.Value ([ref]$a)
                $val = Read-DerElement $atv.Value ([ref]$a)
                $key = Get-DnAttributeKey (ConvertDerOidText $oid.Value)
                $parts += ($key + '=' + (Get-BytesAsText $val.Value))
            }
        }
    } catch { }
    return ($parts -join ', ')
}

function Get-DnAttributeKey {
    param([string]$Oid)
    switch ($Oid) {
        '2.5.4.6'               { return 'C' }
        '2.5.4.8'               { return 'S' }
        '2.5.4.7'               { return 'L' }
        '2.5.4.10'              { return 'O' }
        '2.5.4.11'              { return 'OU' }
        '2.5.4.3'               { return 'CN' }
        '1.2.840.113549.1.9.1'  { return 'E' }
        default                 { return $Oid }
    }
}

function ConvertDerOidText {
    param([byte[]]$OidBytes)
    if ($null -eq $OidBytes -or $OidBytes.Length -eq 0) { return '' }
    $first = [int]$OidBytes[0]
    $parts = @([string][Math]::Floor($first / 40), [string]($first % 40))
    $v = 0
    for ($i = 1; $i -lt $OidBytes.Length; $i++) {
        $b = [int]$OidBytes[$i]
        $v = ($v -shl 7) -bor ($b -band 0x7F)
        if (-not ($b -band 0x80)) { $parts += [string]$v; $v = 0 }
    }
    return ($parts -join '.')
}

# ------------------------------------------------------------
#  证书文件读取
# ------------------------------------------------------------
function Get-CertificateFromFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw (Get-CertText 'err.file.notfound' $Path) }
    $ext = [System.IO.Path]::GetExtension($Path).ToLowerInvariant()
    if ($ext -eq '.pfx' -or $ext -eq '.p12') { throw (Get-CertText 'err.is.pfx') }

    $bytes = [System.IO.File]::ReadAllBytes($Path)

    # 1) DER
    try {
        $c = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$bytes)
        if ($c) { return $c }
    } catch { }

    # 2) PEM
    $text = Get-BytesAsText $bytes
    $blocks = @(Get-PemBlocks $text)
    $cb = $blocks | Where-Object { $_.Label -match 'CERTIFICATE' } | Select-Object -First 1
    if ($cb) {
        return [System.Security.Cryptography.X509Certificates.X509Certificate2]::new([System.Convert]::FromBase64String($cb.Base64))
    }
    throw (Get-CertText 'err.cert.unreadable' $Path)
}

function Get-AllCertificatesFromFile {
    <# 返回文件里所有证书 (叶子 + 链)。支持 PEM / DER / PKCS#7 #>
    param([string]$Path)
    $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
    if (-not (Test-Path -LiteralPath $Path)) { return $col }

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $text = Get-BytesAsText $bytes
    $blocks = @(Get-PemBlocks $text)

    if ($blocks.Count -gt 0) {
        foreach ($b in $blocks) {
            if ($b.Label -notmatch 'CERTIFICATE') { continue }
            try {
                [void]$col.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                    [System.Convert]::FromBase64String($b.Base64)))
            } catch { }
        }
    } else {
        try { $col.Import([byte[]]$bytes) } catch { }
        if ($col.Count -eq 0) {
            try { [void]$col.Add([System.Security.Cryptography.X509Certificates.X509Certificate2]::new([byte[]]$bytes)) } catch { }
        }
    }
    return $col
}

# ------------------------------------------------------------
#  证书 / 私钥匹配与来源
# ------------------------------------------------------------
function Get-RsaFromCert {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
    if (-not $Cert) { return $null }
    try {
        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPrivateKey($Cert)
        if ($rsa) { return $rsa }
    } catch { }
    try {
        if ($Cert.PrivateKey) { return $Cert.PrivateKey }
    } catch { }   # .NET Core 上 PrivateKey 属性会抛 PlatformNotSupported
    return $null
}

function Get-RsaPublicParameters {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
    $pub = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($Cert)
    if (-not $pub) { return $null }
    try { return $pub.ExportParameters($false) } finally { try { $pub.Dispose() } catch { } }
}

function Test-KeyMatchesCert {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [System.Security.Cryptography.RSAParameters]$Params
    )
    try {
        $certParams = Get-RsaPublicParameters $Cert
        if (-not $certParams -or -not $Params.Modulus) { return $false }
        return ((Test-BytesEqual $certParams.Modulus $Params.Modulus) -and
                (Test-BytesEqual $certParams.Exponent $Params.Exponent))
    } catch {
        return $false
    }
}

function Get-CertSummary {
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert)
    $lines = @()
    $lines += (Get-CertText 'cert.subject')   + ': ' + $Cert.Subject
    $lines += (Get-CertText 'cert.issuer')    + ': ' + $Cert.Issuer
    $lines += (Get-CertText 'cert.serial')    + ': ' + $Cert.SerialNumber
    $lines += (Get-CertText 'cert.thumb')     + ': ' + $Cert.Thumbprint
    $lines += (Get-CertText 'cert.validity')  + ': ' + $Cert.NotBefore.ToString('yyyy-MM-dd HH:mm:ss') +
              '  ~  ' + $Cert.NotAfter.ToString('yyyy-MM-dd HH:mm:ss')
    $left = ($Cert.NotAfter - (Get-Date)).Days
    $suffix = ''
    if ($left -lt 0) { $suffix = '  ' + (Get-CertText 'cert.expired') }
    elseif ($left -lt 30) { $suffix = '  ' + (Get-CertText 'cert.expiring') }
    $lines += (Get-CertText 'cert.daysleft') + ': ' + $left + $suffix
    $lines += (Get-CertText 'cert.hasprivatekey') + ': ' + $Cert.HasPrivateKey

    $sig = ''
    try { $sig = $Cert.SignatureAlgorithm.FriendlyName } catch { }
    if (-not $sig) { try { $sig = $Cert.SignatureAlgorithm.Value } catch { } }
    if ($sig) { $lines += (Get-CertText 'cert.sigalg') + ': ' + $sig }

    $lines += ''
    $lines += '--- ' + (Get-CertText 'cert.extensions') + ' ---'
    foreach ($e in $Cert.Extensions) {
        $n = ''
        try { $n = $e.Oid.FriendlyName } catch { }
        if (-not $n) { try { $n = $e.Oid.Value } catch { } }
        $lines += ('[' + $e.Oid.Value + '] ' + $n)
        try {
            foreach ($l in ($e.Format($false) -split "`r?`n")) {
                if ($l.Trim() -ne '') { $lines += ('    ' + $l.Trim()) }
            }
        } catch { }
    }
    return ($lines -join "`n")
}

# ------------------------------------------------------------
#  PFX 读写
# ------------------------------------------------------------
function Get-PfxLoadFlags {
    <# 读 PFX 时的密钥存储标志。
       ★ .NET Framework 4.8 上 EphemeralKeySet 导入进来的私钥【不可再导出】
         (实测), 所以只有 .NET Core 才用临时密钥集。
         .NET Core 用临时密钥集可以避免把私钥写进当前用户的密钥存储。 #>
    $flags = [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::Exportable
    if (Test-IsCoreEdition) {
        try {
            $flags = $flags -bor [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        } catch { }
    }
    return $flags
}

function ConvertFrom-PfxFile {
    param([string]$Path, [string]$Password)
    if (-not (Test-Path -LiteralPath $Path)) { throw (Get-CertText 'err.file.notfound' $Path) }

    $col = $null
    $lastErr = $null
    $candidates = @((Get-PfxLoadFlags), ([System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::DefaultKeySet))
    foreach ($flags in $candidates) {
        try {
            $c = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
            $c.Import($Path, $Password, $flags)
            if ($c.Count -gt 0) { $col = $c; break }
        } catch { $lastErr = $_ }
    }
    if (-not $col) {
        $msg = if ($lastErr) { $lastErr.Exception.Message } else { '' }
        throw (Get-CertText 'err.pfx.load' $msg)
    }

    $all = @($col)
    $leaf = $all | Where-Object { $_.HasPrivateKey } | Select-Object -First 1
    $chain = @()
    foreach ($c in $all) {
        if (-not $leaf -or $c.Thumbprint -ne $leaf.Thumbprint) { $chain += $c }
    }

    $parms = $null
    if ($leaf) {
        $rsa = Get-RsaFromCert $leaf
        if ($rsa) {
            try { $parms = $rsa.ExportParameters($true) } catch { }
            try { $rsa.Dispose() } catch { }
        }
    }

    return [PSCustomObject]@{
        All     = $all
        Leaf    = $leaf
        Chain   = $chain
        Params  = $parms
        Count   = $all.Count
    }
}

function New-RsaForPfxExport {
    <# 生成用于 PFX 导出的 RSA 对象。
       Windows: 用 CSP (PROV_RSA_AES) 命名容器 —— 这是唯一能保证
                「PFX 的私钥以后还能再导出」的做法 (见使用说明)。
       其它平台: 用 RSA.Create() (OpenSSL 实现) 即可。
       返回 @{ Rsa; Cleanup } #>
    param(
        [System.Security.Cryptography.RSAParameters]$Params,
        [switch]$Portable
    )

    # -Portable 强制走"不用 CSP 容器"的路径 (等价于非 Windows 平台的行为)。
    # .NET Framework 上这条路产出的是"私钥不可再导出"的 PFX, 属于已知限制,
    # 与其静默产出一个以后没法备份的证书, 不如直接报错说清楚。
    if ($Portable -and (Test-IsWindowsHost) -and -not (Test-IsCoreEdition)) {
        throw (Get-CertText 'err.pfx.portable.framework')
    }

    if (-not $Portable -and (Test-IsWindowsHost) -and
        (Get-Command New-RsaWithCspContainer -ErrorAction SilentlyContinue)) {
        $rsa = New-RsaWithCspContainer
        $rsa.ImportParameters($Params)
        return [PSCustomObject]@{
            Rsa = $rsa
            Cleanup = {
                param($r)
                try { $r.PersistKeyInCsp = $false } catch { }
                try { $r.Clear() } catch { }
                try { $r.Dispose() } catch { }
            }
        }
    }

    $rsa = [System.Security.Cryptography.RSA]::Create()
    $rsa.ImportParameters($Params)
    return [PSCustomObject]@{
        Rsa = $rsa
        Cleanup = { param($r) try { $r.Dispose() } catch { } }
    }
}

function New-PfxFromCertAndKey {
    <# 证书 + 私钥参数 -> PFX 文件。返回到 PFX 的字节数。 #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [System.Security.Cryptography.RSAParameters]$Params,
        [string]$PfxPath,
        [string]$Password,
        $Chain = @(),
        [switch]$Portable
    )

    if (-not $Cert) { throw (Get-CertText 'err.cert.missing') }
    if (-not $Params.Modulus) { throw (Get-CertText 'err.key.missing') }

    $holder = New-RsaForPfxExport -Params $Params -Portable:$Portable

    $rsa = $holder.Rsa
    try {
        $withKey = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::CopyWithPrivateKey($Cert, $rsa)
        if (-not $withKey.HasPrivateKey) { throw (Get-CertText 'err.pfx.nokey') }

        $col = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2Collection
        [void]$col.Add($withKey)
        foreach ($c in @($Chain)) {
            if ($c -and $c.Thumbprint -ne $withKey.Thumbprint) { [void]$col.Add($c) }
        }

        $bytes = $col.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Pfx, $Password)
        if ($PfxPath) {
            $dir = [System.IO.Path]::GetDirectoryName($PfxPath)
            if ($dir -and -not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }
            [System.IO.File]::WriteAllBytes($PfxPath, $bytes)
        }
        return $bytes.Length
    } finally {
        try { & $holder.Cleanup $rsa } catch { }
    }
}

# ------------------------------------------------------------
#  输出辅助
# ------------------------------------------------------------
function New-MergedPemText {
    <# 证书(+链) + 私钥 -> 单个 PEM 文本 #>
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [System.Security.Cryptography.RSAParameters]$Params,
        $Chain = @(),
        [string]$KeyFormat = 'Pkcs1',
        [switch]$NoChain
    )
    $sb = New-Object System.Text.StringBuilder
    [void]$sb.Append((ConvertTo-PemCertificate $Cert))
    if (-not $NoChain) {
        foreach ($c in @($Chain)) {
            if ($c -and $c.Thumbprint -ne $Cert.Thumbprint) { [void]$sb.Append((ConvertTo-PemCertificate $c)) }
        }
    }
    [void]$sb.Append((ConvertTo-PemPrivateKey $Params $KeyFormat))
    return $sb.ToString()
}

function Get-SafeFileName {
    param([string]$Name, [int]$MaxLength = 80)
    $s = ([string]$Name).Trim()
    if ($s -eq '') { return 'certificate' }
    foreach ($ch in @('\', '/', ':', '*', '?', '"', '<', '>', '|')) { $s = $s.Replace($ch, '_') }
    $s = $s -replace '[\x00-\x1F]', '_'
    $s = $s -replace '\s+', '_'
    $s = $s.Trim('_', '.')
    if ($s -eq '') { $s = 'certificate' }
    if ($s.Length -gt $MaxLength) { $s = $s.Substring(0, $MaxLength) }
    return $s
}

function Get-DefaultOutputDirectory {
    $desktop = ''
    try { $desktop = [System.Environment]::GetFolderPath('Desktop') } catch { }
    if ($desktop -and (Test-Path -LiteralPath $desktop)) { return $desktop }
    try {
        $home2 = [System.Environment]::GetFolderPath('UserProfile')
        if ($home2 -and (Test-Path -LiteralPath $home2)) { return $home2 }
    } catch { }
    return (Get-Location).Path
}

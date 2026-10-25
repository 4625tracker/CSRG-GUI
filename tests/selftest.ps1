#Requires -Version 5.1
<#
    tests\selftest.ps1  —  证书工具箱自检

    在 Windows PowerShell 5.1 与 PowerShell 7+ 上都能跑:
        powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\selftest.ps1
        pwsh -NoProfile -File .\tests\selftest.ps1

    退出码: 0 = 全部通过, 1 = 有失败
#>

param([switch]$Quiet)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CertHelper.ps1')

$script:Pass = 0
$script:Fail = 0
$script:Failures = @()
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('certtool_selftest_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tmp)

function Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        if ($r -eq $false) { throw 'returned false' }
        $script:Pass++
        if (-not $Quiet) { Write-Host ("  PASS  " + $Name) -ForegroundColor Green }
    } catch {
        $script:Fail++
        $script:Failures += ($Name + ' -> ' + $_.Exception.Message)
        Write-Host ("  FAIL  " + $Name + "  ->  " + $_.Exception.Message) -ForegroundColor Red
    }
}

function New-TestCertPair {
    param([string]$Cn = 'test.example.com')
    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    try {
        $parms = $rsa.ExportParameters($true)
        $dnDer = New-DistinguishedNameDer @{ CN = $Cn; O = 'Test Org'; C = 'CN' }
        $name = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new([byte[]]$dnDer)
        $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $name, $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $cert = $req.CreateSelfSigned([datetime]::UtcNow.AddDays(-1), [datetime]::UtcNow.AddDays(30))
    } finally {
        try { $rsa.Dispose() } catch { }
    }
    $pubOnly = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cert.RawData)
    return [PSCustomObject]@{ Cert = $pubOnly; Params = $parms }
}

Write-Host ''
Write-Host ('=== ' + (Get-CertText 'app.title') + ' self-test ===')
Write-Host ((Get-CertText 'app.platform') + ': ' + (Get-PlatformLabel))
Write-Host ''

# ------------------------------------------------------------
Write-Host '[1] i18n' -ForegroundColor Cyan

Check 'all keys resolve in zh and en' {
    $bad = @()
    foreach ($lang in @('zh', 'en')) {
        Set-CertLanguage $lang | Out-Null
        foreach ($k in (Get-CertAllTextKeys)) {
            $v = Get-CertText $k
            if ([string]::IsNullOrWhiteSpace($v)) { $bad += "${lang}:${k}" }
            elseif ($v -eq $k) { $bad += "${lang}:${k}" }
        }
    }
    if ($bad.Count -gt 0) { throw ('unresolved: ' + ($bad -join ', ')) }
    $true
}

Check 'format placeholders are consistent' {
    $bad = @()
    foreach ($k in (Get-CertAllTextKeys)) {
        $entry = (Get-CertTextTable)[$k]
        $zhN = ([regex]::Matches($entry[0], '\{\d+\}')).Count
        $enN = ([regex]::Matches($entry[1], '\{\d+\}')).Count
        if ($zhN -ne $enN) { $bad += $k }
    }
    if ($bad.Count -gt 0) { throw ('placeholder mismatch: ' + ($bad -join ', ')) }
    $true
}

Check 'every literal key used in code exists' {
    $defined = @{}
    foreach ($k in (Get-CertAllTextKeys)) { $defined[$k] = $true }

    $files = @(Get-ChildItem -Path $root -Filter *.ps1 -Recurse -File |
               Where-Object { $_.Name -notmatch '^_probe' -and $_.FullName -notlike '*\tests\*' })
    $missing = @()
    foreach ($f in $files) {
        $text = Get-BytesAsText ([System.IO.File]::ReadAllBytes($f.FullName))
        foreach ($m in [regex]::Matches($text, "(?:Get-CertText|(?<![\w-])T)\s+'([A-Za-z0-9._-]+)'")) {
            $key = $m.Groups[1].Value
            if (-not $defined.ContainsKey($key)) { $missing += ($f.Name + ':' + $key) }
        }
    }
    if ($missing.Count -gt 0) { throw ('undefined keys: ' + (($missing | Sort-Object -Unique) -join ', ')) }
    $true
}

Set-CertLanguage 'zh' | Out-Null

# ------------------------------------------------------------
Write-Host '[2] ASN.1 / DN' -ForegroundColor Cyan

Check 'DN DER with Chinese builds and round-trips' {
    $der = New-DistinguishedNameDer @{ CN = '测试证书'; O = '某某公司'; OU = '运维部'; C = 'CN'; E = 'a@example.com' }
    $text = ConvertFrom-DnDer $der
    return ($text -match 'CN=测试证书' -and $text -match 'O=某某公司' -and $text -match 'C=CN' -and $text -match 'E=a@example.com')
}

Check 'DN rejects empty subject' {
    try { $null = New-DistinguishedNameDer @{} ; return $false } catch { return $true }
}

Check 'OID encode/decode' {
    $der = ConvertTo-DerOid '1.3.6.1.5.5.7.3.2'
    $pos = 0
    $el = Read-DerElement $der ([ref]$pos)
    return ((ConvertDerOidText $el.Value) -eq '1.3.6.1.5.5.7.3.2')
}

Check 'invalid OID rejected' {
    try { $null = ConvertTo-DerOid '1.3.bad'; return $false } catch { return $true }
}

Check 'DER length encodes long form' {
    $b = ConvertTo-DerLength 300
    return ($b.Length -eq 3 -and $b[0] -eq 0x82 -and $b[1] -eq 0x01 -and $b[2] -eq 0x2C)
}

# ------------------------------------------------------------
Write-Host '[3] RSA key PEM' -ForegroundColor Cyan

Check 'PKCS#1 PEM round-trip' {
    $p = New-RsaKeyPair 2048
    $pem = ConvertTo-PemPrivateKey $p 'Pkcs1'
    if ($pem -notmatch 'BEGIN RSA PRIVATE KEY') { throw 'wrong label' }
    $back = ConvertFrom-PemPrivateKey $pem
    return ((Test-BytesEqual $back.Modulus $p.Modulus) -and (Test-BytesEqual $back.D $p.D))
}

Check 'PKCS#8 PEM round-trip' {
    $p = New-RsaKeyPair 2048
    $pem = ConvertTo-PemPrivateKey $p 'Pkcs8'
    if ($pem -notmatch 'BEGIN PRIVATE KEY') { throw 'wrong label' }
    $back = ConvertFrom-PemPrivateKey $pem
    return ((Test-BytesEqual $back.Modulus $p.Modulus) -and (Test-BytesEqual $back.D $p.D))
}

Check 'encrypted key is rejected with a hint' {
    $fake = "-----BEGIN ENCRYPTED PRIVATE KEY-----`nAAAA`n-----END ENCRYPTED PRIVATE KEY-----`n"
    try { $null = ConvertFrom-PemPrivateKey $fake; return $false }
    catch { return ($_.Exception.Message -match 'openssl|pkcs8|加密|ENCRYPTED') }
}

Check 'key file round-trip through disk' {
    $p = New-RsaKeyPair 2048
    $path = Join-Path $tmp 'k.pem'
    Write-TextFileNoBom $path (ConvertTo-PemPrivateKey $p 'Pkcs1')
    $back = Read-PrivateKeyFile $path
    return (Test-BytesEqual $back.Modulus $p.Modulus)
}

# ------------------------------------------------------------
Write-Host '[4] CSR' -ForegroundColor Cyan

Check 'CSR with SAN + EKU builds and parses' {
    $r = New-CsrRequest -Fields @{ CN = 'nas.example.com'; O = 'Test'; C = 'CN' } `
        -EkuOids @('1.3.6.1.5.5.7.3.2', '1.3.6.1.5.5.7.3.1') `
        -SanEntries @('dns=nas.example.com', 'ipaddress=10.0.0.5', 'email=a@example.com', 'upn=user@example.com', 'URL=https://x.example.com') `
        -KeySize 2048 -HashAlgorithm SHA256
    try {
        if ($r.Der.Length -lt 400) { throw 'too small' }
        if ($r.Pem -notmatch 'BEGIN CERTIFICATE REQUEST') { throw 'bad PEM label' }
        $sum = Get-CsrSummaryText $r.Der
        return ($sum -match 'nas\.example\.com' -and $sum -match '2\.5\.29\.17' -and $sum -match '2\.5\.29\.37')
    } finally { try { $r.Rsa.Dispose() } catch { } }
}

Check 'CSR with Chinese subject parses back' {
    $r = New-CsrRequest -Fields @{ CN = '中文站点'; OU = '测试部' } -KeySize 2048
    try {
        $sum = Get-CsrSummaryText $r.Der
        return ($sum -match '中文站点' -and $sum -match '测试部')
    } finally { try { $r.Rsa.Dispose() } catch { } }
}

Check 'CSR rejects bad SAN type' {
    try {
        $null = New-CsrRequest -Fields @{ CN = 'x' } -SanEntries @('bogus=1.2.3.4')
        return $false
    } catch { return $true }
}

Check 'CSR rejects invalid IP' {
    try {
        $null = New-CsrRequest -Fields @{ CN = 'x' } -SanEntries @('ipaddress=999.1.1.1')
        return $false
    } catch { return $true }
}

# ------------------------------------------------------------
Write-Host '[5] PFX merge / split' -ForegroundColor Cyan

Check 'CSP container path: PFX is complete and re-exportable' {
    $pair = New-TestCertPair 'pfx-csp.example.com'
    $pfx = Join-Path $tmp 'csp.pfx'
    $size = New-PfxFromCertAndKey -Cert $pair.Cert -Params $pair.Params -PfxPath $pfx -Password 'test123'
    if ($size -le 0) { throw 'empty pfx' }
    $back = ConvertFrom-PfxFile -Path $pfx -Password 'test123'
    if (-not $back.Leaf) { throw 'no leaf with key after re-import' }
    if (-not $back.Params) { throw 'private key not re-exportable' }
    return (Test-BytesEqual $back.Params.Modulus $pair.Params.Modulus)
}

Check 'portable path: PFX is complete and re-exportable' {
    $pair = New-TestCertPair 'pfx-portable.example.com'
    $pfx = Join-Path $tmp 'portable.pfx'

    if (-not (Test-IsCoreEdition)) {
        # .NET Framework 上这条路已知会产出"私钥不可再导出"的 PFX,
        # 预期行为是明确拒绝, 而不是静默产出坏文件
        try {
            $null = New-PfxFromCertAndKey -Cert $pair.Cert -Params $pair.Params -PfxPath $pfx -Password 'test123' -Portable
            throw 'should have refused on .NET Framework'
        } catch {
            return ($_.Exception.Message -match 'Portable|Framework|再导出|export')
        }
    }

    $null = New-PfxFromCertAndKey -Cert $pair.Cert -Params $pair.Params -PfxPath $pfx -Password 'test123' -Portable
    $back = ConvertFrom-PfxFile -Path $pfx -Password 'test123'
    if (-not $back.Params) { throw 'private key not re-exportable' }
    return (Test-BytesEqual $back.Params.Modulus $pair.Params.Modulus)
}

Check 'key/cert mismatch is detected' {
    $a = New-TestCertPair 'a.example.com'
    $b = New-TestCertPair 'b.example.com'
    return ((Test-KeyMatchesCert -Cert $a.Cert -Params $b.Params) -eq $false)
}

Check 'mismatch cannot be merged into a PFX' {
    $a = New-TestCertPair 'a2.example.com'
    $b = New-TestCertPair 'b2.example.com'
    try { $null = New-PfxFromCertAndKey -Cert $a.Cert -Params $b.Params -PfxPath (Join-Path $tmp 'bad.pfx') -Password 'x'; return $false }
    catch { return $true }
}

Check 'PFX split extracts matching key' {
    $pair = New-TestCertPair 'split.example.com'
    $pfx = Join-Path $tmp 'split.pfx'
    $null = New-PfxFromCertAndKey -Cert $pair.Cert -Params $pair.Params -PfxPath $pfx -Password 'pw'
    $back = ConvertFrom-PfxFile -Path $pfx -Password 'pw'
    $pem = ConvertTo-PemPrivateKey $back.Params 'Pkcs1'
    $parsed = ConvertFrom-PemPrivateKey $pem
    return (Test-BytesEqual $parsed.Modulus $pair.Params.Modulus)
}

Check 'PFX with wrong password fails cleanly' {
    $pair = New-TestCertPair 'wrongpw.example.com'
    $pfx = Join-Path $tmp 'wrongpw.pfx'
    $null = New-PfxFromCertAndKey -Cert $pair.Cert -Params $pair.Params -PfxPath $pfx -Password 'right'
    try { $null = ConvertFrom-PfxFile -Path $pfx -Password 'wrong'; return $false }
    catch { return $true }
}

# ------------------------------------------------------------
Write-Host '[6] PEM bundle / cert I/O' -ForegroundColor Cyan

Check 'merged PEM contains cert and key' {
    $pair = New-TestCertPair 'bundle.example.com'
    $text = New-MergedPemText -Cert $pair.Cert -Params $pair.Params
    $blocks = @(Get-PemBlocks $text)
    $certCount = @($blocks | Where-Object { $_.Label -eq 'CERTIFICATE' }).Count
    $keyCount  = @($blocks | Where-Object { $_.Label -eq 'RSA PRIVATE KEY' }).Count
    return ($certCount -eq 1 -and $keyCount -eq 1)
}

Check 'certificate file read (PEM and DER)' {
    $pair = New-TestCertPair 'io.example.com'
    $pemPath = Join-Path $tmp 'io.pem'
    $derPath = Join-Path $tmp 'io.der'
    Write-TextFileNoBom $pemPath (ConvertTo-PemCertificate $pair.Cert)
    [System.IO.File]::WriteAllBytes($derPath, $pair.Cert.RawData)

    $c1 = Get-CertificateFromFile $pemPath
    $c2 = Get-CertificateFromFile $derPath
    return ($c1.Thumbprint -eq $pair.Cert.Thumbprint -and $c2.Thumbprint -eq $pair.Cert.Thumbprint)
}

Check 'cert summary renders' {
    $pair = New-TestCertPair 'summary.example.com'
    $s = Get-CertSummary $pair.Cert
    return ($s -match 'CN=summary\.example\.com' -and $s.Length -gt 50)
}

Check 'safe file name strips separators' {
    $n = Get-SafeFileName 'a/b:c*d?e"f<g>h|i j'
    return ($n -notmatch '[\\/:*?"<>| ]')
}

Check 'default output directory exists' {
    $d = Get-DefaultOutputDirectory
    return (Test-Path -LiteralPath $d)
}

# ------------------------------------------------------------
Write-Host ''
Write-Host ("RESULT: {0} passed, {1} failed" -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    Write-Host ''
    foreach ($f in $script:Failures) { Write-Host ('  - ' + $f) -ForegroundColor Red }
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue

if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

#Requires -Version 5.1
<#
    tests\clitest.ps1  —  csrtool.ps1 端到端测试

    用法:
        pwsh -NoProfile -File .\tests\clitest.ps1
        pwsh -NoProfile -File .\tests\clitest.ps1 -Exe powershell.exe
        powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\clitest.ps1 -Exe powershell.exe

    会分别在 PS 5.1 与 PS 7 下各跑一遍 CLI (如果两者都存在)。
#>

param(
    [string]$Exe = ''
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'CertHelper.ps1')

$script:Pass = 0
$script:Fail = 0
$script:Failures = @()

function Write-CiAnnotation {
    param([string]$Text)
    if ($env:GITHUB_ACTIONS -ne 'true') { return }
    $oneLine = ($Text -replace "[\r\n]+", ' ')
    Write-Host ("::error file=tests/clitest.ps1::" + $oneLine)
}

function Check {
    param([string]$Name, [scriptblock]$Body)
    try {
        $r = & $Body
        if ($r -eq $false) { throw 'returned false' }
        $script:Pass++
        Write-Host ('  PASS  ' + $Name) -ForegroundColor Green
    } catch {
        $script:Fail++
        $detail = $Name + ' [' + $_.Exception.GetType().Name + '] -> ' + $_.Exception.Message
        $script:Failures += $detail
        Write-Host ('  FAIL  ' + $detail) -ForegroundColor Red
        Write-CiAnnotation $detail
    }
}

# ---- 准备材料: 一把私钥 + 一张与之匹配的自签证书 ----
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('certtool_cli_' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($tmp)

$parms = New-RsaKeyPair 2048
$keyFile = Join-Path $tmp 'issued-key.pem'
Write-TextFileNoBom $keyFile (ConvertTo-PemPrivateKey $parms 'Pkcs1')

$rsa = [System.Security.Cryptography.RSA]::Create()
$rsa.ImportParameters($parms)
try {
    $dnDer = New-DistinguishedNameDer @{ CN = 'cli.example.com'; O = 'Test Org'; C = 'CN' }
    $name = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new([byte[]]$dnDer)
    $req = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
        $name, $rsa,
        [System.Security.Cryptography.HashAlgorithmName]::SHA256,
        [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
    $cert = $req.CreateSelfSigned([datetime]::UtcNow.AddDays(-1), [datetime]::UtcNow.AddDays(30))
} finally { try { $rsa.Dispose() } catch { } }
$pub = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($cert.RawData)
$certFile = Join-Path $tmp 'issued.cer'
Write-TextFileNoBom $certFile (ConvertTo-PemCertificate $pub)

$cli = Join-Path $root 'csrtool.ps1'

function Invoke-Cli {
    param([string[]]$Arguments)
    $out = & $Exe -NoProfile -ExecutionPolicy Bypass -File $cli @Arguments 2>&1 | Out-String
    return [PSCustomObject]@{ Output = $out; Code = $LASTEXITCODE }
}

$targets = @()
if ($Exe -ne '') {
    $resolved = Get-Command $Exe -ErrorAction SilentlyContinue
    if (-not $resolved) { throw "not found: $Exe" }
    $targets += @{ Name = $Exe; Path = $resolved.Source -or $resolved.Name }
} else {
    foreach ($cand in @('powershell.exe', 'pwsh')) {
        $c = Get-Command $cand -ErrorAction SilentlyContinue
        if ($c) { $targets += @{ Name = $cand; Path = $c.Source } }
    }
    # 当前进程若都不是, 补一个
    if ($targets.Count -eq 0) { $targets += @{ Name = 'pwsh(cmdlet)'; Path = '' } }
}

foreach ($target in $targets) {
    $Exe = $target.Path
    if ($Exe -eq '') { continue }

    Write-Host ''
    Write-Host ('=== csrtool.ps1 under ' + $target.Name + ' ===') -ForegroundColor Cyan

    Check 'help exits 0 and prints usage' {
        $r = Invoke-Cli @('--help')
        return ($r.Code -eq 0 -and $r.Output -match 'new-csr' -and $r.Output -match 'merge-pfx')
    }

    Check 'version exits 0' {
        $r = Invoke-Cli @('-Version')
        return ($r.Code -eq 0 -and $r.Output -match '\d+\.\d+\.\d+')
    }

    Check 'new-csr writes CSR and key' {
        $csr = Join-Path $tmp ("csr_" + $target.Name + ".csr")
        $key = Join-Path $tmp ("csr_" + $target.Name + ".key")
        $r = Invoke-Cli @('new-csr', '-CN', 'nas.example.com', '-O', 'Test',
                          '-San', 'dns=nas.example.com,ipaddress=10.0.0.5',
                          '-Eku', '1.3.6.1.5.5.7.3.2,1.3.6.1.5.5.7.3.1',
                          '-KeyOut', $key, '-Out', $csr, '-Force')
        if ($r.Code -ne 0) { throw ('exit=' + $r.Code + ' ' + $r.Output) }
        if (-not (Test-Path -LiteralPath $csr)) { throw 'csr missing' }
        if (-not (Test-Path -LiteralPath $key)) { throw 'key missing' }

        $text = Get-FileText $csr
        if ($text -notmatch 'BEGIN CERTIFICATE REQUEST') { throw 'csr is not PEM' }
        $blocks = @(Get-PemBlocks $text)
        return ($blocks.Count -eq 1)
    }

    Check 'new-csr rejects missing CN' {
        $r = Invoke-Cli @('new-csr', '-Out', (Join-Path $tmp 'nope.csr'))
        return ($r.Code -ne 0)
    }

    Check 'new-csr refuses to overwrite without -Force' {
        $csr = Join-Path $tmp 'exists.csr'
        Write-TextFileNoBom $csr 'x'
        $key = Join-Path $tmp 'exists.key'
        $r = Invoke-Cli @('new-csr', '-CN', 'x.example.com', '-KeyOut', $key, '-Out', $csr)
        return ($r.Code -ne 0)
    }

    Check 'info shows certificate fields' {
        $r = Invoke-Cli @('info', '-Cert', $certFile)
        return ($r.Code -eq 0 -and $r.Output -match 'cli\.example\.com')
    }

    Check 'verify reports a match' {
        $r = Invoke-Cli @('verify', '-Cert', $certFile, '-Key', $keyFile)
        return ($r.Code -eq 0)
    }

    Check 'verify detects a mismatch' {
        $otherKey = Join-Path $tmp 'other.key'
        Write-TextFileNoBom $otherKey (ConvertTo-PemPrivateKey (New-RsaKeyPair 2048) 'Pkcs1')
        $r = Invoke-Cli @('verify', '-Cert', $certFile, '-Key', $otherKey)
        return ($r.Code -ne 0)
    }

    Check 'merge-pfx then split-pfx round-trip' {
        $pfx = Join-Path $tmp ("cli_" + $target.Name + ".pfx")
        $r1 = Invoke-Cli @('merge-pfx', '-Cert', $certFile, '-Key', $keyFile, '-Out', $pfx, '-Password', 'test123', '-Force')
        if ($r1.Code -ne 0) { throw ('merge exit=' + $r1.Code + ' ' + $r1.Output) }
        if (-not (Test-Path -LiteralPath $pfx)) { throw 'pfx missing' }

        $prefix = Join-Path $tmp ("split_" + $target.Name)
        $r2 = Invoke-Cli @('split-pfx', '-In', $pfx, '-Password', 'test123', '-Out', $prefix, '-Der', '-Force')
        if ($r2.Code -ne 0) { throw ('split exit=' + $r2.Code + ' ' + $r2.Output) }

        $certOut = $prefix + '-cert.pem'
        $keyOut = $prefix + '-key.pem'
        if (-not (Test-Path -LiteralPath $certOut)) { throw 'cert output missing' }
        if (-not (Test-Path -LiteralPath $keyOut)) { throw 'key output missing' }

        $back = ConvertFrom-PemPrivateKey (Get-FileText $keyOut)
        return (Test-BytesEqual $back.Modulus $parms.Modulus)
    }

    Check 'merge-pem writes a combined bundle' {
        $pem = Join-Path $tmp ("bundle_" + $target.Name + ".pem")
        $r = Invoke-Cli @('merge-pem', '-Cert', $certFile, '-Key', $keyFile, '-Out', $pem, '-Force')
        if ($r.Code -ne 0) { throw ('exit=' + $r.Code + ' ' + $r.Output) }
        $blocks = @(Get-PemBlocks (Get-FileText $pem))
        return ($blocks.Count -eq 2)
    }

    Check 'export-key writes a matching key' {
        $out = Join-Path $tmp ("exp_" + $target.Name + ".pem")
        $r = Invoke-Cli @('export-key', '-Cert', $certFile, '-Key', $keyFile, '-Out', $out, '-Force')
        if ($r.Code -ne 0) { throw ('exit=' + $r.Code + ' ' + $r.Output) }
        $back = ConvertFrom-PemPrivateKey (Get-FileText $out)
        return (Test-BytesEqual $back.Modulus $parms.Modulus)
    }

    Check 'english mode renders english text' {
        $r = Invoke-Cli @('-Language', 'en', 'info', '-Cert', $certFile)
        return ($r.Code -eq 0 -and $r.Output -match 'Subject')
    }

    Check 'unknown command exits non-zero' {
        $r = Invoke-Cli @('frobnicate')
        return ($r.Code -ne 0)
    }
}

Write-Host ''
Write-Host ('RESULT: {0} passed, {1} failed' -f $script:Pass, $script:Fail) -ForegroundColor $(if ($script:Fail -eq 0) { 'Green' } else { 'Red' })
if ($script:Fail -gt 0) {
    Write-Host ''
    foreach ($f in $script:Failures) { Write-Host ('  - ' + $f) -ForegroundColor Red }
}

Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }

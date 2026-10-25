#Requires -Version 5.1
<#
    证书工具箱  GUI  CertToolkit.ps1
    ============================================================
    标签页 1  生成 CSR
        · 选择证书用途 (EKU)、填写主题、配置密钥和 SAN
        · 两种后端:
            certreq   (默认, 仅 Windows) 私钥留在本机密钥容器
            .NET      (可移植) 私钥写成 <名字>-key.pem 文件
    标签页 2  合并 / 拆解
        · 证书文件 + 本机存储私钥   ->  PFX
        · 证书文件 + 私钥文件       ->  PFX
        · 证书文件 + 私钥文件       ->  合并 PEM
        · PFX 文件                  ->  拆解成证书 + 私钥

    兼容: Windows PowerShell 5.1 / PowerShell 7+
    依赖: 同目录 CertHelper.ps1 -> lib\*
#>

param(
    [string]$Language = '',
    [switch]$SelfTest
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = 'Stop'

$ScriptDir = $PSScriptRoot
if (-not $ScriptDir) { $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path }

$helperPath = Join-Path $ScriptDir 'CertHelper.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    [System.Windows.Forms.MessageBox]::Show(
        "CertHelper.ps1 not found next to this script.`r`n缺少 CertHelper.ps1",
        'Certificate Toolkit', 'OK', 'Error') | Out-Null
    exit 1
}
. $helperPath

if ($Language -ne '') { Set-CertLanguage $Language | Out-Null }

# ============================================================
#  外观
# ============================================================
function Get-UiFontName {
    if ((Get-CertLanguage) -eq 'zh') { return 'Microsoft YaHei UI' }
    return 'Segoe UI'
}

function Get-MonoFontName {
    foreach ($n in @('Consolas', 'Cascadia Mono', 'Courier New')) {
        try {
            $f = New-Object System.Drawing.Font($n, 9)
            $f.Dispose()
            return $n
        } catch { }
    }
    return 'Courier New'
}

# ============================================================
#  证书用途 (EKU)
# ============================================================
$script:EkuDefs = @(
    @{ Key = 'eku.client';       Oid = '1.3.6.1.5.5.7.3.2';        Default = $true  },
    @{ Key = 'eku.server';       Oid = '1.3.6.1.5.5.7.3.1';        Default = $false },
    @{ Key = 'eku.code';         Oid = '1.3.6.1.5.5.7.3.3';        Default = $false },
    @{ Key = 'eku.email';        Oid = '1.3.6.1.5.5.7.3.4';        Default = $false },
    @{ Key = 'eku.ipsec.end';    Oid = '1.3.6.1.5.5.7.3.5';        Default = $false },
    @{ Key = 'eku.ipsec.tunnel'; Oid = '1.3.6.1.5.5.7.3.6';        Default = $false },
    @{ Key = 'eku.ipsec.user';   Oid = '1.3.6.1.5.5.7.3.7';        Default = $false },
    @{ Key = 'eku.timestamp';    Oid = '1.3.6.1.5.5.7.3.8';        Default = $false },
    @{ Key = 'eku.ocsp';         Oid = '1.3.6.1.5.5.7.3.9';        Default = $false },
    @{ Key = 'eku.smartcard';    Oid = '1.3.6.1.4.1.311.20.2.2';   Default = $false },
    @{ Key = 'eku.rdp';          Oid = '1.3.6.1.4.1.311.54.1.2';   Default = $false }
)

# SAN 类型: 显示文字 -> certreq/内部使用的前缀
$script:SanTypes = @(
    @{ LabelKey = 'csr.san.dns';   Prefix = 'dns'       },
    @{ LabelKey = 'csr.san.ip';    Prefix = 'ipaddress' },
    @{ LabelKey = 'csr.san.email'; Prefix = 'email'     },
    @{ LabelKey = 'csr.san.upn';   Prefix = 'upn'       },
    @{ LabelKey = 'csr.san.url';   Prefix = 'URL'       }
)

$script:SanEntries = New-Object System.Collections.ArrayList
$script:Ctl = @{}
$script:Form = $null
$script:PendingLanguage = $null
$script:OutTouched = $false
$script:SuppressAuto = $false
$script:ModeRadios = @()

# ============================================================
#  主题信息校验
# ============================================================
$script:X500Limits = @{ CN = 64; OU = 64; O = 64; L = 128; S = 128; C = 2; E = 128 }
$script:DnTotalLimit = 256
$script:DnSpecialChars = [ordered]@{
    ',' = 'val.dn.comma'
    '+' = 'val.dn.plus'
    '"' = 'val.dn.quote'
    '\' = 'val.dn.backslash'
    '<' = 'val.dn.angleopen'
    '>' = 'val.dn.angleclose'
    ';' = 'val.dn.semicolon'
}

function Get-SubjectFields {
    return @{
        CN = $script:Ctl.tbCN.Text.Trim()
        O  = $script:Ctl.tbO.Text.Trim()
        OU = $script:Ctl.tbOU.Text.Trim()
        L  = $script:Ctl.tbL.Text.Trim()
        S  = $script:Ctl.tbS.Text.Trim()
        C  = $script:Ctl.tbC.Text.Trim()
        E  = $script:Ctl.tbE.Text.Trim()
    }
}

function Test-SubjectFields {
    param([hashtable]$F)
    $errs = @()
    $warns = @()
    $order = @('C', 'S', 'L', 'O', 'OU', 'CN', 'E')
    $labels = @{
        C = (Get-CertText 'csr.label.c'); S = (Get-CertText 'csr.label.s')
        L = (Get-CertText 'csr.label.l'); O = (Get-CertText 'csr.label.o')
        OU = (Get-CertText 'csr.label.ou'); CN = (Get-CertText 'csr.label.cn')
        E = (Get-CertText 'csr.label.e')
    }

    foreach ($k in $order) {
        $v = [string]$F[$k]
        if ($v -eq '') { continue }
        $lim = $script:X500Limits[$k]
        if ($v.Length -gt $lim) {
            $errs += (Get-CertText 'val.err.len' $labels[$k] $k $v.Length $lim)
        }
    }

    foreach ($k in $order) {
        $v = [string]$F[$k]
        if ($v -eq '') { continue }
        foreach ($ch in $script:DnSpecialChars.Keys) {
            if ($v.Contains($ch)) {
                $errs += (Get-CertText 'val.err.char' $labels[$k] $k $ch (Get-CertText $script:DnSpecialChars[$ch]))
            }
        }
    }

    $c = [string]$F.C
    if ($c -ne '' -and $c -notmatch '^[A-Za-z]{2}$') { $warns += (Get-CertText 'val.warn.country') }

    $e = [string]$F.E
    if ($e -ne '' -and $e -notmatch '^[^@\s,;]+@[^@\s,;]+\.[^@\s,;]+$') { $warns += (Get-CertText 'val.warn.email') }

    $total = 0
    foreach ($k in $order) {
        $v = [string]$F[$k]
        if ($v -ne '') { $total += ($k.Length + 1 + $v.Length + 2) }
    }
    if ($total -gt $script:DnTotalLimit) { $errs += (Get-CertText 'val.err.total' $total $script:DnTotalLimit) }

    return [PSCustomObject]@{ Errors = $errs; Warnings = $warns; Total = $total }
}

function Update-SubjectCheck {
    $lbl = $script:Ctl.lblSubjectCheck
    if (-not $lbl) { return }
    try {
        $f = Get-SubjectFields
        $r = Test-SubjectFields $f

        $parts = @()
        foreach ($k in @('CN', 'O', 'OU', 'L', 'S', 'C', 'E')) {
            $v = [string]$f[$k]
            if ($v -ne '') { $parts += ($k + ' ' + $v.Length + '/' + $script:X500Limits[$k]) }
        }
        $lenLine = ($parts -join '  ') + '   ' + $r.Total + '/' + $script:DnTotalLimit

        if ($r.Errors.Count -gt 0) {
            $lbl.ForeColor = [System.Drawing.Color]::Firebrick
            $more = ''
            if ($r.Errors.Count -gt 1) { $more = '  ' + (Get-CertText 'val.status.more' ($r.Errors.Count - 1)) }
            $lbl.Text = (Get-CertText 'val.status.err' ($r.Errors[0] + $more))
        } elseif ($r.Warnings.Count -gt 0) {
            $lbl.ForeColor = [System.Drawing.Color]::DarkOrange
            $more = ''
            if ($r.Warnings.Count -gt 1) { $more = '  ' + (Get-CertText 'val.status.more' ($r.Warnings.Count - 1)) }
            $lbl.Text = (Get-CertText 'val.status.warn' ($r.Warnings[0] + $more))
        } else {
            $lbl.ForeColor = [System.Drawing.Color]::ForestGreen
            $lbl.Text = (Get-CertText 'val.status.ok') + '      ' + $lenLine
        }
    } catch { }
}

# ============================================================
#  日志
# ============================================================
function Write-Log {
    param([System.Windows.Forms.RichTextBox]$Box, [string]$Text, [string]$Color = 'Black')
    if (-not $Box) { return }
    $ts = (Get-Date).ToString('HH:mm:ss')
    $Box.SelectionStart = $Box.TextLength
    $Box.SelectionLength = 0
    try { $Box.SelectionColor = [System.Drawing.Color]::FromName($Color) } catch { }
    $Box.AppendText('[' + $ts + '] ' + $Text + "`r`n")
    $Box.SelectionStart = $Box.TextLength
    $Box.ScrollToCaret()
    if (-not $SelfTest) { [System.Windows.Forms.Application]::DoEvents() }
}

# ============================================================
#  小工具
# ============================================================
function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 100, $Font = $null)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 22)
    $l.TextAlign = 'MiddleRight'
    if ($Font) { $l.Font = $Font }
    return $l
}

function New-Hint {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 300, $Font = $null)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 20)
    $l.ForeColor = [System.Drawing.Color]::Gray
    if ($Font) { $l.Font = $Font }
    return $l
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 300)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, 22)
    return $t
}

function New-Button {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 95)
    $b = New-Object System.Windows.Forms.Button
    $b.Text = $Text
    $b.Location = New-Object System.Drawing.Point($X, $Y)
    $b.Size = New-Object System.Drawing.Size($W, 25)
    return $b
}

function Show-Msg {
    param([string]$Text, [string]$Title, [string]$Buttons = 'OK', [string]$Icon = 'Information')
    if ($SelfTest) { return 'Yes' }
    return [System.Windows.Forms.MessageBox]::Show($Text, $Title, $Buttons, $Icon)
}

function Get-SelectedEkuOids {
    $ekus = @()
    foreach ($def in $script:EkuDefs) {
        $cb = $script:Ctl.EkuChecks[$def.Oid]
        if ($cb -and $cb.Checked) { $ekus += $def.Oid }
    }
    $custom = $script:Ctl.tbCustomOid.Text.Trim()
    if ($custom -ne '') {
        foreach ($o in ($custom -split ',')) {
            $v = $o.Trim()
            if ($v -match '^\d+(\.\d+)+$') { $ekus += $v }
        }
    }
    return $ekus
}

function Test-PortableMode {
    $cb = $script:Ctl.cbPortable
    return ($cb -and $cb.Checked)
}

# ============================================================
#  生成 CSR
# ============================================================
function Invoke-GenerateCsr {
    $vr = Test-SubjectFields (Get-SubjectFields)

    if ($vr.Errors.Count -gt 0) {
        $msg = (Get-CertText 'msg.invalid.header') + "`r`n`r`n"
        $i = 1
        foreach ($e in $vr.Errors) { $msg += '  ' + $i + ') ' + $e + "`r`n"; $i++ }
        $msg += "`r`n" + (Get-CertText 'msg.invalid.limits') + "`r`n" + (Get-CertText 'msg.invalid.chars')
        [void](Show-Msg $msg (Get-CertText 'msg.title.invalid') 'OK' 'Error')
        Write-Log $script:Ctl.log1 (Get-CertText 'msg.invalid.header') 'Red'
        return
    }

    if ($vr.Warnings.Count -gt 0) {
        $msg = (Get-CertText 'msg.warn.header') + "`r`n`r`n"
        $i = 1
        foreach ($w in $vr.Warnings) { $msg += '  ' + $i + ') ' + $w + "`r`n"; $i++ }
        $msg += "`r`n" + (Get-CertText 'msg.warn.footer')
        if ((Show-Msg $msg (Get-CertText 'msg.title.remind') 'YesNo' 'Warning') -ne 'Yes') { return }
    }

    if ($script:Ctl.tbCN.Text.Trim() -eq '') {
        [void](Show-Msg (Get-CertText 'msg.cn.required') (Get-CertText 'msg.title.missing') 'OK' 'Warning')
        return
    }

    $ekus = @(Get-SelectedEkuOids)
    if ($ekus.Count -eq 0) {
        if ((Show-Msg (Get-CertText 'msg.eku.none') (Get-CertText 'ui.warning') 'YesNo' 'Warning') -ne 'Yes') { return }
    }

    $outFile = $script:Ctl.tbOut.Text.Trim()
    if ($outFile -eq '') {
        [void](Show-Msg (Get-CertText 'msg.out.required') (Get-CertText 'ui.info') 'OK' 'Warning')
        return
    }

    $portable = Test-PortableMode
    $useCertReq = (-not $portable) -and (Test-CertReqAvailable)

    # ---- 覆盖确认 ----
    if (Test-Path -LiteralPath $outFile) {
        $cur = Get-Item -LiteralPath $outFile
        $msg = Get-CertText 'msg.exists.body' $outFile $cur.LastWriteTime.ToString('yyyy-MM-dd HH:mm')
        $r = Show-Msg $msg (Get-CertText 'msg.title.exists') 'YesNo' 'Warning'
        if ($r -ne 'Yes') {
            $dir = [System.IO.Path]::GetDirectoryName($outFile)
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($outFile)
            $ext = [System.IO.Path]::GetExtension($outFile)
            for ($i = 2; $i -le 99; $i++) {
                $cand = Join-Path $dir ($baseName + '-' + $i + $ext)
                if (-not (Test-Path -LiteralPath $cand)) {
                    $script:OutTouched = $true
                    $script:Ctl.tbOut.Text = $cand
                    $outFile = $cand
                    Write-Log $script:Ctl.log1 (Get-CertText 'msg.renamed' (Split-Path $outFile -Leaf)) 'DarkGreen'
                    break
                }
            }
        }
    }

    $fields = Get-SubjectFields
    $keySize = [int]$script:Ctl.cbKeyLen.SelectedItem
    $hash = [string]$script:Ctl.cbHash.SelectedItem
    $san = @($script:SanEntries)
    $outDir = [System.IO.Path]::GetDirectoryName($outFile)
    if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
        [void][System.IO.Directory]::CreateDirectory($outDir)
    }

    Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.header') 'Navy'
    Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.output' (Split-Path $outFile -Leaf))
    Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.eku' ($ekus -join ', '))
    Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.key' $keySize $hash $script:Ctl.cbMachine.Checked)
    if ($san.Count -gt 0) { Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.san' ($san -join ', ')) }
    Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.backend' $(if ($useCertReq) { 'certreq' } else { '.NET' }))

    try {
        if ($useCertReq) {
            # ---------- certreq: 私钥留在本机密钥容器 ----------
            $inf = Build-InfContent -Subject $fields -EkuOids $ekus -KeyLength $keySize `
                     -HashAlg $hash -Exportable $script:Ctl.cbExport.Checked `
                     -MachineKeySet $script:Ctl.cbMachine.Checked -SanLines $san

            $before = @()
            foreach ($loc in (Get-RequestStoreLocations)) {
                $before += @(Get-ChildItem -Path $loc -ErrorAction SilentlyContinue | ForEach-Object { $_.Thumbprint })
            }

            $r = New-CsrViaCertReq -OutFile $outFile -InfContent $inf -KeepInf:$script:Ctl.cbSaveInf.Checked
            foreach ($line in ($r.Output -split "`r?`n")) {
                if ($line.Trim() -ne '') { Write-Log $script:Ctl.log1 ('  ' + $line.Trim()) 'DarkGreen' }
            }
            if (-not $r.Ok) {
                Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.failed') 'Red'
                [void](Show-Msg (Get-CertText 'log.csr.failed') (Get-CertText 'ui.failed') 'OK' 'Error')
                return
            }

            $size = (Get-Item -LiteralPath $outFile).Length
            Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.done' $outFile $size) 'DarkGreen'
            Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.keynotfile') 'Gray'

            # 记录这次的私钥容器
            try {
                $after = @()
                foreach ($loc in (Get-RequestStoreLocations)) {
                    $after += @(Get-ChildItem -Path $loc -ErrorAction SilentlyContinue)
                }
                $newReq = $after | Where-Object { $before -notcontains $_.Thumbprint } | Select-Object -First 1
                if ($newReq) {
                    $oc = Find-OrphanKeyContainer -Cert $newReq -IncludeMachine
                    if ($oc) {
                        Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.container' $oc.Container $oc.KeyNumber $oc.Machine) 'DarkGreen'
                        Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.containerhint') 'Gray'
                    } else {
                        Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.containernone') 'DarkOrange'
                    }
                }
            } catch {
                Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.containerskip' $_.Exception.Message) 'DarkOrange'
            }
        } else {
            # ---------- .NET: 私钥写成文件 ----------
            $req = New-CsrRequest -Fields $fields -EkuOids $ekus -SanEntries $san `
                      -KeySize $keySize -HashAlgorithm $hash
            try {
                $parms = $req.Rsa.ExportParameters($true)
            } finally {
                try { $req.Rsa.Dispose() } catch { }
            }

            Write-TextFileNoBom $outFile $req.Pem
            $size = (Get-Item -LiteralPath $outFile).Length
            Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.done' $outFile $size) 'DarkGreen'

            $keyFile = [System.IO.Path]::ChangeExtension($outFile, '.key')
            Write-TextFileNoBom $keyFile (ConvertTo-PemPrivateKey $parms 'Pkcs1')
            Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.keyfile' $keyFile) 'DarkGreen'
            Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.keyfilewarn') 'DarkOrange'
            Write-Log $script:Ctl.log1 (Get-CertText 'log.portable.notice') 'Gray'
        }

        Write-Log $script:Ctl.log1 ''
        Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.nextstep1' $outFile) 'Gray'
        Write-Log $script:Ctl.log1 (Get-CertText 'log.csr.nextstep2') 'Gray'

        $body = Get-CertText 'msg.csr.ok.body' $outFile $size
        if ((Show-Msg $body (Get-CertText 'ui.success') 'YesNo' 'Information') -eq 'Yes') {
            if ($outDir -and -not $SelfTest) { Start-Process -FilePath $outDir -ErrorAction SilentlyContinue }
        }
    } catch {
        Write-Log $script:Ctl.log1 (Get-CertText 'err.generic' $_.Exception.Message) 'Red'
        [void](Show-Msg $_.Exception.Message (Get-CertText 'ui.error') 'OK' 'Error')
    }
}

# ============================================================
#  标签页 2 的各种动作
# ============================================================
function Get-SelectedMode {
    for ($i = 0; $i -lt $script:ModeRadios.Count; $i++) {
        if ($script:ModeRadios[$i].Checked) { return $i }
    }
    return 0
}

function Resolve-LocalPrivateKey {
    <# 返回 @{ Params; Source } 或 $null #>
    param([System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert, [string]$KeyPath)

    if ($KeyPath -ne '') {
        $p = Read-PrivateKeyFile $KeyPath
        return [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.file' $KeyPath) }
    }

    if (-not (Test-IsWindowsHost)) { return $null }

    $found = Find-CertWithPrivateKey $Cert
    if ($found) {
        $rsa = Get-RsaFromCert $found
        if ($rsa) {
            try { $p = $rsa.ExportParameters($true) } catch { $p = $null } finally { try { $rsa.Dispose() } catch { } }
            if ($p -and $p.Modulus) {
                return [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.store' $found.Thumbprint) }
            }
        }
    }

    Write-Log $script:Ctl.log2 (Get-CertText 'log.scan.containers') 'Navy'
    $oc = Find-OrphanKeyContainer -Cert $Cert -IncludeMachine
    if ($oc) {
        Write-Log $script:Ctl.log2 (Get-CertText 'log.orphan.found' $oc.Container) 'DarkGreen'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.orphan.meta' $oc.KeyNumber $oc.Machine) 'Gray'
        $p = Get-RsaParamsFromContainer -Container $oc.Container -KeyNumber $oc.KeyNumber -Machine:$oc.Machine -Private
        return [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.container' $oc.Container) }
    }
    return $null
}

function Invoke-CertInfo {
    $script:Ctl.log2.Clear()
    $cf = $script:Ctl.tbCert2.Text.Trim()
    if ($cf -eq '') {
        [void](Show-Msg (Get-CertText 'msg.cert.required') (Get-CertText 'ui.info') 'OK' 'Warning')
        return
    }
    try {
        $ext = [System.IO.Path]::GetExtension($cf).ToLowerInvariant()
        if ($ext -eq '.pfx' -or $ext -eq '.p12') {
            $pfx = ConvertFrom-PfxFile -Path $cf -Password $script:Ctl.tbPwd2.Text
            $first = $true
            foreach ($c in $pfx.All) {
                if (-not $first) { Write-Log $script:Ctl.log2 ('-' * 60) 'DarkGray' }
                foreach ($line in ((Get-CertSummary $c) -split "`n")) { Write-Log $script:Ctl.log2 $line }
                $first = $false
            }
        } else {
            $cert = Get-CertificateFromFile $cf
            foreach ($line in ((Get-CertSummary $cert) -split "`n")) { Write-Log $script:Ctl.log2 $line }
        }
    } catch {
        Write-Log $script:Ctl.log2 (Get-CertText 'log.read.fail' $_.Exception.Message) 'Red'
    }
}

function Invoke-VerifyMatch {
    $script:Ctl.log2.Clear()
    $cf = $script:Ctl.tbCert2.Text.Trim()
    if ($cf -eq '') {
        [void](Show-Msg (Get-CertText 'msg.cert.required') (Get-CertText 'ui.info') 'OK' 'Warning')
        return
    }
    try {
        $cert = Get-CertificateFromFile $cf
        Write-Log $script:Ctl.log2 (Get-CertText 'log.cert' (($cert.Subject -split ',')[0]))
        $resolved = Resolve-LocalPrivateKey -Cert $cert -KeyPath $script:Ctl.tbKey2.Text.Trim()
        if (-not $resolved) {
            Write-Log $script:Ctl.log2 (Get-CertText 'log.no.key') 'Red'
            Write-Log $script:Ctl.log2 (Get-CertText 'log.no.key.hint') 'DarkOrange'
            return
        }
        Write-Log $script:Ctl.log2 $resolved.Source 'Gray'
        if (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params) {
            Write-Log $script:Ctl.log2 (Get-CertText 'log.match.ok') 'DarkGreen'
        } else {
            Write-Log $script:Ctl.log2 (Get-CertText 'log.match.bad') 'Red'
        }
    } catch {
        Write-Log $script:Ctl.log2 (Get-CertText 'log.verify.fail' $_.Exception.Message) 'Red'
    }
}

function Invoke-ExportKey {
    $script:Ctl.log2.Clear()
    $cf = $script:Ctl.tbCert2.Text.Trim()
    if ($cf -eq '') {
        [void](Show-Msg (Get-CertText 'msg.cert.required') (Get-CertText 'ui.info') 'OK' 'Warning')
        return
    }
    try {
        $cert = Get-CertificateFromFile $cf
        Write-Log $script:Ctl.log2 (Get-CertText 'log.cert' (($cert.Subject -split ',')[0]))
        Write-Log $script:Ctl.log2 (Get-CertText 'log.thumb' $cert.Thumbprint)

        $resolved = Resolve-LocalPrivateKey -Cert $cert -KeyPath $script:Ctl.tbKey2.Text.Trim()
        if (-not $resolved) {
            Write-Log $script:Ctl.log2 (Get-CertText 'log.no.key') 'Red'
            Write-Log $script:Ctl.log2 (Get-CertText 'log.no.key.hint') 'DarkOrange'
            return
        }
        if (-not (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params)) {
            Write-Log $script:Ctl.log2 (Get-CertText 'log.match.bad') 'Red'
            return
        }

        $dir = [System.IO.Path]::GetDirectoryName($cf)
        $name = [System.IO.Path]::GetFileNameWithoutExtension($cf) + '-key.pem'
        if ($dir) { $keyPath = [System.IO.Path]::Combine($dir, $name) } else { $keyPath = $name }
        Write-TextFileNoBom $keyPath (ConvertTo-PemPrivateKey $resolved.Params 'Pkcs1')

        Write-Log $script:Ctl.log2 (Get-CertText 'log.exported' $keyPath) 'DarkGreen'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.src' $resolved.Source) 'Gray'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.fmt' 'PKCS#1') 'Gray'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.warn') 'DarkOrange'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.next') 'Gray'
    } catch {
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.fail' $_.Exception.Message) 'Red'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.export.failhint') 'DarkOrange'
    }
}

function Invoke-MergeRun {
    $script:Ctl.log2.Clear()
    $mode = Get-SelectedMode
    $cf = $script:Ctl.tbCert2.Text.Trim()
    $kf = $script:Ctl.tbKey2.Text.Trim()
    $out = $script:Ctl.tbOut2.Text.Trim()
    $pwd = $script:Ctl.tbPwd2.Text

    Write-Log $script:Ctl.log2 (Get-CertText 'log.mode.header' $script:ModeRadios[$mode].Text) 'Navy'

    try {
        # ---------- 模式 0 / 1: 合并 PFX ----------
        if ($mode -eq 0 -or $mode -eq 1) {
            if ($cf -eq '') { throw (Get-CertText 'msg.cert.required') }
            if ($out -eq '') { throw (Get-CertText 'msg.outpath.required') }
            if ($pwd -eq '') { throw (Get-CertText 'msg.pwd.required') }

            $cert = Get-CertificateFromFile $cf
            Write-Log $script:Ctl.log2 (Get-CertText 'log.cert' (($cert.Subject -split ',')[0]))

            $resolved = $null
            if ($mode -eq 1) {
                if ($kf -eq '') { throw (Get-CertText 'msg.key.required') }
                $resolved = Resolve-LocalPrivateKey -Cert $cert -KeyPath $kf
            } else {
                $found = $null
                if (Test-IsWindowsHost) { $found = Find-CertWithPrivateKey $cert }
                if (-not $found -and $script:Ctl.cbInstall.Checked) {
                    Write-Log $script:Ctl.log2 (Get-CertText 'log.install.requested') 'Navy'
                    $acc = Install-CertificateFromFile -CertPath $cf
                    foreach ($line in ($acc.Message -split "`r?`n")) {
                        if ($line.Trim() -ne '') {
                            $color = 'DarkRed'
                            if ($acc.Ok) { $color = 'DarkGreen' }
                            Write-Log $script:Ctl.log2 ('  ' + $line.Trim()) $color
                        }
                    }
                    if (Test-IsWindowsHost) { $found = Find-CertWithPrivateKey $cert }
                    if ($found) { Write-Log $script:Ctl.log2 (Get-CertText 'log.install.paired') 'DarkGreen' }
                } elseif (-not $found) {
                    Write-Log $script:Ctl.log2 (Get-CertText 'log.install.skipped') 'Gray'
                }

                if ($found) {
                    $rsa = Get-RsaFromCert $found
                    try { $p = $rsa.ExportParameters($true) } finally { try { $rsa.Dispose() } catch { } }
                    $resolved = [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.store' $found.Thumbprint) }
                } else {
                    $resolved = Resolve-LocalPrivateKey -Cert $cert -KeyPath ''
                }
            }

            if (-not $resolved) {
                throw ("`r`n" + (Get-CertText 'log.no.key') + "`r`n`r`n" + (Get-CertText 'log.no.key.hint') +
                       "`r`n`r`n" + (Get-CertText 'log.export.next'))
            }
            Write-Log $script:Ctl.log2 $resolved.Source 'Gray'

            if (-not (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params)) {
                throw (Get-CertText 'log.match.bad')
            }
            Write-Log $script:Ctl.log2 (Get-CertText 'log.verify.pass') 'DarkGreen'

            $chain = @()
            if ($script:Ctl.cbChain.Checked) {
                foreach ($c in (Get-AllCertificatesFromFile $cf)) {
                    if ($c.Thumbprint -ne $cert.Thumbprint) { $chain += $c }
                }
                if ($chain.Count -gt 0) { Write-Log $script:Ctl.log2 (Get-CertText 'log.chain.count' $chain.Count) }
            }

            $outDir = [System.IO.Path]::GetDirectoryName($out)
            if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                [void][System.IO.Directory]::CreateDirectory($outDir)
            }

            $size = New-PfxFromCertAndKey -Cert $cert -Params $resolved.Params -PfxPath $out `
                        -Password $pwd -Chain $chain
            Write-Log $script:Ctl.log2 (Get-CertText 'log.out.size' $out $size) 'DarkGreen'

            $back = ConvertFrom-PfxFile -Path $out -Password $pwd
            Write-Log $script:Ctl.log2 (Get-CertText 'log.readback' ([bool]$back.Leaf))
            if ($back.Leaf -and $back.Params) {
                Write-Log $script:Ctl.log2 (Get-CertText 'log.pfx.good') 'DarkGreen'
            } else {
                Write-Log $script:Ctl.log2 (Get-CertText 'log.pfx.bad') 'Red'
            }
            [void](Show-Msg (Get-CertText 'msg.pfx.ok.body' $out $size ([bool]$back.Leaf)) `
                        (Get-CertText 'ui.success') 'OK' 'Information')
            return
        }

        # ---------- 模式 2: 合并 PEM ----------
        if ($mode -eq 2) {
            if ($cf -eq '') { throw (Get-CertText 'msg.cert.required') }
            if ($kf -eq '') { throw (Get-CertText 'msg.key.required') }
            if ($out -eq '') { throw (Get-CertText 'msg.outpath.required') }

            $cert = Get-CertificateFromFile $cf
            $parms = Read-PrivateKeyFile $kf
            if (-not (Test-KeyMatchesCert -Cert $cert -Params $parms)) { throw (Get-CertText 'log.match.bad') }
            Write-Log $script:Ctl.log2 (Get-CertText 'log.verify.pass') 'DarkGreen'

            $chain = @()
            if ($script:Ctl.cbChain.Checked) {
                foreach ($c in (Get-AllCertificatesFromFile $cf)) {
                    if ($c.Thumbprint -ne $cert.Thumbprint) { $chain += $c }
                }
            }

            $text = New-MergedPemText -Cert $cert -Params $parms -Chain $chain -KeyFormat 'Pkcs1'
            $outDir = [System.IO.Path]::GetDirectoryName($out)
            if ($outDir -and -not (Test-Path -LiteralPath $outDir)) {
                [void][System.IO.Directory]::CreateDirectory($outDir)
            }
            Write-TextFileNoBom $out $text
            Write-Log $script:Ctl.log2 (Get-CertText 'log.out.size' $out (Get-Item -LiteralPath $out).Length) 'DarkGreen'
            Write-Log $script:Ctl.log2 (Get-CertText 'log.pem.note') 'Gray'
            [void](Show-Msg (Get-CertText 'msg.pem.ok.body' $out) (Get-CertText 'ui.success') 'OK' 'Information')
            return
        }

        # ---------- 模式 3: 拆解 PFX ----------
        if ($mode -eq 3) {
            if ($cf -eq '') { throw (Get-CertText 'msg.cert.required') }
            if ($pwd -eq '') { throw (Get-CertText 'msg.pfx.pwd.required') }

            $pfx = ConvertFrom-PfxFile -Path $cf -Password $pwd
            Write-Log $script:Ctl.log2 (Get-CertText 'log.split.count' $pfx.Count)
            foreach ($c in $pfx.All) {
                Write-Log $script:Ctl.log2 (Get-CertText 'log.split.item' (($c.Subject -split ',')[0]) $c.HasPrivateKey)
            }
            if (-not $pfx.Leaf) { throw (Get-CertText 'log.split.noLeaf') }
            if (-not $pfx.Params) { throw (Get-CertText 'err.key.not.exportable') }

            if ($out -ne '') {
                $baseDir = [System.IO.Path]::GetDirectoryName($out)
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($out)
            } else {
                $baseDir = [System.IO.Path]::GetDirectoryName($cf)
                $baseName = [System.IO.Path]::GetFileNameWithoutExtension($cf)
            }
            if (-not $baseDir) { $baseDir = (Get-Location).Path }
            if (-not $baseName) { $baseName = 'certificate' }
            if (-not (Test-Path -LiteralPath $baseDir)) {
                [void][System.IO.Directory]::CreateDirectory($baseDir)
            }

            $certPem = [System.IO.Path]::Combine($baseDir, $baseName + '-cert.pem')
            $sb = New-Object System.Text.StringBuilder
            [void]$sb.Append((ConvertTo-PemCertificate $pfx.Leaf))
            foreach ($c in $pfx.Chain) { [void]$sb.Append((ConvertTo-PemCertificate $c)) }
            Write-TextFileNoBom $certPem $sb.ToString()
            Write-Log $script:Ctl.log2 (Get-CertText 'log.split.cert' $certPem) 'DarkGreen'

            $keyPem = [System.IO.Path]::Combine($baseDir, $baseName + '-key.pem')
            Write-TextFileNoBom $keyPem (ConvertTo-PemPrivateKey $pfx.Params 'Pkcs1')
            Write-Log $script:Ctl.log2 (Get-CertText 'log.split.key' $keyPem) 'DarkGreen'

            if ($script:Ctl.cbKeepBoth.Checked) {
                $derPath = [System.IO.Path]::Combine($baseDir, $baseName + '-cert.der')
                [System.IO.File]::WriteAllBytes($derPath, $pfx.Leaf.RawData)
                Write-Log $script:Ctl.log2 (Get-CertText 'log.split.der' $derPath) 'DarkGreen'
            }

            Write-Log $script:Ctl.log2 (Get-CertText 'log.split.done') 'DarkGreen'
            [void](Show-Msg (Get-CertText 'msg.split.ok.body' $certPem $keyPem) (Get-CertText 'ui.success') 'OK' 'Information')
            return
        }
    } catch {
        Write-Log $script:Ctl.log2 (Get-CertText 'err.generic' $_.Exception.Message) 'Red'
        [void](Show-Msg $_.Exception.Message (Get-CertText 'ui.failed') 'OK' 'Error')
    }
}

# ============================================================
#  构建界面
# ============================================================
function New-MainForm {
    $fontName = Get-UiFontName
    $monoName = Get-MonoFontName

    $fontUi = New-Object System.Drawing.Font($fontName, 9)
    $fontSmall = New-Object System.Drawing.Font($fontName, 8)
    $fontMono = New-Object System.Drawing.Font($monoName, 8.5)

    $form = New-Object System.Windows.Forms.Form
    $form.Text = (Get-CertText 'app.title.full')
    $form.Size = New-Object System.Drawing.Size(736, 1014)
    $form.StartPosition = 'CenterScreen'
    $form.FormBorderStyle = 'FixedDialog'
    $form.MaximizeBox = $false
    $form.Font = $fontUi
    $script:Form = $form

    # ---- 菜单 ----
    $menu = New-Object System.Windows.Forms.MenuStrip
    $menu.Font = $fontUi
    $langItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $langItem.Text = (Get-CertText 'app.menu.language')

    $itemZh = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemZh.Text = (Get-CertText 'app.lang.zh')
    $itemZh.Checked = ((Get-CertLanguage) -eq 'zh')
    $itemZh.Add_Click({ $script:PendingLanguage = 'zh'; if ($script:Form) { $script:Form.Close() } })

    $itemEn = New-Object System.Windows.Forms.ToolStripMenuItem
    $itemEn.Text = (Get-CertText 'app.lang.en')
    $itemEn.Checked = ((Get-CertLanguage) -eq 'en')
    $itemEn.Add_Click({ $script:PendingLanguage = 'en'; if ($script:Form) { $script:Form.Close() } })

    [void]$langItem.DropDownItems.Add($itemZh)
    [void]$langItem.DropDownItems.Add($itemEn)
    [void]$menu.Items.Add($langItem)

    $aboutItem = New-Object System.Windows.Forms.ToolStripMenuItem
    $aboutItem.Text = (Get-CertText 'app.about.title')
    $aboutItem.Add_Click({
        $body = Get-CertText 'app.about.body' (Get-CertToolVersion) (Get-PlatformLabel)
        [void](Show-Msg $body (Get-CertText 'app.about.title') 'OK' 'Information')
    })
    [void]$menu.Items.Add($aboutItem)
    $form.Controls.Add($menu)
    $form.MainMenuStrip = $menu

    # ---- 标签页 ----
    $tabs = New-Object System.Windows.Forms.TabControl
    $tabs.Location = New-Object System.Drawing.Point(8, 30)
    $tabs.Size = New-Object System.Drawing.Size(704, 936)
    $form.Controls.Add($tabs)

    # ================= 标签页 1 =================
    $tab1 = New-Object System.Windows.Forms.TabPage
    $tab1.Text = '  ' + (Get-CertText 'app.title.csr') + '  '
    $tabs.TabPages.Add($tab1)

    $y = 12
    $grpSubj = New-Object System.Windows.Forms.GroupBox
    $grpSubj.Text = (Get-CertText 'csr.group.subject')
    $grpSubj.Location = New-Object System.Drawing.Point(10, $y)
    $grpSubj.Size = New-Object System.Drawing.Size(676, 205)
    $tab1.Controls.Add($grpSubj)

    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.cn') 8 26 100 $fontUi))
    $script:Ctl.tbCN = New-TextBox 118 24 310
    $grpSubj.Controls.Add($script:Ctl.tbCN)
    $grpSubj.Controls.Add((New-Hint (Get-CertText 'csr.hint.cn') 438 27 220 $fontSmall))

    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.o') 8 52 100 $fontUi))
    $script:Ctl.tbO = New-TextBox 118 50 310; $grpSubj.Controls.Add($script:Ctl.tbO)
    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.ou') 8 78 100 $fontUi))
    $script:Ctl.tbOU = New-TextBox 118 76 310; $grpSubj.Controls.Add($script:Ctl.tbOU)
    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.l') 8 104 100 $fontUi))
    $script:Ctl.tbL = New-TextBox 118 102 170; $grpSubj.Controls.Add($script:Ctl.tbL)
    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.s') 300 104 60 $fontUi))
    $script:Ctl.tbS = New-TextBox 368 102 190; $grpSubj.Controls.Add($script:Ctl.tbS)
    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.c') 8 130 60 $fontUi))
    $script:Ctl.tbC = New-TextBox 118 128 60; $script:Ctl.tbC.Text = 'CN'; $grpSubj.Controls.Add($script:Ctl.tbC)
    $grpSubj.Controls.Add((New-Label (Get-CertText 'csr.label.e') 190 130 60 $fontUi))
    $script:Ctl.tbE = New-TextBox 258 128 300; $grpSubj.Controls.Add($script:Ctl.tbE)

    $script:Ctl.lblSubjectCheck = New-Object System.Windows.Forms.Label
    $script:Ctl.lblSubjectCheck.Location = New-Object System.Drawing.Point(10, 156)
    $script:Ctl.lblSubjectCheck.Size = New-Object System.Drawing.Size(656, 44)
    $script:Ctl.lblSubjectCheck.Font = $fontSmall
    $script:Ctl.lblSubjectCheck.ForeColor = [System.Drawing.Color]::DimGray
    $grpSubj.Controls.Add($script:Ctl.lblSubjectCheck)

    $y += 212
    $grpEku = New-Object System.Windows.Forms.GroupBox
    $grpEku.Text = (Get-CertText 'csr.group.eku')
    $grpEku.Location = New-Object System.Drawing.Point(10, $y)
    $grpEku.Size = New-Object System.Drawing.Size(676, 195)
    $tab1.Controls.Add($grpEku)

    $script:Ctl.EkuChecks = @{}
    $ex = 12
    $ey = 22
    foreach ($def in $script:EkuDefs) {
        $cb = New-Object System.Windows.Forms.CheckBox
        $cb.Text = (Get-CertText $def.Key) + '  ' + $def.Oid
        $cb.Location = New-Object System.Drawing.Point($ex, $ey)
        $cb.Size = New-Object System.Drawing.Size(325, 22)
        $cb.Checked = $def.Default
        $cb.Tag = $def.Oid
        $grpEku.Controls.Add($cb)
        $script:Ctl.EkuChecks[$def.Oid] = $cb
        $ey += 26
        if ($ey -gt 140) { $ey = 22; $ex = 350 }
    }
    $grpEku.Controls.Add((New-Label (Get-CertText 'csr.label.customoid') 6 165 85 $fontUi))
    $script:Ctl.tbCustomOid = New-TextBox 96 163 260
    $grpEku.Controls.Add($script:Ctl.tbCustomOid)
    $grpEku.Controls.Add((New-Hint (Get-CertText 'csr.hint.customoid') 362 166 300 $fontSmall))

    $y += 202
    $grpKey = New-Object System.Windows.Forms.GroupBox
    $grpKey.Text = (Get-CertText 'csr.group.key')
    $grpKey.Location = New-Object System.Drawing.Point(10, $y)
    $grpKey.Size = New-Object System.Drawing.Size(676, 128)
    $tab1.Controls.Add($grpKey)

    $grpKey.Controls.Add((New-Label (Get-CertText 'csr.label.keylen') 8 25 70 $fontUi))
    $script:Ctl.cbKeyLen = New-Object System.Windows.Forms.ComboBox
    $script:Ctl.cbKeyLen.DropDownStyle = 'DropDownList'
    [void]$script:Ctl.cbKeyLen.Items.AddRange(@('2048', '3072', '4096'))
    $script:Ctl.cbKeyLen.SelectedIndex = 0
    $script:Ctl.cbKeyLen.Location = New-Object System.Drawing.Point(82, 23)
    $script:Ctl.cbKeyLen.Size = New-Object System.Drawing.Size(90, 22)
    $grpKey.Controls.Add($script:Ctl.cbKeyLen)

    $grpKey.Controls.Add((New-Label (Get-CertText 'csr.label.hashalg') 190 25 70 $fontUi))
    $script:Ctl.cbHash = New-Object System.Windows.Forms.ComboBox
    $script:Ctl.cbHash.DropDownStyle = 'DropDownList'
    [void]$script:Ctl.cbHash.Items.AddRange(@('SHA256', 'SHA384', 'SHA512'))
    $script:Ctl.cbHash.SelectedIndex = 0
    $script:Ctl.cbHash.Location = New-Object System.Drawing.Point(264, 23)
    $script:Ctl.cbHash.Size = New-Object System.Drawing.Size(100, 22)
    $grpKey.Controls.Add($script:Ctl.cbHash)

    $script:Ctl.cbExport = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbExport.Text = (Get-CertText 'csr.chk.exportable')
    $script:Ctl.cbExport.Location = New-Object System.Drawing.Point(390, 24)
    $script:Ctl.cbExport.Size = New-Object System.Drawing.Size(140, 22)
    $script:Ctl.cbExport.Checked = $true
    $grpKey.Controls.Add($script:Ctl.cbExport)

    $script:Ctl.cbMachine = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbMachine.Text = (Get-CertText 'csr.chk.machine')
    $script:Ctl.cbMachine.Location = New-Object System.Drawing.Point(82, 52)
    $script:Ctl.cbMachine.Size = New-Object System.Drawing.Size(320, 22)
    $grpKey.Controls.Add($script:Ctl.cbMachine)

    $script:Ctl.cbPortable = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbPortable.Text = (Get-CertText 'csr.chk.portable')
    $script:Ctl.cbPortable.Location = New-Object System.Drawing.Point(82, 76)
    $script:Ctl.cbPortable.Size = New-Object System.Drawing.Size(340, 22)
    $grpKey.Controls.Add($script:Ctl.cbPortable)
    $grpKey.Controls.Add((New-Hint (Get-CertText 'csr.hint.portable') 82 98 580 $fontSmall))

    # certreq 不可用时只能走可移植模式
    if (-not (Test-CertReqAvailable)) {
        $script:Ctl.cbPortable.Checked = $true
        $script:Ctl.cbPortable.Enabled = $false
        $script:Ctl.cbMachine.Enabled = $false
    }
    $script:Ctl.cbPortable.Add_CheckedChanged({
        $p = $script:Ctl.cbPortable.Checked
        $script:Ctl.cbMachine.Enabled = -not $p
        $script:Ctl.cbExport.Enabled = -not $p
    })

    $y += 135
    $grpSan = New-Object System.Windows.Forms.GroupBox
    $grpSan.Text = (Get-CertText 'csr.group.san')
    $grpSan.Location = New-Object System.Drawing.Point(10, $y)
    $grpSan.Size = New-Object System.Drawing.Size(676, 155)
    $tab1.Controls.Add($grpSan)

    $grpSan.Controls.Add((New-Label (Get-CertText 'csr.label.santype') 8 25 50 $fontUi))
    $script:Ctl.cbSanType = New-Object System.Windows.Forms.ComboBox
    $script:Ctl.cbSanType.DropDownStyle = 'DropDownList'
    foreach ($st in $script:SanTypes) { [void]$script:Ctl.cbSanType.Items.Add((Get-CertText $st.LabelKey)) }
    $script:Ctl.cbSanType.SelectedIndex = 0
    $script:Ctl.cbSanType.Location = New-Object System.Drawing.Point(62, 23)
    $script:Ctl.cbSanType.Size = New-Object System.Drawing.Size(110, 22)
    $grpSan.Controls.Add($script:Ctl.cbSanType)

    $grpSan.Controls.Add((New-Label (Get-CertText 'csr.label.sanvalue') 180 25 30 $fontUi))
    $script:Ctl.tbSanVal = New-TextBox 215 23 340
    $grpSan.Controls.Add($script:Ctl.tbSanVal)

    $btnSanAdd = New-Button (Get-CertText 'ui.add') 562 21 70
    $grpSan.Controls.Add($btnSanAdd)

    $script:Ctl.lbSan = New-Object System.Windows.Forms.ListBox
    $script:Ctl.lbSan.Location = New-Object System.Drawing.Point(62, 55)
    $script:Ctl.lbSan.Size = New-Object System.Drawing.Size(493, 88)
    $grpSan.Controls.Add($script:Ctl.lbSan)

    $btnSanDel = New-Button (Get-CertText 'ui.remove') 562 55 70
    $grpSan.Controls.Add($btnSanDel)

    $y += 162
    $grpOut = New-Object System.Windows.Forms.GroupBox
    $grpOut.Text = (Get-CertText 'csr.group.out')
    $grpOut.Location = New-Object System.Drawing.Point(10, $y)
    $grpOut.Size = New-Object System.Drawing.Size(676, 78)
    $tab1.Controls.Add($grpOut)

    $grpOut.Controls.Add((New-Label (Get-CertText 'csr.label.saveas') 8 25 55 $fontUi))
    $script:Ctl.tbOut = New-TextBox 68 23 490
    $defaultOut = Join-Path (Get-DefaultOutputDirectory) 'request.req'
    $script:Ctl.tbOut.Text = $defaultOut
    $grpOut.Controls.Add($script:Ctl.tbOut)

    $btnBrowse = New-Button (Get-CertText 'ui.browse') 566 21 100
    $grpOut.Controls.Add($btnBrowse)

    $script:Ctl.cbSaveInf = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbSaveInf.Text = (Get-CertText 'csr.chk.saveinf')
    $script:Ctl.cbSaveInf.Location = New-Object System.Drawing.Point(68, 50)
    $script:Ctl.cbSaveInf.Size = New-Object System.Drawing.Size(240, 22)
    $script:Ctl.cbSaveInf.Checked = $true
    $grpOut.Controls.Add($script:Ctl.cbSaveInf)

    $y += 85
    $btnGen = New-Object System.Windows.Forms.Button
    $btnGen.Text = (Get-CertText 'csr.btn.generate')
    $btnGen.Location = New-Object System.Drawing.Point(10, $y)
    $btnGen.Size = New-Object System.Drawing.Size(140, 32)
    $btnGen.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnGen.ForeColor = [System.Drawing.Color]::White
    $btnGen.FlatStyle = 'Flat'
    $tab1.Controls.Add($btnGen)

    $btnPrev = New-Object System.Windows.Forms.Button
    $btnPrev.Text = (Get-CertText 'csr.btn.preview')
    $btnPrev.Location = New-Object System.Drawing.Point(158, $y)
    $btnPrev.Size = New-Object System.Drawing.Size(110, 32)
    $tab1.Controls.Add($btnPrev)

    $btnClear1 = New-Object System.Windows.Forms.Button
    $btnClear1.Text = (Get-CertText 'ui.clear')
    $btnClear1.Location = New-Object System.Drawing.Point(276, $y)
    $btnClear1.Size = New-Object System.Drawing.Size(80, 32)
    $tab1.Controls.Add($btnClear1)

    $btnOpen1 = New-Object System.Windows.Forms.Button
    $btnOpen1.Text = (Get-CertText 'ui.openfolder')
    $btnOpen1.Location = New-Object System.Drawing.Point(364, $y)
    $btnOpen1.Size = New-Object System.Drawing.Size(110, 32)
    $tab1.Controls.Add($btnOpen1)

    $y += 40
    $grpLog1 = New-Object System.Windows.Forms.GroupBox
    $grpLog1.Text = (Get-CertText 'ui.log')
    $grpLog1.Location = New-Object System.Drawing.Point(10, $y)
    $grpLog1.Size = New-Object System.Drawing.Size(676, 104)
    $tab1.Controls.Add($grpLog1)

    $script:Ctl.log1 = New-Object System.Windows.Forms.RichTextBox
    $script:Ctl.log1.Location = New-Object System.Drawing.Point(8, 18)
    $script:Ctl.log1.Size = New-Object System.Drawing.Size(660, 80)
    $script:Ctl.log1.ReadOnly = $true
    $script:Ctl.log1.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $script:Ctl.log1.Font = $fontMono
    $script:Ctl.log1.ScrollBars = 'Vertical'
    $grpLog1.Controls.Add($script:Ctl.log1)

    # ================= 标签页 2 =================
    $tab2 = New-Object System.Windows.Forms.TabPage
    $tab2.Text = '  ' + (Get-CertText 'app.title.merge') + '  '
    $tabs.TabPages.Add($tab2)

    $y2 = 12
    $grpMode = New-Object System.Windows.Forms.GroupBox
    $grpMode.Text = (Get-CertText 'merge.group.mode')
    $grpMode.Location = New-Object System.Drawing.Point(10, $y2)
    $grpMode.Size = New-Object System.Drawing.Size(676, 196)
    $tab2.Controls.Add($grpMode)

    $script:ModeRadios = @()
    $my = 20
    for ($mi = 0; $mi -lt 4; $mi++) {
        $rb = New-Object System.Windows.Forms.RadioButton
        $rb.Text = (Get-CertText ('merge.mode.' + $mi))
        $rb.Location = New-Object System.Drawing.Point(12, $my)
        $rb.Size = New-Object System.Drawing.Size(470, 20)
        $grpMode.Controls.Add($rb)
        $script:ModeRadios += $rb

        $lb = New-Hint (Get-CertText ('merge.mode.' + $mi + '.desc')) 32 ($my + 20) 620 $fontSmall
        $lb.Size = New-Object System.Drawing.Size(620, 17)
        $grpMode.Controls.Add($lb)

        $my += 43
    }
    $script:ModeRadios[0].Checked = $true

    $y2 += 204
    $grpFiles = New-Object System.Windows.Forms.GroupBox
    $grpFiles.Text = (Get-CertText 'merge.group.files')
    $grpFiles.Location = New-Object System.Drawing.Point(10, $y2)
    $grpFiles.Size = New-Object System.Drawing.Size(676, 145)
    $tab2.Controls.Add($grpFiles)

    $grpFiles.Controls.Add((New-Label (Get-CertText 'merge.label.certfile') 8 26 80 $fontUi))
    $script:Ctl.tbCert2 = New-TextBox 90 24 470
    $grpFiles.Controls.Add($script:Ctl.tbCert2)
    $btnCert2 = New-Button (Get-CertText 'ui.browse') 570 22 95
    $grpFiles.Controls.Add($btnCert2)

    $grpFiles.Controls.Add((New-Label (Get-CertText 'merge.label.keyfile') 8 56 80 $fontUi))
    $script:Ctl.tbKey2 = New-TextBox 90 54 470
    $grpFiles.Controls.Add($script:Ctl.tbKey2)
    $btnKey2 = New-Button (Get-CertText 'ui.browse') 570 52 95
    $grpFiles.Controls.Add($btnKey2)

    $grpFiles.Controls.Add((New-Label (Get-CertText 'merge.label.pfxpwd') 8 86 80 $fontUi))
    $script:Ctl.tbPwd2 = New-TextBox 90 84 210
    $script:Ctl.tbPwd2.UseSystemPasswordChar = $true
    $grpFiles.Controls.Add($script:Ctl.tbPwd2)
    $script:Ctl.cbShowPwd = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbShowPwd.Text = (Get-CertText 'ui.show')
    $script:Ctl.cbShowPwd.Location = New-Object System.Drawing.Point(310, 86)
    $script:Ctl.cbShowPwd.Size = New-Object System.Drawing.Size(80, 22)
    $grpFiles.Controls.Add($script:Ctl.cbShowPwd)
    $grpFiles.Controls.Add((New-Hint (Get-CertText 'merge.hint.pfxpwd') 396 88 280 $fontSmall))

    $grpFiles.Controls.Add((New-Label (Get-CertText 'merge.label.outfile') 8 114 80 $fontUi))
    $script:Ctl.tbOut2 = New-TextBox 90 112 470
    $grpFiles.Controls.Add($script:Ctl.tbOut2)
    $btnOut2 = New-Button (Get-CertText 'ui.browse') 570 110 95
    $grpFiles.Controls.Add($btnOut2)

    $y2 += 152
    $grpOpt2 = New-Object System.Windows.Forms.GroupBox
    $grpOpt2.Text = (Get-CertText 'merge.group.options')
    $grpOpt2.Location = New-Object System.Drawing.Point(10, $y2)
    $grpOpt2.Size = New-Object System.Drawing.Size(676, 86)
    $tab2.Controls.Add($grpOpt2)

    $script:Ctl.cbChain = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbChain.Text = (Get-CertText 'merge.chk.chain')
    $script:Ctl.cbChain.Location = New-Object System.Drawing.Point(12, 22)
    $script:Ctl.cbChain.Size = New-Object System.Drawing.Size(380, 22)
    $script:Ctl.cbChain.Checked = $true
    $grpOpt2.Controls.Add($script:Ctl.cbChain)

    $script:Ctl.cbKeepBoth = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbKeepBoth.Text = (Get-CertText 'merge.chk.der')
    $script:Ctl.cbKeepBoth.Location = New-Object System.Drawing.Point(410, 22)
    $script:Ctl.cbKeepBoth.Size = New-Object System.Drawing.Size(250, 22)
    $grpOpt2.Controls.Add($script:Ctl.cbKeepBoth)

    $script:Ctl.cbInstall = New-Object System.Windows.Forms.CheckBox
    $script:Ctl.cbInstall.Text = (Get-CertText 'merge.chk.install')
    $script:Ctl.cbInstall.Location = New-Object System.Drawing.Point(12, 50)
    $script:Ctl.cbInstall.Size = New-Object System.Drawing.Size(470, 22)
    $script:Ctl.cbInstall.Checked = $false
    $grpOpt2.Controls.Add($script:Ctl.cbInstall)
    $grpOpt2.Controls.Add((New-Hint (Get-CertText 'merge.hint.install') 486 52 180 $fontSmall))

    $y2 += 94
    $btnRun2 = New-Object System.Windows.Forms.Button
    $btnRun2.Text = (Get-CertText 'ui.run')
    $btnRun2.Location = New-Object System.Drawing.Point(10, $y2)
    $btnRun2.Size = New-Object System.Drawing.Size(120, 34)
    $btnRun2.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $btnRun2.ForeColor = [System.Drawing.Color]::White
    $btnRun2.FlatStyle = 'Flat'
    $tab2.Controls.Add($btnRun2)

    $btnInfo2 = New-Object System.Windows.Forms.Button
    $btnInfo2.Text = (Get-CertText 'merge.btn.certinfo')
    $btnInfo2.Location = New-Object System.Drawing.Point(138, $y2)
    $btnInfo2.Size = New-Object System.Drawing.Size(120, 34)
    $tab2.Controls.Add($btnInfo2)

    $btnMatch2 = New-Object System.Windows.Forms.Button
    $btnMatch2.Text = (Get-CertText 'merge.btn.verify')
    $btnMatch2.Location = New-Object System.Drawing.Point(266, $y2)
    $btnMatch2.Size = New-Object System.Drawing.Size(120, 34)
    $tab2.Controls.Add($btnMatch2)

    $btnOpen2 = New-Object System.Windows.Forms.Button
    $btnOpen2.Text = (Get-CertText 'ui.openfolder')
    $btnOpen2.Location = New-Object System.Drawing.Point(394, $y2)
    $btnOpen2.Size = New-Object System.Drawing.Size(110, 34)
    $tab2.Controls.Add($btnOpen2)

    $btnExportKey = New-Object System.Windows.Forms.Button
    $btnExportKey.Text = (Get-CertText 'merge.btn.exportkey')
    $btnExportKey.Location = New-Object System.Drawing.Point(512, $y2)
    $btnExportKey.Size = New-Object System.Drawing.Size(150, 34)
    $tab2.Controls.Add($btnExportKey)

    $y2 += 42
    $grpLog2 = New-Object System.Windows.Forms.GroupBox
    $grpLog2.Text = (Get-CertText 'merge.group.log')
    $grpLog2.Location = New-Object System.Drawing.Point(10, $y2)
    $grpLog2.Size = New-Object System.Drawing.Size(676, 380)
    $tab2.Controls.Add($grpLog2)

    $script:Ctl.log2 = New-Object System.Windows.Forms.RichTextBox
    $script:Ctl.log2.Location = New-Object System.Drawing.Point(8, 18)
    $script:Ctl.log2.Size = New-Object System.Drawing.Size(660, 354)
    $script:Ctl.log2.ReadOnly = $true
    $script:Ctl.log2.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
    $script:Ctl.log2.Font = $fontMono
    $script:Ctl.log2.ScrollBars = 'Vertical'
    $grpLog2.Controls.Add($script:Ctl.log2)

    # ================= 事件 =================
    $btnSanAdd.Add_Click({
        $v = $script:Ctl.tbSanVal.Text.Trim()
        if ($v -eq '') { return }
        $idx = $script:Ctl.cbSanType.SelectedIndex
        $prefix = 'dns'
        if ($idx -ge 0 -and $idx -lt $script:SanTypes.Count) { $prefix = $script:SanTypes[$idx].Prefix }
        $entry = $prefix + '=' + $v
        [void]$script:SanEntries.Add($entry)
        [void]$script:Ctl.lbSan.Items.Add($entry)
        $script:Ctl.tbSanVal.Clear()
    })

    $btnSanDel.Add_Click({
        $i = $script:Ctl.lbSan.SelectedIndex
        if ($i -ge 0) {
            $script:SanEntries.RemoveAt($i)
            $script:Ctl.lbSan.Items.RemoveAt($i)
        }
    })

    $btnBrowse.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'CSR (*.req)|*.req|All files (*.*)|*.*'
        $cur = [System.IO.Path]::GetFileName($script:Ctl.tbOut.Text)
        if ($cur) { $sfd.FileName = $cur }
        $d0 = [System.IO.Path]::GetDirectoryName($script:Ctl.tbOut.Text)
        if ($d0 -and (Test-Path -LiteralPath $d0)) { $sfd.InitialDirectory = $d0 }
        if ($sfd.ShowDialog() -eq 'OK') {
            $script:OutTouched = $true
            $script:Ctl.tbOut.Text = $sfd.FileName
        }
    })

    $btnOpen1.Add_Click({
        $d = [System.IO.Path]::GetDirectoryName($script:Ctl.tbOut.Text)
        if ($d -and (Test-Path -LiteralPath $d)) { Start-Process -FilePath $d -ErrorAction SilentlyContinue }
    })

    $btnClear1.Add_Click({
        foreach ($c in @($script:Ctl.tbCN, $script:Ctl.tbO, $script:Ctl.tbOU, $script:Ctl.tbL,
                          $script:Ctl.tbS, $script:Ctl.tbE, $script:Ctl.tbCustomOid, $script:Ctl.tbSanVal)) {
            $c.Clear()
        }
        $script:Ctl.tbC.Text = 'CN'
        $script:Ctl.lbSan.Items.Clear()
        $script:SanEntries.Clear()
        foreach ($oid in $script:Ctl.EkuChecks.Keys) {
            $script:Ctl.EkuChecks[$oid].Checked = ($oid -eq '1.3.6.1.5.5.7.3.2')
        }
        $script:Ctl.cbKeyLen.SelectedIndex = 0
        $script:Ctl.cbHash.SelectedIndex = 0
        $script:Ctl.cbExport.Checked = $true
        $script:Ctl.cbMachine.Checked = $false
        $script:OutTouched = $false
        $script:Ctl.tbCN.Text = ''
        Write-Log $script:Ctl.log1 (Get-CertText 'log.form.cleared') 'Gray'
    })

    $btnPrev.Add_Click({
        try {
            $fields = Get-SubjectFields
            $ekus = @(Get-SelectedEkuOids)
            $san = @($script:SanEntries)
            $text = ''
            if ((-not (Test-PortableMode)) -and (Test-CertReqAvailable)) {
                $text = Build-InfContent -Subject $fields -EkuOids $ekus `
                          -KeyLength ([int]$script:Ctl.cbKeyLen.SelectedItem) `
                          -HashAlg ([string]$script:Ctl.cbHash.SelectedItem) `
                          -Exportable $script:Ctl.cbExport.Checked `
                          -MachineKeySet $script:Ctl.cbMachine.Checked -SanLines $san
            } else {
                $sb = New-Object System.Text.StringBuilder
                [void]$sb.AppendLine((Get-CertText 'csr.group.subject') + ': ' + (Get-DistinguishedNameText $fields))
                [void]$sb.AppendLine((Get-CertText 'csr.group.eku') + ': ' + ($ekus -join ', '))
                if ($san.Count -gt 0) { [void]$sb.AppendLine((Get-CertText 'csr.label.sanvalue') + ': ' + ($san -join ', ')) }
                $keyLine = Get-CertText 'log.csr.key' ([int]$script:Ctl.cbKeyLen.SelectedItem) ([string]$script:Ctl.cbHash.SelectedItem) $false
                [void]$sb.AppendLine($keyLine)
                [void]$sb.AppendLine((Get-CertText 'log.csr.backend' '.NET'))
                $text = $sb.ToString()
            }
            $pf = New-Object System.Windows.Forms.Form
            $pf.Text = (Get-CertText 'csr.preview.title')
            $pf.Size = New-Object System.Drawing.Size(820, 520)
            $pf.StartPosition = 'CenterParent'
            $pf.Font = $fontUi
            $rt = New-Object System.Windows.Forms.RichTextBox
            $rt.Dock = 'Fill'
            $rt.Font = New-Object System.Drawing.Font($monoName, 10)
            $rt.Text = $text
            $rt.ReadOnly = $true
            $pf.Controls.Add($rt)
            [void]$pf.ShowDialog($form)
            $pf.Dispose()
        } catch {
            [void](Show-Msg $_.Exception.Message (Get-CertText 'msg.preview.failed') 'OK' 'Error')
        }
    })

    $btnGen.Add_Click({ Invoke-GenerateCsr })

    $script:Ctl.cbShowPwd.Add_CheckedChanged({
        $script:Ctl.tbPwd2.UseSystemPasswordChar = -not $script:Ctl.cbShowPwd.Checked
    })

    $btnCert2.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Certificate (*.cer;*.crt;*.pem;*.der)|*.cer;*.crt;*.pem;*.der|PFX (*.pfx;*.p12)|*.pfx;*.p12|All files (*.*)|*.*'
        if ($ofd.ShowDialog() -eq 'OK') { $script:Ctl.tbCert2.Text = $ofd.FileName }
    })

    $btnKey2.Add_Click({
        $ofd = New-Object System.Windows.Forms.OpenFileDialog
        $ofd.Filter = 'Private key (*.key;*.pem;*.txt)|*.key;*.pem;*.txt|All files (*.*)|*.*'
        if ($ofd.ShowDialog() -eq 'OK') { $script:Ctl.tbKey2.Text = $ofd.FileName }
    })

    $btnOut2.Add_Click({
        $sfd = New-Object System.Windows.Forms.SaveFileDialog
        $sfd.Filter = 'PFX (*.pfx)|*.pfx|PEM (*.pem)|*.pem|All files (*.*)|*.*'
        $sfd.FileName = 'output.pfx'
        if ($sfd.ShowDialog() -eq 'OK') { $script:Ctl.tbOut2.Text = $sfd.FileName }
    })

    $btnOpen2.Add_Click({
        $d = [System.IO.Path]::GetDirectoryName($script:Ctl.tbOut2.Text)
        if (-not $d) { $d = [System.IO.Path]::GetDirectoryName($script:Ctl.tbCert2.Text) }
        if ($d -and (Test-Path -LiteralPath $d)) { Start-Process -FilePath $d -ErrorAction SilentlyContinue }
    })

    $btnInfo2.Add_Click({ Invoke-CertInfo })
    $btnMatch2.Add_Click({ Invoke-VerifyMatch })
    $btnExportKey.Add_Click({ Invoke-ExportKey })
    $btnRun2.Add_Click({ Invoke-MergeRun })

    $form.Add_Shown({
        Write-Log $script:Ctl.log1 (Get-CertText 'log.started') 'Navy'
        Write-Log $script:Ctl.log1 ((Get-CertText 'app.version') + ' ' + (Get-CertToolVersion) + '   ' + (Get-CertText 'log.host' $env:COMPUTERNAME $env:USERNAME (Get-PlatformLabel))) 'Gray'
        Write-Log $script:Ctl.log1 (Get-CertText 'log.hint.csr') 'Gray'
        Write-Log $script:Ctl.log1 (Get-CertText 'log.hint.store') 'Gray'
        Write-Log $script:Ctl.log1 ''

        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.title') 'Navy'
        Write-Log $script:Ctl.log2 ''
        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.0') 'DarkGreen'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.1') 'DarkGreen'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.2') 'DarkGreen'
        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.3') 'DarkGreen'
        Write-Log $script:Ctl.log2 ''
        Write-Log $script:Ctl.log2 (Get-CertText 'log.merge.help.pem') 'Gray'

        Update-SubjectCheck

        if ($SelfTest) {
            $script:SelfTestTimer = New-Object System.Windows.Forms.Timer
            $script:SelfTestTimer.Interval = 400
            $script:SelfTestTimer.Add_Tick({
                $script:SelfTestTimer.Stop()
                $script:ExitCode = Invoke-GuiSelfTest
                if ($script:Form) { $script:Form.Close() }
            })
            $script:SelfTestTimer.Start()
        }
    })

    return $form
}

# ============================================================
#  GUI 自测 (-SelfTest)
#  真正驱动界面上的代码路径: 生成 CSR -> 合并 PFX -> 拆解 -> 校验
#  返回失败个数
# ============================================================
function Invoke-GuiSelfTest {
    $fail = 0
    $lines = @()

    function Add-Result {
        param([bool]$Ok, [string]$Text)
        if ($Ok) { $script:GstLines += ('PASS  ' + $Text) }
        else { $script:GstLines += ('FAIL  ' + $Text); $script:GstFail++ }
    }

    $script:GstLines = @()
    $script:GstFail = 0
    $tmp = Join-Path ([System.IO.Path]::GetTempPath()) ('certtool_gui_' + [guid]::NewGuid().ToString('N'))
    [void][System.IO.Directory]::CreateDirectory($tmp)

    try {
        Add-Result (([string](Get-CertToolVersion)).Length -gt 0) 'toolkit version present'

        $tabCount = 0
        foreach ($c in $script:Form.Controls) {
            if ($c -is [System.Windows.Forms.TabControl]) { $tabCount = $c.TabPages.Count }
        }
        Add-Result ($tabCount -eq 2) ('ui has two tabs (got ' + $tabCount + ')')

        # ---- 1. 主题校验能拦住逗号 ----
        $bad = Test-SubjectFields @{ CN = 'a,b'; O = ''; OU = ''; L = ''; S = ''; C = 'CN'; E = '' }
        Add-Result ($bad.Errors.Count -gt 0) 'subject validation rejects a comma'

        # ---- 2. 可移植模式生成 CSR ----
        $script:Ctl.tbCN.Text = 'gui-selftest.example.com'
        $script:Ctl.tbO.Text = 'Self Test'
        $script:Ctl.tbC.Text = 'CN'
        $script:Ctl.cbPortable.Checked = $true
        $sanRaw = 'dns=gui-selftest.example.com'
        [void]$script:SanEntries.Add($sanRaw)
        [void]$script:Ctl.lbSan.Items.Add($sanRaw)
        $csrPath = Join-Path $tmp 'gui.req'
        $script:Ctl.tbOut.Text = $csrPath
        Invoke-GenerateCsr

        Add-Result (Test-Path -LiteralPath $csrPath) 'CSR file written'
        $keyPath = [System.IO.Path]::ChangeExtension($csrPath, '.key')
        Add-Result (Test-Path -LiteralPath $keyPath) 'private key file written'
        $blocks = @(Get-PemBlocks (Get-FileText $csrPath))
        Add-Result ($blocks.Count -eq 1) 'CSR is a single PEM block'

        # ---- 3. 用这把私钥造一张自签证书 (模拟 CA 签发) ----
        $parms = Read-PrivateKeyFile $keyPath
        $full = ($null -ne $parms.Modulus -and $null -ne $parms.D -and
                 $null -ne $parms.P -and $null -ne $parms.Q -and $null -ne $parms.DP)
        Add-Result $full 'private key file carries a complete CRT key'
        if (-not $full) { throw 'key file is incomplete: modulus/D/P/Q/DP must all be present' }

        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $rsa.ImportParameters($parms)
            $dnDer = New-DistinguishedNameDer @{ CN = 'gui-selftest.example.com'; O = 'Self Test'; C = 'CN' }
            $dn = [System.Security.Cryptography.X509Certificates.X500DistinguishedName]::new([byte[]]$dnDer)
            $creq = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                $dn, $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
            $signed = $creq.CreateSelfSigned([datetime]::UtcNow.AddDays(-1), [datetime]::UtcNow.AddDays(30))
        } catch {
            $sizes = 'mod=' + $parms.Modulus.Length + ' d=' + $parms.D.Length +
                     ' p=' + $parms.P.Length + ' q=' + $parms.Q.Length
            throw ('could not rebuild RSA from the key file: ' + $_.Exception.Message + '  [' + $sizes + ']')
        } finally { try { $rsa.Dispose() } catch { } }
        $certPath = Join-Path $tmp 'gui.cer'
        Write-TextFileNoBom $certPath (ConvertTo-PemCertificate $signed)
        Add-Result (Test-Path -LiteralPath $certPath) 'test certificate written'

        # ---- 4. 合并 PFX (模式 2 = 证书 + 私钥文件) ----
        $pfxPath = Join-Path $tmp 'gui.pfx'
        $script:ModeRadios[1].Checked = $true
        $script:Ctl.tbCert2.Text = $certPath
        $script:Ctl.tbKey2.Text = $keyPath
        $script:Ctl.tbOut2.Text = $pfxPath
        $script:Ctl.tbPwd2.Text = 'selftest123'
        Invoke-MergeRun
        Add-Result (Test-Path -LiteralPath $pfxPath) 'PFX written by the merge tab'

        $back = ConvertFrom-PfxFile -Path $pfxPath -Password 'selftest123'
        Add-Result ($null -ne $back.Leaf) 'PFX re-reads with a keyed certificate'
        if ($back.Params) {
            Add-Result (Test-BytesEqual $back.Params.Modulus $parms.Modulus) 'PFX key matches the original key'
        } else {
            Add-Result $false 'PFX private key is re-exportable'
        }

        # ---- 5. 拆解 PFX (模式 4) ----
        $prefix = Join-Path $tmp 'split'
        $script:ModeRadios[3].Checked = $true
        $script:Ctl.tbCert2.Text = $pfxPath
        $script:Ctl.tbOut2.Text = $prefix
        Invoke-MergeRun
        Add-Result (Test-Path -LiteralPath ($prefix + '-cert.pem')) 'split produced a certificate'
        Add-Result (Test-Path -LiteralPath ($prefix + '-key.pem')) 'split produced a key'

        # ---- 6. 验证 / 详情 / 导出 ----
        $script:ModeRadios[0].Checked = $true
        $script:Ctl.tbCert2.Text = $certPath
        $script:Ctl.tbKey2.Text = $keyPath
        Invoke-VerifyMatch
        Add-Result ($script:Ctl.log2.Text -match '(matches|匹配)') 'verify key match reports success'

        Invoke-CertInfo
        Add-Result ($script:Ctl.log2.Text -match 'gui-selftest\.example\.com') 'certificate details render'

        Invoke-ExportKey
        $exported = Join-Path $tmp 'gui-key.pem'
        Add-Result (Test-Path -LiteralPath $exported) 'export private key wrote a file'

        # ---- 7. 双语都能取到文案 ----
        $zhOk = $false
        $enOk = $false
        Set-CertLanguage 'zh' | Out-Null
        $zhOk = ((Get-CertText 'app.title') -ne 'app.title')
        Set-CertLanguage 'en' | Out-Null
        $enOk = ((Get-CertText 'app.title') -ne 'app.title')
        Add-Result ($zhOk -and $enOk) 'both languages resolve'
    } catch {
        Add-Result $false ('unexpected error: ' + $_.Exception.Message)
    } finally {
        Remove-Item -LiteralPath $tmp -Recurse -Force -ErrorAction SilentlyContinue
    }

    foreach ($l in $script:GstLines) {
        if ($l.StartsWith('PASS')) { Write-Host $l -ForegroundColor Green } else { Write-Host $l -ForegroundColor Red }
    }
    Write-Host ('RESULT: {0} passed, {1} failed' -f ($script:GstLines.Count - $script:GstFail), $script:GstFail) `
        -ForegroundColor $(if ($script:GstFail -eq 0) { 'Green' } else { 'Red' })
    return $script:GstFail
}

# ============================================================
#  启动
# ============================================================
$script:ExitCode = 0
while ($true) {
    if ($script:PendingLanguage) {
        $lang = $script:PendingLanguage
        $script:PendingLanguage = $null
        Set-CertLanguage $lang | Out-Null
    }

    $script:Form = New-MainForm
    [void]$script:Form.ShowDialog()
    $script:Form.Dispose()
    $script:Form = $null

    if (-not $script:PendingLanguage) { break }
    if ($SelfTest) { break }
}

if ($SelfTest) { exit 0 }
exit $script:ExitCode

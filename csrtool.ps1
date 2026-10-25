#Requires -Version 5.1
<#
    证书工具箱 命令行版  csrtool.ps1
    ============================================================
    跨平台: Windows / Linux / macOS,  Windows PowerShell 5.1 与 PowerShell 7+

    命令:
        new-csr      生成 CSR 与私钥
        merge-pfx    证书 + 私钥 -> PFX
        merge-pem    证书 + 私钥 -> 合并 PEM
        split-pfx    PFX -> 证书 + 私钥
        info         显示证书详情
        verify       验证私钥与证书是否匹配
        export-key   导出证书对应的私钥
        scan-keys    扫描本机密钥容器 (仅 Windows)
        serve        交互式菜单 (无参数时的默认行为)

    示例:
        ./csrtool.ps1 new-csr -CN nas.example.com -San dns=nas.example.com -KeyOut ./nas.key
        ./csrtool.ps1 merge-pfx -Cert issued.cer -Key nas.key -Out nas.pfx -Password secret
        ./csrtool.ps1 split-pfx my.pfx -Password secret -Out ./out

    ★ 参数是手工解析的: 这里故意不写 param() / [CmdletBinding()],
      否则 -CN、-San 这类"动态"选项会被 PowerShell 的参数绑定器直接拒掉。
#>

$ErrorActionPreference = 'Stop'

$ScriptRoot = $PSScriptRoot
if (-not $ScriptRoot) { $ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path }
$helperPath = Join-Path $ScriptRoot 'CertHelper.ps1'
if (-not (Test-Path -LiteralPath $helperPath)) {
    Write-Host 'Missing CertHelper.ps1 next to this script.' -ForegroundColor Red
    exit 2
}
. $helperPath

# ============================================================
#  参数解析
# ============================================================
$script:Opt = @{}
$script:Pos = @()
$script:Cmd = ''
$script:SwitchNames = @('force', 'help', 'h', 'machine', 'der', 'nochain', 'quiet', 'version', 'v', 'verbose')

function Initialize-Options {
    param([object[]]$Arguments)

    $script:Opt = @{}
    $script:Pos = @()
    $script:Cmd = ''

    $i = 0
    while ($i -lt $Arguments.Count) {
        $a = [string]$Arguments[$i]

        if ($a -match '^--?([A-Za-z][A-Za-z0-9_-]*)$') {
            $name = $Matches[1].ToLowerInvariant()
            if ($script:SwitchNames -contains $name) {
                $script:Opt[$name] = $true
                $i++
                continue
            }
            if (($i + 1) -ge $Arguments.Count) { throw (Get-CertText 'cli.param.value' $a) }
            $script:Opt[$name] = [string]$Arguments[$i + 1]
            $i += 2
            continue
        }

        if ($script:Cmd -eq '') { $script:Cmd = $a.ToLowerInvariant() }
        else { $script:Pos += $a }
        $i++
    }
}

function Get-Opt {
    param([string[]]$Names, [string]$Default = '')
    foreach ($n in $Names) {
        $k = $n.ToLowerInvariant()
        if ($script:Opt.ContainsKey($k)) { return [string]$script:Opt[$k] }
    }
    return $Default
}

function Test-Opt {
    param([string[]]$Names)
    foreach ($n in $Names) {
        if ($script:Opt.ContainsKey($n.ToLowerInvariant())) { return $true }
    }
    return $false
}

function Get-RequiredOpt {
    param([string[]]$Names, [string]$Display)
    $v = Get-Opt $Names
    if ($v -eq '') { throw (Get-CertText 'cli.param.missing' $Display) }
    return $v
}

# ============================================================
#  输出辅助
# ============================================================
function Write-Err  { param([string]$Text) Write-Host ('[x] ' + $Text) -ForegroundColor Red }
function Write-Ok   { param([string]$Text) Write-Host ('[+] ' + $Text) -ForegroundColor Green }
function Write-Line { param([string]$Text, [string]$Color = 'Gray') Write-Host $Text -ForegroundColor $Color }

function Exit-WithError {
    param([string]$Text)
    Write-Err $Text
    exit 1
}

function Resolve-TargetPath {
    <# 展开相对路径与 ~; 已存在且没有 -Force 时拒绝覆盖 #>
    param([string]$Path, [switch]$Force)

    if ($Path -eq '') { return '' }
    $p = $Path
    if ($p -eq '~') { $p = Get-DefaultOutputDirectory }
    elseif ($p -like '~/*' -or $p -like '~\*') {
        $p = Join-Path (Get-DefaultOutputDirectory) $p.Substring(2)
    }
    if (-not [System.IO.Path]::IsPathRooted($p)) { $p = Join-Path (Get-Location).Path $p }

    $dir = [System.IO.Path]::GetDirectoryName($p)
    if ($dir -and -not [System.IO.Directory]::Exists($dir)) {
        [void][System.IO.Directory]::CreateDirectory($dir)
    }
    if ((Test-Path -LiteralPath $p) -and -not $Force) {
        throw (Get-CertText 'cli.overwrite.blocked' $p)
    }
    return $p
}

function Read-SecretText {
    param([string]$Prompt)
    if ($env:CERDTOOL_PASSWORD) { return $env:CERDTOOL_PASSWORD }
    try {
        $sec = Read-Host -Prompt $Prompt -AsSecureString
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($sec)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($bstr) }
        finally { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
    } catch {
        return (Read-Host -Prompt $Prompt)
    }
}

function Get-PasswordOpt {
    param([switch]$Required, [string]$Prompt)
    foreach ($k in @('password', 'pwd')) {
        if ($script:Opt.ContainsKey($k)) { return [string]$script:Opt[$k] }
    }
    if (-not $Required) { return '' }
    if ([Console]::IsInputRedirected) { throw (Get-CertText 'cli.param.missing' '-Password') }
    return (Read-SecretText $Prompt)
}

function Get-KeyFormatOpt {
    param([string]$Default = 'Pkcs1')
    $v = (Get-Opt @('keyformat') $Default).ToLowerInvariant()
    if ($v -eq 'pkcs8') { return 'Pkcs8' }
    return 'Pkcs1'
}

# ============================================================
#  私钥来源解析: 文件 -> 证书存储 -> 密钥容器
# ============================================================
function Resolve-PrivateKey {
    param(
        [System.Security.Cryptography.X509Certificates.X509Certificate2]$Cert,
        [string]$KeyPath,
        [switch]$AllowMachineStore
    )

    if ($KeyPath -ne '') {
        if (-not (Test-Path -LiteralPath $KeyPath)) { throw (Get-CertText 'err.file.notfound' $KeyPath) }
        $parms = Read-PrivateKeyFile $KeyPath
        return [PSCustomObject]@{ Params = $parms; Source = (Get-CertText 'cli.key.from.file' $KeyPath) }
    }

    if (-not (Test-IsWindowsHost)) { return $null }

    $found = Find-CertWithPrivateKey $Cert
    if ($found) {
        $rsa = Get-RsaFromCert $found
        if ($rsa) {
            try {
                $p = $rsa.ExportParameters($true)
            } catch {
                $p = $null
            } finally {
                try { $rsa.Dispose() } catch { }
            }
            if ($p -and $p.Modulus) {
                return [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.store' $found.Thumbprint) }
            }
        }
    }

    $oc = Find-OrphanKeyContainer -Cert $Cert -IncludeMachine:$AllowMachineStore
    if ($oc) {
        $p = Get-RsaParamsFromContainer -Container $oc.Container -KeyNumber $oc.KeyNumber -Machine:$oc.Machine -Private
        return [PSCustomObject]@{ Params = $p; Source = (Get-CertText 'cli.key.from.container' $oc.Container) }
    }
    return $null
}

function Get-CertArgument {
    param([string]$Display = '-Cert')
    $p = Get-Opt @('cert', 'certificate', 'in', 'input')
    if ($p -eq '' -and $script:Pos.Count -gt 0) { $p = [string]$script:Pos[0] }
    if ($p -eq '') { throw (Get-CertText 'cli.param.missing' $Display) }
    if (-not (Test-Path -LiteralPath $p)) { throw (Get-CertText 'err.file.notfound' $p) }
    return $p
}

# ============================================================
#  new-csr
# ============================================================
function Invoke-NewCsr {
    $cn = Get-Opt @('cn', 'commonname')
    if ($cn -eq '') { throw (Get-CertText 'cli.param.missing' '-CN') }

    $fields = @{
        CN = $cn
        O  = Get-Opt @('o', 'organization')
        OU = Get-Opt @('ou', 'organizationalunit')
        L  = Get-Opt @('l', 'locality', 'city')
        S  = Get-Opt @('s', 'st', 'state')
        C  = Get-Opt @('c', 'country')
        E  = Get-Opt @('e', 'email')
    }

    $ekuRaw = Get-Opt @('eku', 'usage')
    if ($ekuRaw -eq '') { $ekuRaw = '1.3.6.1.5.5.7.3.2' }
    $ekuList = @($ekuRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })

    $sanRaw = Get-Opt @('san', 'subjectaltname')
    $sanList = @()
    if ($sanRaw -ne '') {
        $sanList = @($sanRaw -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    }

    $keySize = 2048
    $ksText = Get-Opt @('keysize', 'size')
    if ($ksText -ne '') {
        $parsed = 0
        if (-not [int]::TryParse($ksText, [ref]$parsed) -or $parsed -lt 1024 -or $parsed -gt 8192) {
            throw (Get-CertText 'cli.param.invalid' '-KeySize' $ksText)
        }
        $keySize = $parsed
    }

    $hash = Get-Opt @('hash', 'hashalgorithm')
    if ($hash -eq '') { $hash = 'SHA256' }
    $hash = $hash.ToUpperInvariant()
    if (@('SHA1', 'SHA256', 'SHA384', 'SHA512') -notcontains $hash) {
        throw (Get-CertText 'err.hash.unsupported' $hash)
    }

    $keyFormat = Get-KeyFormatOpt

    $outText = Get-Opt @('out', 'output')
    if ($outText -eq '') { $outText = (Get-SafeFileName $cn) + '.csr' }
    $outFile = Resolve-TargetPath $outText -Force:(Test-Opt @('force'))

    $keyText = Get-Opt @('keyout', 'key')
    $keyFile = ''
    if ($keyText -ne '') { $keyFile = Resolve-TargetPath $keyText -Force:(Test-Opt @('force')) }

    # ---- 后端选择 ----
    $backend = (Get-Opt @('backend') 'auto').ToLowerInvariant()
    if (@('auto', 'dotnet', 'certreq') -notcontains $backend) {
        throw (Get-CertText 'cli.param.invalid' '-Backend' $backend)
    }
    if ($backend -eq 'certreq' -and -not (Test-CertReqAvailable)) {
        throw (Get-CertText 'cli.csr.certreq.only')
    }
    if ($backend -eq 'auto') {
        if ($keyFile -ne '' -or -not (Test-CertReqAvailable)) { $backend = 'dotnet' }
        else { $backend = 'certreq' }
    }
    if ($backend -eq 'certreq' -and $keyFile -ne '') {
        throw (Get-CertText 'cli.param.invalid' '-KeyOut' 'certreq backend keeps the key in a local container')
    }
    if ($backend -eq 'dotnet' -and $keyFile -eq '') {
        throw (Get-CertText 'cli.param.missing' '-KeyOut (required with the dotnet backend)')
    }

    Write-Line (Get-CertText 'log.csr.header') 'Cyan'
    Write-Line ((Get-CertText 'csr.subject') + ': ' + (Get-DistinguishedNameText $fields))
    Write-Line (Get-CertText 'log.csr.backend' $backend)
    Write-Line (Get-CertText 'log.csr.eku' ($ekuList -join ', '))
    if ($sanList.Count -gt 0) { Write-Line (Get-CertText 'log.csr.san' ($sanList -join ', ')) }

    if ($backend -eq 'certreq') {
        # ---- certreq 后端: 私钥落在本机密钥容器里 ----
        $infContent = Build-InfContent -Subject $fields -EkuOids $ekuList -KeyLength $keySize `
                        -HashAlg $hash -Exportable $true -MachineKeySet $false -SanLines $sanList

        $before = @()
        foreach ($loc in (Get-RequestStoreLocations)) {
            $before += @(Get-ChildItem -Path $loc -ErrorAction SilentlyContinue | ForEach-Object { $_.Thumbprint })
        }

        $r = New-CsrViaCertReq -OutFile $outFile -InfContent $infContent
        if (-not $r.Ok) {
            Write-Err ((Get-CertText 'log.csr.failed') + ': ' + $r.Output)
            exit 1
        }
        $size = (Get-Item -LiteralPath $outFile).Length
        Write-Ok (Get-CertText 'cli.csr.written' $outFile $size)
        Write-Line (Get-CertText 'cli.csr.certreq.keynote') 'DarkYellow'

        try {
            $after = @()
            foreach ($loc in (Get-RequestStoreLocations)) {
                $after += @(Get-ChildItem -Path $loc -ErrorAction SilentlyContinue)
            }
            $newReq = $after | Where-Object { $before -notcontains $_.Thumbprint } | Select-Object -First 1
            if ($newReq) {
                $oc = Find-OrphanKeyContainer -Cert $newReq -IncludeMachine
                if ($oc) { Write-Ok (Get-CertText 'log.csr.container' $oc.Container $oc.KeyNumber $oc.Machine) }
                else { Write-Line (Get-CertText 'log.csr.containernone') 'DarkYellow' }
            }
        } catch { }
        return
    }

    # ---- .NET 后端: 私钥由我们生成, 必须落盘 ----
    $req = New-CsrRequest -Fields $fields -EkuOids $ekuList -SanEntries $sanList `
              -KeySize $keySize -HashAlgorithm $hash
    try {
        $parms = $req.Rsa.ExportParameters($true)
    } finally {
        try { $req.Rsa.Dispose() } catch { }
    }

    Write-TextFileNoBom $outFile $req.Pem
    Write-Ok (Get-CertText 'cli.csr.written' $outFile (Get-Item -LiteralPath $outFile).Length)

    Write-TextFileNoBom $keyFile (ConvertTo-PemPrivateKey $parms $keyFormat)
    Write-Ok (Get-CertText 'cli.key.written' $keyFile)
    Write-Line (Get-CertText 'log.csr.keyfilewarn') 'DarkYellow'
    Write-Line (Get-CertText 'cli.csr.portable.note')

    if (Test-Opt @('verbose')) { Write-Line (Get-CsrSummaryText $req.Der) }
}

# ============================================================
#  merge-pfx / merge-pem
# ============================================================
function Get-MergeContext {
    $certPath = Get-CertArgument '-Cert'
    $cert = Get-CertificateFromFile $certPath
    Write-Line (Get-CertText 'log.cert' (($cert.Subject -split ',')[0]))

    $resolved = Resolve-PrivateKey -Cert $cert -KeyPath (Get-Opt @('key', 'keyfile')) -AllowMachineStore
    if (-not $resolved) { throw (Get-CertText 'cli.no.key.found') }
    if (-not (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params)) { throw (Get-CertText 'log.match.bad') }
    Write-Line (Get-CertText 'log.verify.pass') 'Green'
    Write-Line $resolved.Source

    $chain = @()
    if (-not (Test-Opt @('nochain'))) {
        $chainFile = Get-Opt @('chain')
        if ($chainFile -ne '') {
            if (-not (Test-Path -LiteralPath $chainFile)) { throw (Get-CertText 'err.file.notfound' $chainFile) }
            foreach ($c in (Get-AllCertificatesFromFile $chainFile)) {
                if ($c.Thumbprint -ne $cert.Thumbprint) { $chain += $c }
            }
        } else {
            foreach ($c in (Get-AllCertificatesFromFile $certPath)) {
                if ($c.Thumbprint -ne $cert.Thumbprint) { $chain += $c }
            }
        }
        if ($chain.Count -gt 0) { Write-Line (Get-CertText 'log.chain.count' $chain.Count) }
    }

    return [PSCustomObject]@{ Cert = $cert; Params = $resolved.Params; Chain = $chain }
}

function Invoke-MergePfx {
    $ctx = Get-MergeContext
    $outPath = Resolve-TargetPath (Get-RequiredOpt @('out', 'output') '-Out') -Force:(Test-Opt @('force'))
    $pwd = Get-PasswordOpt -Required -Prompt (Get-CertText 'cli.pw.prompt')

    Write-Line (Get-CertText 'log.mode.header' (Get-CertText 'app.title.merge'))
    $size = New-PfxFromCertAndKey -Cert $ctx.Cert -Params $ctx.Params -PfxPath $outPath `
                -Password $pwd -Chain $ctx.Chain
    Write-Ok (Get-CertText 'log.out.size' $outPath $size)

    $back = ConvertFrom-PfxFile -Path $outPath -Password $pwd
    if ($back.Leaf -and $back.Params) {
        Write-Ok (Get-CertText 'log.pfx.good')
    } else {
        Write-Line (Get-CertText 'log.pfx.bad') 'Red'
        exit 1
    }
}

function Invoke-MergePem {
    $ctx = Get-MergeContext
    $outPath = Resolve-TargetPath (Get-RequiredOpt @('out', 'output') '-Out') -Force:(Test-Opt @('force'))

    $text = New-MergedPemText -Cert $ctx.Cert -Params $ctx.Params -Chain $ctx.Chain `
                -KeyFormat (Get-KeyFormatOpt) -NoChain:(Test-Opt @('nochain'))
    Write-TextFileNoBom $outPath $text
    Write-Ok (Get-CertText 'log.out.size' $outPath (Get-Item -LiteralPath $outPath).Length)
    Write-Line (Get-CertText 'log.pem.note')
}

# ============================================================
#  split-pfx
# ============================================================
function Invoke-SplitPfx {
    $inPath = Get-Opt @('in', 'input')
    if ($inPath -eq '') { $inPath = Get-Opt @('cert', 'certificate') }
    if ($inPath -eq '' -and $script:Pos.Count -gt 0) { $inPath = [string]$script:Pos[0] }
    if ($inPath -eq '') { throw (Get-CertText 'cli.param.missing' '-In') }
    if (-not (Test-Path -LiteralPath $inPath)) { throw (Get-CertText 'err.file.notfound' $inPath) }

    $inPath = (Resolve-Path -LiteralPath $inPath).Path
    $pwd = Get-PasswordOpt -Required -Prompt (Get-CertText 'cli.pw.prompt')

    Write-Line (Get-CertText 'log.mode.header' (Get-CertText 'app.title.merge'))
    $pfx = ConvertFrom-PfxFile -Path $inPath -Password $pwd
    Write-Line (Get-CertText 'log.split.count' $pfx.Count)
    foreach ($c in $pfx.All) {
        Write-Line (Get-CertText 'log.split.item' (($c.Subject -split ',')[0]) $c.HasPrivateKey)
    }
    if (-not $pfx.Leaf) { throw (Get-CertText 'log.split.noLeaf') }
    if (-not $pfx.Params) { throw (Get-CertText 'err.key.not.exportable') }

    # 输出前缀可以是目录, 也可以带文件名
    $prefixText = Get-Opt @('out', 'output')
    $dir = ''
    $base = ''
    if ($prefixText -eq '') {
        $dir = [System.IO.Path]::GetDirectoryName($inPath)
        $base = [System.IO.Path]::GetFileNameWithoutExtension($inPath)
    } elseif (Test-Path -LiteralPath $prefixText -PathType Container) {
        $dir = (Resolve-Path -LiteralPath $prefixText).Path
        $base = [System.IO.Path]::GetFileNameWithoutExtension($inPath)
    } else {
        # ★ -Out 是"前缀", 不是文件路径: 名字里的点号要原样保留
        #   (例如 -Out my.cert 应该得到 my.cert-cert.pem, 而不是 my-cert.pem)
        $prefix = Resolve-TargetPath $prefixText
        $dir = [System.IO.Path]::GetDirectoryName($prefix)
        $base = [System.IO.Path]::GetFileName($prefix)
    }
    if (-not $dir) { $dir = (Get-Location).Path }
    if (-not $base) { $base = 'certificate' }
    if (-not [System.IO.Directory]::Exists($dir)) { [void][System.IO.Directory]::CreateDirectory($dir) }

    $force = Test-Opt @('force')
    $certPem = Join-Path $dir ($base + '-cert.pem')
    $keyPem  = Join-Path $dir ($base + '-key.pem')
    if (-not $force) {
        foreach ($p in @($certPem, $keyPem)) {
            if (Test-Path -LiteralPath $p) { throw (Get-CertText 'cli.overwrite.blocked' $p) }
        }
    }

    $certSb = New-Object System.Text.StringBuilder
    [void]$certSb.Append((ConvertTo-PemCertificate $pfx.Leaf))
    foreach ($c in $pfx.Chain) { [void]$certSb.Append((ConvertTo-PemCertificate $c)) }
    Write-TextFileNoBom $certPem $certSb.ToString()
    Write-Ok (Get-CertText 'log.split.cert' $certPem)

    Write-TextFileNoBom $keyPem (ConvertTo-PemPrivateKey $pfx.Params (Get-KeyFormatOpt))
    Write-Ok (Get-CertText 'log.split.key' $keyPem)

    if (Test-Opt @('der')) {
        $derPath = Join-Path $dir ($base + '-cert.der')
        [System.IO.File]::WriteAllBytes($derPath, $pfx.Leaf.RawData)
        Write-Ok (Get-CertText 'log.split.der' $derPath)
    }
    Write-Ok (Get-CertText 'log.split.done')
}

# ============================================================
#  info / verify / export-key / scan-keys
# ============================================================
function Invoke-Info {
    $certPath = Get-CertArgument '-Cert'
    $ext = [System.IO.Path]::GetExtension($certPath).ToLowerInvariant()

    if ($ext -eq '.pfx' -or $ext -eq '.p12') {
        $pwd = Get-PasswordOpt -Required -Prompt (Get-CertText 'cli.pw.prompt')
        $pfx = ConvertFrom-PfxFile -Path $certPath -Password $pwd
        $first = $true
        foreach ($c in $pfx.All) {
            if (-not $first) { Write-Line '------------------------------------------------------------' 'DarkGray' }
            Write-Line (Get-CertSummary $c)
            $first = $false
        }
        return
    }

    Write-Line (Get-CertSummary (Get-CertificateFromFile $certPath))
}

function Invoke-Verify {
    $certPath = Get-CertArgument '-Cert'
    $cert = Get-CertificateFromFile $certPath
    Write-Line (Get-CertText 'log.cert' (($cert.Subject -split ',')[0]))
    Write-Line (Get-CertText 'log.thumb' $cert.Thumbprint)

    $resolved = Resolve-PrivateKey -Cert $cert -KeyPath (Get-Opt @('key', 'keyfile')) -AllowMachineStore
    if (-not $resolved) {
        Write-Line (Get-CertText 'log.no.key') 'Red'
        if (Test-IsWindowsHost) { Write-Line (Get-CertText 'log.no.key.hint') 'DarkYellow' }
        exit 1
    }
    Write-Line $resolved.Source

    if (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params) {
        Write-Ok (Get-CertText 'log.match.ok')
        return
    }
    Write-Line (Get-CertText 'log.match.bad') 'Red'
    exit 1
}

function Invoke-ExportKey {
    $certPath = Get-CertArgument '-Cert'
    $cert = Get-CertificateFromFile $certPath

    $resolved = Resolve-PrivateKey -Cert $cert -KeyPath (Get-Opt @('key', 'keyfile')) -AllowMachineStore
    if (-not $resolved) {
        Write-Line (Get-CertText 'log.no.key') 'Red'
        exit 1
    }
    if (-not (Test-KeyMatchesCert -Cert $cert -Params $resolved.Params)) {
        Write-Line (Get-CertText 'log.match.bad') 'Red'
        exit 1
    }

    $outText = Get-Opt @('out', 'output')
    if ($outText -eq '') {
        $dir0 = [System.IO.Path]::GetDirectoryName($certPath)
        $name0 = [System.IO.Path]::GetFileNameWithoutExtension($certPath) + '-key.pem'
        if ($dir0) { $outText = [System.IO.Path]::Combine($dir0, $name0) } else { $outText = $name0 }
    }
    $outPath = Resolve-TargetPath $outText -Force:(Test-Opt @('force'))

    $fmt = Get-KeyFormatOpt
    Write-TextFileNoBom $outPath (ConvertTo-PemPrivateKey $resolved.Params $fmt)
    Write-Ok (Get-CertText 'log.exported' $outPath)
    Write-Line (Get-CertText 'log.export.src' $resolved.Source)
    Write-Line (Get-CertText 'log.export.fmt' $fmt)
    Write-Line (Get-CertText 'log.export.warn') 'DarkYellow'
}

function Invoke-ScanKeys {
    if (-not (Test-IsWindowsHost)) {
        Write-Line (Get-CertText 'err.certreq.missing') 'Yellow'
        return
    }
    $user = @(Get-KeyContainerNames)
    Write-Line (Get-CertText 'cli.scan.header') 'Cyan'
    if ($user.Count -eq 0) { Write-Line (Get-CertText 'cli.scan.empty') }
    else { foreach ($n in $user) { Write-Line ('  ' + $n) } }
    Write-Line (Get-CertText 'cli.scan.count' $user.Count)

    if (Test-Opt @('machine')) {
        $mach = @(Get-KeyContainerNames -Machine)
        Write-Line (Get-CertText 'cli.scan.machine') 'Cyan'
        if ($mach.Count -eq 0) { Write-Line (Get-CertText 'cli.scan.empty') }
        else { foreach ($n in $mach) { Write-Line ('  ' + $n) } }
        Write-Line (Get-CertText 'cli.scan.count' $mach.Count)
    }
}

# ============================================================
#  交互式菜单
# ============================================================
function Read-Answer {
    param([string]$Prompt, [string]$Default = '')
    $v = Read-Host -Prompt $Prompt
    if ([string]::IsNullOrWhiteSpace($v)) { return $Default }
    return $v.Trim()
}

function Invoke-Menu {
    while ($true) {
        Write-Host ''
        Write-Line ('=== ' + (Get-CertText 'menu.title') + ' ===') 'Cyan'
        Write-Line ((Get-CertText 'app.platform') + ': ' + (Get-PlatformLabel))
        Write-Host ''

        $items = @(
            (Get-CertText 'menu.0'), (Get-CertText 'menu.1'), (Get-CertText 'menu.2'),
            (Get-CertText 'menu.3'), (Get-CertText 'menu.4'), (Get-CertText 'menu.5'),
            (Get-CertText 'menu.6'), (Get-CertText 'menu.7')
        )
        for ($i = 0; $i -lt $items.Count; $i++) { Write-Line ('  [' + $i + '] ' + $items[$i]) }

        $choice = Read-Answer (Get-CertText 'menu.prompt') '0'

        if ($choice -eq '7') { Write-Line (Get-CertText 'menu.bye'); return }
        if ($choice -eq '6') {
            $next = 'en'
            if ((Get-CertLanguage) -eq 'en') { $next = 'zh' }
            Set-CertLanguage $next | Out-Null
            continue
        }

        try {
            if     ($choice -eq '0') { Invoke-MenuNewCsr }
            elseif ($choice -eq '1') { Invoke-MenuMergePfx }
            elseif ($choice -eq '2') { Invoke-MenuMergePem }
            elseif ($choice -eq '3') { Invoke-MenuSplit }
            elseif ($choice -eq '4') { Invoke-MenuInfo }
            elseif ($choice -eq '5') { Invoke-MenuVerify }
            else { Write-Line (Get-CertText 'menu.invalid') 'Yellow'; continue }
        } catch {
            Write-Err $_.Exception.Message
        }
        [void](Read-Host -Prompt (Get-CertText 'menu.press.enter'))
    }
}

function Invoke-MenuNewCsr {
    $cn = Read-Answer (Get-CertText 'menu.label.cn')
    if ($cn -eq '') { throw (Get-CertText 'msg.cn.required') }
    $san = Read-Answer (Get-CertText 'menu.label.san')
    $dir = Get-DefaultOutputDirectory
    $safe = Get-SafeFileName $cn

    $script:Opt = @{}
    $script:Opt['cn'] = $cn
    if ($san -ne '') { $script:Opt['san'] = $san }
    $script:Opt['keyout'] = Read-Answer (Get-CertText 'menu.label.out') (Join-Path $dir ($safe + '.key'))
    $script:Opt['out'] = Join-Path $dir ($safe + '.csr')
    $script:Opt['force'] = $true
    $script:Opt['backend'] = 'dotnet'
    Invoke-NewCsr
}

function Invoke-MenuMergePfx {
    $script:Opt = @{}
    $script:Opt['cert'] = Read-Answer (Get-CertText 'menu.label.cert')
    $script:Opt['key'] = Read-Answer (Get-CertText 'menu.label.key')
    $default = [System.IO.Path]::ChangeExtension($script:Opt['cert'], '.pfx')
    $script:Opt['out'] = Read-Answer (Get-CertText 'menu.label.out') $default
    $script:Opt['password'] = Read-SecretText (Get-CertText 'menu.label.pwd')
    $script:Opt['force'] = $true
    Invoke-MergePfx
}

function Invoke-MenuMergePem {
    $script:Opt = @{}
    $script:Opt['cert'] = Read-Answer (Get-CertText 'menu.label.cert')
    $script:Opt['key'] = Read-Answer (Get-CertText 'menu.label.key')
    $default = [System.IO.Path]::ChangeExtension($script:Opt['cert'], '.pem')
    $script:Opt['out'] = Read-Answer (Get-CertText 'menu.label.out') $default
    $script:Opt['force'] = $true
    Invoke-MergePem
}

function Invoke-MenuSplit {
    $script:Opt = @{}
    $script:Opt['in'] = Read-Answer (Get-CertText 'menu.label.pfx')
    $script:Opt['password'] = Read-SecretText (Get-CertText 'menu.label.pwd')
    $script:Opt['force'] = $true
    Invoke-SplitPfx
}

function Invoke-MenuInfo {
    $script:Opt = @{}
    $script:Opt['cert'] = Read-Answer (Get-CertText 'menu.label.cert')
    $ext = [System.IO.Path]::GetExtension($script:Opt['cert']).ToLowerInvariant()
    if ($ext -eq '.pfx' -or $ext -eq '.p12') {
        $script:Opt['password'] = Read-SecretText (Get-CertText 'menu.label.pwd')
    }
    Invoke-Info
}

function Invoke-MenuVerify {
    $script:Opt = @{}
    $script:Opt['cert'] = Read-Answer (Get-CertText 'menu.label.cert')
    $script:Opt['key'] = Read-Answer (Get-CertText 'menu.label.key')
    Invoke-Verify
}

# ============================================================
#  帮助
# ============================================================
function Show-Usage {
    Write-Line (Get-CertText 'app.title') 'Cyan'
    Write-Line ((Get-CertText 'app.version') + ' ' + (Get-CertToolVersion) + '   ' + (Get-PlatformLabel))
    Write-Host ''
    Write-Line (Get-CertText 'cli.usage')
}

function Show-CommandHelp {
    param([string]$Name)
    switch ($Name) {
        'new-csr'    { Write-Line (Get-CertText 'cli.help.new-csr'); return }
        'merge-pfx'  { Write-Line (Get-CertText 'cli.help.merge-pfx'); return }
        'merge-pem'  { Write-Line (Get-CertText 'cli.help.merge-pem'); return }
        'split-pfx'  { Write-Line (Get-CertText 'cli.help.split-pfx'); return }
        'info'       { Write-Line (Get-CertText 'cli.help.info'); return }
        'verify'     { Write-Line (Get-CertText 'cli.help.verify'); return }
        'export-key' { Write-Line (Get-CertText 'cli.help.export-key'); return }
        'scan-keys'  { Write-Line (Get-CertText 'cli.help.scan-keys'); return }
        default      { Show-Usage; return }
    }
}

# ============================================================
#  入口
# ============================================================
try {
    Initialize-Options @($args)
} catch {
    Write-Err $_.Exception.Message
    exit 2
}

$langOpt = Get-Opt @('language', 'lang')
if ($langOpt -ne '') {
    try { Set-CertLanguage $langOpt | Out-Null }
    catch { Write-Err $_.Exception.Message; exit 2 }
}

if ((Test-Opt @('version', 'v')) -and $script:Cmd -eq '') {
    Write-Line ((Get-CertToolVersion) + '  ' + (Get-PlatformLabel))
    exit 0
}

if (Test-Opt @('help', 'h')) {
    if ($script:Cmd -ne '') { Show-CommandHelp $script:Cmd } else { Show-Usage }
    exit 0
}

$cmd = $script:Cmd

# 允许 `csrtool.ps1 somefile.pfx` 直接看详情
if ($cmd -eq '') {
    if ($script:Pos.Count -gt 0) { $cmd = 'info' }
}

if ($cmd -eq '' -or $cmd -eq 'help') {
    if ($cmd -eq 'help') { Show-Usage } else { Invoke-Menu }
    exit 0
}

try {
    if     ($cmd -eq 'new-csr')    { Invoke-NewCsr }
    elseif ($cmd -eq 'merge-pfx')  { Invoke-MergePfx }
    elseif ($cmd -eq 'merge-pem')  { Invoke-MergePem }
    elseif ($cmd -eq 'split-pfx')  { Invoke-SplitPfx }
    elseif ($cmd -eq 'info')       { Invoke-Info }
    elseif ($cmd -eq 'verify')     { Invoke-Verify }
    elseif ($cmd -eq 'export-key') { Invoke-ExportKey }
    elseif ($cmd -eq 'scan-keys')  { Invoke-ScanKeys }
    elseif ($cmd -eq 'serve')      { Invoke-Menu }
    else {
        Write-Err (Get-CertText 'cli.unknown.cmd' $cmd)
        Write-Line (Get-CertText 'cli.help.hint')
        exit 2
    }
} catch {
    Write-Err $_.Exception.Message
    exit 1
}

exit 0

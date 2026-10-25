#Requires -Version 5.1
<#
    CSR 证书申请生成器  (CertReq GUI)   ★ 旧版, 仅作参考 ★
    ------------------------------------------------------------
    这个单页工具的功能已被 CertToolkit.ps1 完全覆盖, 并且:
      · 只在 Windows PowerShell 5.1 + certreq 下测试过
      · 没有跨平台 / 可移植模式 / 双语界面
    新用户请直接用  启动证书工具箱.bat  或  CertToolkit.ps1

    ------------------------------------------------------------
    · 可视化选择证书用途 (EKU)、填写主题信息、配置密钥和 SAN
    · 默认只生成本地 CSR 文件 (.req)，私钥留在本机证书存储
    · 生成的申请可以交给任何 CA (certreq -submit) 签发
    · 密钥存储位置可选「用户」或「机器」——注意:
        MachineKeySet 生成的私钥【只能导入到机器存储】
        UserKeySet    生成的私钥【只能导入到用户存储】
    · AIA (含 OCSP) 和 CDP 由【CA 在签发时】添加, 不体现在 CSR 里
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$ErrorActionPreference = "Stop"

# ============================================================
#  证书用途 (EKU) 定义
# ============================================================
$EkuList = @(
    @{ Label = "客户端身份验证  Client Authentication"; Oid = "1.3.6.1.5.5.7.3.2"; Checked = $true  },
    @{ Label = "服务器身份验证  Server Authentication"; Oid = "1.3.6.1.5.5.7.3.1"; Checked = $false },
    @{ Label = "代码签名          Code Signing";        Oid = "1.3.6.1.5.5.7.3.3"; Checked = $false },
    @{ Label = "电子邮件保护      Email Protection";    Oid = "1.3.6.1.5.5.7.3.4"; Checked = $false },
    @{ Label = "IPsec 终端        IPsec End System";    Oid = "1.3.6.1.5.5.7.3.5"; Checked = $false },
    @{ Label = "IPsec 隧道        IPsec Tunnel";        Oid = "1.3.6.1.5.5.7.3.6"; Checked = $false },
    @{ Label = "IPsec 用户        IPsec User";          Oid = "1.3.6.1.5.5.7.3.7"; Checked = $false },
    @{ Label = "时间戳            Time Stamping";       Oid = "1.3.6.1.5.5.7.3.8"; Checked = $false },
    @{ Label = "OCSP 签名         OCSP Signing";        Oid = "1.3.6.1.5.5.7.3.9"; Checked = $false },
    @{ Label = "智能卡登录        Smart Card Logon";    Oid = "1.3.6.1.4.1.311.20.2.2"; Checked = $false },
    @{ Label = "远程桌面身份验证  RDP Authentication";  Oid = "1.3.6.1.4.1.311.54.1.2"; Checked = $false }
)

$script:SanEntries = New-Object System.Collections.ArrayList
$script:LogBox     = $null

# ============================================================
#  工具函数
# ============================================================
function Write-Log {
    param([string]$Text, [string]$Color = "Black")
    if (-not $script:LogBox) { return }
    $ts = (Get-Date).ToString("HH:mm:ss")
    $script:LogBox.SelectionStart  = $script:LogBox.TextLength
    $script:LogBox.SelectionLength = 0
    $script:LogBox.SelectionColor  = [System.Drawing.Color]::FromName($Color)
    $script:LogBox.AppendText("[$ts] $Text`r`n")
    $script:LogBox.SelectionStart  = $script:LogBox.TextLength
    $script:LogBox.ScrollToCaret()
    [System.Windows.Forms.Application]::DoEvents()
}

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 110)
    $l = New-Object System.Windows.Forms.Label
    $l.Text = $Text
    $l.Location = New-Object System.Drawing.Point($X, $Y)
    $l.Size = New-Object System.Drawing.Size($W, 22)
    $l.TextAlign = "MiddleRight"
    return $l
}

function New-TextBox {
    param([int]$X, [int]$Y, [int]$W = 300)
    $t = New-Object System.Windows.Forms.TextBox
    $t.Location = New-Object System.Drawing.Point($X, $Y)
    $t.Size = New-Object System.Drawing.Size($W, 22)
    return $t
}

# ============================================================
#  生成 INF 内容
# ============================================================
function Build-InfContent {
    param(
        [hashtable]$Subject,
        [string[]]$EkuOids,
        [int]$KeyLength,
        [string]$HashAlg,
        [bool]$Exportable,
        [bool]$MachineKeySet,
        [string[]]$SanLines
    )

    $sb = New-Object System.Text.StringBuilder

    # ---- Subject DN: 顺序遵循 Windows 惯例 C, S, L, O, OU, CN ----
    $parts = @()
    if ($Subject.C  -ne "") { $parts += ("C="  + $Subject.C)  }
    if ($Subject.S  -ne "") { $parts += ("S="  + $Subject.S)  }
    if ($Subject.L  -ne "") { $parts += ("L="  + $Subject.L)  }
    if ($Subject.O  -ne "") { $parts += ("O="  + $Subject.O)  }
    if ($Subject.OU -ne "") { $parts += ("OU=" + $Subject.OU) }
    if ($Subject.CN -ne "") { $parts += ("CN=" + $Subject.CN) }
    if ($Subject.E  -ne "") { $parts += ("E="  + $Subject.E)  }
    $dn = $parts -join ", "

    [void]$sb.AppendLine("[NewRequest]")
    [void]$sb.AppendLine("Subject = `"$dn`"")
    [void]$sb.AppendLine("KeyLength = $KeyLength")
    [void]$sb.AppendLine("HashAlgorithm = $HashAlg")
    [void]$sb.AppendLine("Exportable = $($Exportable.ToString().ToUpper())")
    [void]$sb.AppendLine("MachineKeySet = $($MachineKeySet.ToString().ToUpper())")
    [void]$sb.AppendLine("RequestType = PKCS10")
    # ---- EKU: 每行一个 OID ----
    # 这是 certreq 唯一支持的多 EKU 写法 (实测验证):
    #   2.5.29.37="{text}A&{text}B"  -> 报 E_INVALIDARG
    #   2.5.29.37 重复行              -> 报 0x80070560
    #   OID=A,B  /  OID=A;B           -> 报 ERROR_MORE_DATA / INVALID_PARAMETER
    #   只有 [EnhancedKeyUsageExtension] + 逐行 OID=  可行
    if ($EkuOids.Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[EnhancedKeyUsageExtension]")
        foreach ($oid in $EkuOids) {
            [void]$sb.AppendLine("OID=$oid")
        }
    }

    if ($SanLines.Count -gt 0) {
        [void]$sb.AppendLine("")
        [void]$sb.AppendLine("[Extensions]")
        [void]$sb.AppendLine("2.5.29.17 = `"{text}$($SanLines -join '&')`"")
    }

    return $sb.ToString()
}

# ============================================================
#  ======================= 主窗体 =============================
# ============================================================
$form = New-Object System.Windows.Forms.Form
$form.Text = "CSR 证书申请生成器"
$form.Size = New-Object System.Drawing.Size(700, 900)
$form.StartPosition = "CenterScreen"
$form.FormBorderStyle = "FixedDialog"
$form.MaximizeBox = $false
$form.Font = New-Object System.Drawing.Font("Microsoft YaHei UI", 9)

$y = 12

# ---------- 主题信息 ----------
$grpSubj = New-Object System.Windows.Forms.GroupBox
$grpSubj.Text = "主题信息 (Subject)"
$grpSubj.Location = New-Object System.Drawing.Point(12, $y)
$grpSubj.Size = New-Object System.Drawing.Size(660, 210)
$form.Controls.Add($grpSubj)

$grpSubj.Controls.Add((New-Label "通用名称 CN *" 10 26))
$tbCN = New-TextBox 125 24 300
$grpSubj.Controls.Add($tbCN)
$lblCNHint = New-Object System.Windows.Forms.Label
$lblCNHint.Text = "例: NAS-Monitor-I"
$lblCNHint.Location = New-Object System.Drawing.Point(432, 27)
$lblCNHint.Size = New-Object System.Drawing.Size(210, 20)
$lblCNHint.ForeColor = [System.Drawing.Color]::Gray
$grpSubj.Controls.Add($lblCNHint)

$grpSubj.Controls.Add((New-Label "组织 O" 10 52))
$tbO = New-TextBox 125 50 300
$grpSubj.Controls.Add($tbO)

$grpSubj.Controls.Add((New-Label "部门 OU" 10 78))
$tbOU = New-TextBox 125 76 300
$grpSubj.Controls.Add($tbOU)

$grpSubj.Controls.Add((New-Label "城市 L" 10 104))
$tbL = New-TextBox 125 102 180
$grpSubj.Controls.Add($tbL)

$grpSubj.Controls.Add((New-Label "省份 S" 315 104 60))
$tbS = New-TextBox 380 102 180
$grpSubj.Controls.Add($tbS)

$grpSubj.Controls.Add((New-Label "国家 C" 10 130 60))
$tbC = New-TextBox 125 128 60
$tbC.Text = "CN"
$grpSubj.Controls.Add($tbC)

$grpSubj.Controls.Add((New-Label "邮箱 E" 200 130 60))
$tbE = New-TextBox 265 128 295
$grpSubj.Controls.Add($tbE)

$y += 220

# ---------- 证书用途 ----------
$grpEku = New-Object System.Windows.Forms.GroupBox
$grpEku.Text = "证书用途 Enhanced Key Usage (EKU) — 可多选"
$grpEku.Location = New-Object System.Drawing.Point(12, $y)
$grpEku.Size = New-Object System.Drawing.Size(660, 200)
$form.Controls.Add($grpEku)

$script:EkuChecks = @{}
$ex = 12; $ey = 22; $col = 0
foreach ($e in $EkuList) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $e.Label
    $cb.Location = New-Object System.Drawing.Point($ex, $ey)
    $cb.Size = New-Object System.Drawing.Size(315, 22)
    $cb.Checked = $e.Checked
    $cb.Tag = $e.Oid
    $grpEku.Controls.Add($cb)
    $script:EkuChecks[$e.Oid] = $cb
    $ey += 26
    if ($ey -gt 145) { $ey = 22; $ex = 340 }
}

$grpEku.Controls.Add((New-Label "自定义 OID" 8 168 80))
$tbCustomOid = New-TextBox 92 166 260
$grpEku.Controls.Add($tbCustomOid)
$lblOidHint = New-Object System.Windows.Forms.Label
$lblOidHint.Text = "多个用逗号分隔, 例: 1.2.3.4,1.2.3.5"
$lblOidHint.Location = New-Object System.Drawing.Point(360, 169)
$lblOidHint.Size = New-Object System.Drawing.Size(280, 20)
$lblOidHint.ForeColor = [System.Drawing.Color]::Gray
$grpEku.Controls.Add($lblOidHint)

$y += 210

# ---------- 密钥选项 ----------
$grpKey = New-Object System.Windows.Forms.GroupBox
$grpKey.Text = "密钥选项"
$grpKey.Location = New-Object System.Drawing.Point(12, $y)
$grpKey.Size = New-Object System.Drawing.Size(660, 105)
$form.Controls.Add($grpKey)

$grpKey.Controls.Add((New-Label "密钥长度" 10 25 70))
$cbKeyLen = New-Object System.Windows.Forms.ComboBox
$cbKeyLen.DropDownStyle = "DropDownList"
[void]$cbKeyLen.Items.AddRange(@("2048", "3072", "4096"))
$cbKeyLen.SelectedIndex = 0
$cbKeyLen.Location = New-Object System.Drawing.Point(85, 23)
$cbKeyLen.Size = New-Object System.Drawing.Size(90, 22)
$grpKey.Controls.Add($cbKeyLen)

$grpKey.Controls.Add((New-Label "签名算法" 190 25 70))
$cbHash = New-Object System.Windows.Forms.ComboBox
$cbHash.DropDownStyle = "DropDownList"
[void]$cbHash.Items.AddRange(@("SHA256", "SHA384", "SHA512"))
$cbHash.SelectedIndex = 0
$cbHash.Location = New-Object System.Drawing.Point(265, 23)
$cbHash.Size = New-Object System.Drawing.Size(100, 22)
$grpKey.Controls.Add($cbHash)

$cbExport = New-Object System.Windows.Forms.CheckBox
$cbExport.Text = "密钥可导出 (Exportable)"
$cbExport.Location = New-Object System.Drawing.Point(385, 24)
$cbExport.Size = New-Object System.Drawing.Size(190, 22)
$cbExport.Checked = $true
$grpKey.Controls.Add($cbExport)

$cbMachine = New-Object System.Windows.Forms.CheckBox
$cbMachine.Text = "使用机器密钥存储 (MachineKeySet)"
$cbMachine.Location = New-Object System.Drawing.Point(85, 52)
$cbMachine.Size = New-Object System.Drawing.Size(280, 22)
$grpKey.Controls.Add($cbMachine)

$lblMkHint = New-Object System.Windows.Forms.Label
$lblMkHint.Text = "勾选 → 私钥进【机器存储】; 不勾 → 进【用户存储】。导入证书时位置必须匹配"
$lblMkHint.Location = New-Object System.Drawing.Point(12, 78)
$lblMkHint.Size = New-Object System.Drawing.Size(640, 20)
$lblMkHint.ForeColor = [System.Drawing.Color]::Gray
$grpKey.Controls.Add($lblMkHint)

$y += 115

# ---------- SAN ----------
$grpSan = New-Object System.Windows.Forms.GroupBox
$grpSan.Text = "主题备用名称 SAN (服务器证书必填, 客户端证书可选)"
$grpSan.Location = New-Object System.Drawing.Point(12, $y)
$grpSan.Size = New-Object System.Drawing.Size(660, 165)
$form.Controls.Add($grpSan)

$grpSan.Controls.Add((New-Label "类型" 10 25 40))
$cbSanType = New-Object System.Windows.Forms.ComboBox
$cbSanType.DropDownStyle = "DropDownList"
[void]$cbSanType.Items.AddRange(@("DNS 域名", "IP 地址", "Email", "UPN", "URL"))
$cbSanType.SelectedIndex = 0
$cbSanType.Location = New-Object System.Drawing.Point(55, 23)
$cbSanType.Size = New-Object System.Drawing.Size(100, 22)
$grpSan.Controls.Add($cbSanType)

$grpSan.Controls.Add((New-Label "值" 165 25 25))
$tbSanVal = New-TextBox 195 23 320
$grpSan.Controls.Add($tbSanVal)

$btnSanAdd = New-Object System.Windows.Forms.Button
$btnSanAdd.Text = "添加"
$btnSanAdd.Location = New-Object System.Drawing.Point(525, 21)
$btnSanAdd.Size = New-Object System.Drawing.Size(70, 25)
$grpSan.Controls.Add($btnSanAdd)

$lbSan = New-Object System.Windows.Forms.ListBox
$lbSan.Location = New-Object System.Drawing.Point(55, 55)
$lbSan.Size = New-Object System.Drawing.Size(460, 95)
$grpSan.Controls.Add($lbSan)

$btnSanDel = New-Object System.Windows.Forms.Button
$btnSanDel.Text = "删除选中"
$btnSanDel.Location = New-Object System.Drawing.Point(525, 55)
$btnSanDel.Size = New-Object System.Drawing.Size(70, 25)
$grpSan.Controls.Add($btnSanDel)

$btnSanClear = New-Object System.Windows.Forms.Button
$btnSanClear.Text = "全部清空"
$btnSanClear.Location = New-Object System.Drawing.Point(525, 85)
$btnSanClear.Size = New-Object System.Drawing.Size(70, 25)
$grpSan.Controls.Add($btnSanClear)

$y += 175

# ---------- 输出 ----------
$grpOut = New-Object System.Windows.Forms.GroupBox
$grpOut.Text = "输出"
$grpOut.Location = New-Object System.Drawing.Point(12, $y)
$grpOut.Size = New-Object System.Drawing.Size(660, 80)
$form.Controls.Add($grpOut)

$grpOut.Controls.Add((New-Label "保存为" 10 25 55))
$tbOut = New-TextBox 70 23 480
$tbOut.Text = (Join-Path ([Environment]::GetFolderPath("Desktop")) "request.req")
$grpOut.Controls.Add($tbOut)

$btnBrowse = New-Object System.Windows.Forms.Button
$btnBrowse.Text = "浏览..."
$btnBrowse.Location = New-Object System.Drawing.Point(558, 21)
$btnBrowse.Size = New-Object System.Drawing.Size(90, 25)
$grpOut.Controls.Add($btnBrowse)

$cbSaveInf = New-Object System.Windows.Forms.CheckBox
$cbSaveInf.Text = "同时保存 INF 便于复查"
$cbSaveInf.Location = New-Object System.Drawing.Point(70, 52)
$cbSaveInf.Size = New-Object System.Drawing.Size(220, 22)
$cbSaveInf.Checked = $true
$grpOut.Controls.Add($cbSaveInf)

$y += 90

# ---------- 按钮 ----------
$btnGen = New-Object System.Windows.Forms.Button
$btnGen.Text = "生成 CSR"
$btnGen.Location = New-Object System.Drawing.Point(12, $y)
$btnGen.Size = New-Object System.Drawing.Size(140, 34)
$btnGen.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
$btnGen.ForeColor = [System.Drawing.Color]::White
$btnGen.FlatStyle = "Flat"
$form.Controls.Add($btnGen)

$btnPrev = New-Object System.Windows.Forms.Button
$btnPrev.Text = "预览 INF"
$btnPrev.Location = New-Object System.Drawing.Point(162, $y)
$btnPrev.Size = New-Object System.Drawing.Size(110, 34)
$form.Controls.Add($btnPrev)

$btnClear = New-Object System.Windows.Forms.Button
$btnClear.Text = "清空表单"
$btnClear.Location = New-Object System.Drawing.Point(282, $y)
$btnClear.Size = New-Object System.Drawing.Size(110, 34)
$form.Controls.Add($btnClear)

$btnOpenFolder = New-Object System.Windows.Forms.Button
$btnOpenFolder.Text = "打开输出目录"
$btnOpenFolder.Location = New-Object System.Drawing.Point(402, $y)
$btnOpenFolder.Size = New-Object System.Drawing.Size(120, 34)
$form.Controls.Add($btnOpenFolder)

$y += 45

# ---------- 日志 ----------
$grpLog = New-Object System.Windows.Forms.GroupBox
$grpLog.Text = "日志"
$grpLog.Location = New-Object System.Drawing.Point(12, $y)
$grpLog.Size = New-Object System.Drawing.Size(660, 118)
$form.Controls.Add($grpLog)

$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Location = New-Object System.Drawing.Point(10, 20)
$script:LogBox.Size = New-Object System.Drawing.Size(640, 90)
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(250, 250, 250)
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 8.5)
$script:LogBox.ScrollBars = "Vertical"
$grpLog.Controls.Add($script:LogBox)

# ============================================================
#  收集表单数据
# ============================================================
function Get-FormData {
    $subj = @{
        CN = $tbCN.Text.Trim()
        O  = $tbO.Text.Trim()
        OU = $tbOU.Text.Trim()
        L  = $tbL.Text.Trim()
        S  = $tbS.Text.Trim()
        C  = $tbC.Text.Trim()
        E  = $tbE.Text.Trim()
    }

    $ekus = @()
    foreach ($k in $script:EkuChecks.Keys) {
        if ($script:EkuChecks[$k].Checked) { $ekus += $k }
    }
    if ($tbCustomOid.Text.Trim() -ne "") {
        foreach ($o in ($tbCustomOid.Text -split ",")) {
            $v = $o.Trim()
            if ($v -ne "" -and $v -match "^\d+(\.\d+)+$") { $ekus += $v }
        }
    }

    $san = @()
    foreach ($s in $script:SanEntries) { $san += $s.RawLine }

    return @{
        Subject      = $subj
        EkuOids      = $ekus
        KeyLength    = [int]$cbKeyLen.SelectedItem
        HashAlg      = [string]$cbHash.SelectedItem
        Exportable   = $cbExport.Checked
        MachineKeySet= $cbMachine.Checked
        SanLines     = $san
    }
}

function Test-FormData {
    param($Data)
    if ($Data.Subject.CN -eq "") {
        [System.Windows.Forms.MessageBox]::Show("【通用名称 CN】不能为空。", "缺少必填项", "OK", "Warning") | Out-Null
        return $false
    }
    if ($Data.EkuOids.Count -eq 0) {
        $r = [System.Windows.Forms.MessageBox]::Show("没有选择任何【证书用途 EKU】。`r`n`r`n不带 EKU 的证书会被很多系统拒绝使用。`r`n确定要继续吗?", "未选择用途", "YesNo", "Warning")
        if ($r -ne "Yes") { return $false }
    }
    # 检查非 ASCII 字符 (certreq 的 INF 兼容性提示)
    $allText = ($Data.Subject.Values -join " ") + " " + ($Data.SanLines -join " ")
    if ($allText -match "[^\x00-\x7F]") {
        $r = [System.Windows.Forms.MessageBox]::Show(
            "检测到非 ASCII 字符 (中文等)。`r`n`r`n这通常可以工作, 但如果 certreq 报错,`r`n请改用拼音或英文重试。`r`n`r`n继续吗?",
            "包含非 ASCII 字符", "YesNo", "Information")
        if ($r -ne "Yes") { return $false }
    }
    return $true
}

# ============================================================
#  事件绑定
# ============================================================
$btnSanAdd.Add_Click({
    $t = $cbSanType.SelectedItem
    $v = $tbSanVal.Text.Trim()
    if ($v -eq "") { return }
    $prefix = switch ($t) {
        "DNS 域名" { "dns" }
        "IP 地址"  { "ipaddress" }
        "Email"    { "email" }
        "UPN"      { "upn" }
        "URL"      { "URL" }
        default    { "dns" }
    }
    $raw = "$prefix=$v"
    $null = $script:SanEntries.Add([PSCustomObject]@{ Display = $raw; RawLine = $raw })
    $lbSan.Items.Add($raw) | Out-Null
    $tbSanVal.Clear()
})

$btnSanDel.Add_Click({
    if ($lbSan.SelectedIndex -ge 0) {
        $i = $lbSan.SelectedIndex
        $lbSan.Items.RemoveAt($i)
        $script:SanEntries.RemoveAt($i)
    }
})

$btnSanClear.Add_Click({
    $lbSan.Items.Clear()
    $script:SanEntries.Clear()
})

$btnBrowse.Add_Click({
    $sfd = New-Object System.Windows.Forms.SaveFileDialog
    $sfd.Filter = "证书申请文件 (*.req)|*.req|所有文件 (*.*)|*.*"
    $sfd.FileName = "request.req"
    if ($sfd.ShowDialog() -eq "OK") { $tbOut.Text = $sfd.FileName }
})

$btnOpenFolder.Add_Click({
    $dir = Split-Path $tbOut.Text -Parent
    if (Test-Path $dir) { Start-Process explorer.exe $dir }
})

$btnClear.Add_Click({
    foreach ($c in @($tbCN, $tbO, $tbOU, $tbL, $tbS, $tbE, $tbCustomOid, $tbSanVal)) { $c.Clear() }
    $tbC.Text = "CN"
    $lbSan.Items.Clear()
    $script:SanEntries.Clear()
    foreach ($k in $script:EkuChecks.Keys) { $script:EkuChecks[$k].Checked = $false }
    $script:EkuChecks["1.3.6.1.5.5.7.3.2"].Checked = $true
    $cbKeyLen.SelectedIndex = 0
    $cbHash.SelectedIndex = 0
    $cbExport.Checked = $true
    $cbMachine.Checked = $false
    Write-Log "表单已清空" "Gray"
})

$btnPrev.Add_Click({
    try {
        $d = Get-FormData
        $content = Build-InfContent -Subject $d.Subject -EkuOids $d.EkuOids -KeyLength $d.KeyLength `
                                    -HashAlg $d.HashAlg -Exportable $d.Exportable `
                                    -MachineKeySet $d.MachineKeySet -SanLines $d.SanLines
        $pf = New-Object System.Windows.Forms.Form
        $pf.Text = "INF 预览 (这些内容将交给 certreq -new)"
        $pf.Size = New-Object System.Drawing.Size(760, 480)
        $pf.StartPosition = "CenterParent"
        $rt = New-Object System.Windows.Forms.RichTextBox
        $rt.Dock = "Fill"
        $rt.Font = New-Object System.Drawing.Font("Consolas", 10)
        $rt.Text = $content
        $rt.ReadOnly = $true
        $rt.BackColor = [System.Drawing.Color]::White
        $pf.Controls.Add($rt)
        [void]$pf.ShowDialog($form)
    } catch {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "预览失败", "OK", "Error") | Out-Null
    }
})

$btnGen.Add_Click({
    try {
        $d = Get-FormData
        if (-not (Test-FormData $d)) { return }

        $outFile = $tbOut.Text.Trim()
        if ($outFile -eq "") {
            [System.Windows.Forms.MessageBox]::Show("请填写输出文件路径。", "缺少输出路径", "OK", "Warning") | Out-Null
            return
        }
        $outDir = Split-Path $outFile -Parent
        if (-not (Test-Path $outDir)) {
            New-Item -ItemType Directory -Path $outDir -Force | Out-Null
        }

        $infFile = [System.IO.Path]::ChangeExtension($outFile, ".inf")
        $content = Build-InfContent -Subject $d.Subject -EkuOids $d.EkuOids -KeyLength $d.KeyLength `
                                    -HashAlg $d.HashAlg -Exportable $d.Exportable `
                                    -MachineKeySet $d.MachineKeySet -SanLines $d.SanLines

        Write-Log "========== 开始生成 ==========" "Navy"
        Write-Log ("主题: " + ($d.Subject.Values | Where-Object { $_ -ne "" } | Measure-Object).Count + " 个字段")
        Write-Log ("用途: " + ($d.EkuOids -join ", "))
        Write-Log ("密钥: " + $d.KeyLength + " 位 / " + $d.HashAlg + " / 可导出=" + $d.Exportable + " / 机器存储=" + $d.MachineKeySet)
        if ($d.SanLines.Count -gt 0) { Write-Log ("SAN : " + ($d.SanLines -join ", ")) }

        # 用系统 ANSI 编码写 INF (certreq 按 ANSI 读取)
        [System.IO.File]::WriteAllText($infFile, $content, [System.Text.Encoding]::Default)
        Write-Log ("已写入 INF: " + $infFile) "Gray"

        if (Test-Path $outFile) { Remove-Item $outFile -Force -ErrorAction SilentlyContinue }

        Write-Log "正在调用 certreq -new ..."
        $so = Join-Path $env:TEMP ("csr_o_" + [guid]::NewGuid().ToString("N") + ".txt")
        $se = Join-Path $env:TEMP ("csr_e_" + [guid]::NewGuid().ToString("N") + ".txt")

        $p = Start-Process -FilePath "certreq.exe" -ArgumentList @("-new", $infFile, $outFile) `
                           -PassThru -WindowStyle Hidden -Wait `
                           -RedirectStandardOutput $so -RedirectStandardError $se

        $stdout = if (Test-Path $so) { Get-Content $so -Raw } else { "" }
        $stderr = if (Test-Path $se) { Get-Content $se -Raw } else { "" }
        Remove-Item $so, $se -Force -ErrorAction SilentlyContinue

        if ($stdout) { ($stdout -split "`r?`n") | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log ("  " + $_.Trim()) "DarkGreen" } }
        if ($stderr) { ($stderr -split "`r?`n") | Where-Object { $_.Trim() -ne "" } | ForEach-Object { Write-Log ("  " + $_.Trim()) "DarkRed" } }

        if (-not (Test-Path $outFile)) {
            Write-Log "生成失败: 没有产生 .req 文件" "Red"
            [System.Windows.Forms.MessageBox]::Show("生成失败, 详见日志。", "失败", "OK", "Error") | Out-Null
            return
        }

        $sz = (Get-Item $outFile).Length
        Write-Log ("完成! 申请文件: " + $outFile + "  (" + $sz + " 字节)") "DarkGreen"
        Write-Log "私钥已保存在本机证书存储, 未写入文件。" "Gray"
        if (-not $cbSaveInf.Checked) {
            Remove-Item $infFile -Force -ErrorAction SilentlyContinue
            Write-Log "INF 已删除 (按你的设置)" "Gray"
        } else {
            Write-Log ("INF 保留: " + $infFile) "Gray"
        }

        Write-Log ""
        Write-Log "下一步 (拿到任何一台能连 CA 的机器上执行):" "Navy"
        Write-Log ("  certreq -submit -config - `"" + $outFile + "`" issued.cer") "Gray"
        Write-Log ("  certreq -accept issued.cer") "Gray"
        Write-Log "注意: AIA(含OCSP) 和 CDP 由 CA 签发时添加, 不在 CSR 里。" "Gray"

        $r = [System.Windows.Forms.MessageBox]::Show(
            "CSR 生成成功!`r`n`r`n文件: $outFile`r`n大小: $sz 字节`r`n`r`n是否打开所在文件夹?",
            "成功", "YesNo", "Information")
        if ($r -eq "Yes") { Start-Process explorer.exe $outDir }

    } catch {
        Write-Log ("异常: " + $_.Exception.Message) "Red"
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, "出错", "OK", "Error") | Out-Null
    }
})

# ============================================================
#  启动
# ============================================================
$form.Add_Shown({
    Write-Log "CSR 证书申请生成器 已启动" "Navy"
    Write-Log ("主机: " + $env:COMPUTERNAME + "   用户: " + $env:USERNAME) "Gray"
    $cv = & certreq.exe 2>&1 | Select-Object -First 1
    if ($cv) { Write-Log "certreq 可用 ✓" "DarkGreen" } else { Write-Log "警告: 找不到 certreq.exe" "Red" }
    Write-Log "填写主题信息 → 勾选用途 → 点【生成 CSR】" "Gray"
    Write-Log ""
})

[void]$form.ShowDialog()
$form.Dispose()

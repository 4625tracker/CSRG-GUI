# ============================================================
#  CertI18n.ps1  —  中英文界面文案
#  ------------------------------------------------------------
#  用法:
#      . .\lib\CertI18n.ps1
#      Set-CertLanguage 'en'          # 或 'zh'
#      Get-CertText 'app.title'       # -> 当前语言文案
#      Get-CertText 'err.file.notfound' $path
#      T 'app.title'                  # 同上, 简写
#
#  语言选择优先级:
#      1) 显式 Set-CertLanguage / -Language 参数
#      2) 环境变量  CERDTOOL_LANG=zh|en
#      3) 系统区域  中文 -> zh, 其它 -> en
# ============================================================

$script:CertLang = $null
$script:CertLanguages = @('zh', 'en')

$script:CertStrings = @{

# ---------------- 应用 / 通用 ----------------
'app.title'              = @('证书工具箱',            'Certificate Toolkit')
'app.title.csr'          = @('生成 CSR',              'Generate CSR')
'app.title.merge'        = @('合并 / 拆解',           'Merge / Split')
'app.title.full'         = @('证书工具箱  —  CSR 生成  /  证书与私钥合并', 'Certificate Toolkit  —  CSR Generator & Certificate/Key Merger')
'app.version'            = @('版本',                  'Version')
'app.platform'           = @('平台',                  'Platform')
'app.language'           = @('语言',                  'Language')
'app.lang.zh'            = @('中文',                  'Chinese')
'app.lang.en'            = @('English',               'English')

'ui.ok'                  = @('确定',                  'OK')
'ui.cancel'              = @('取消',                  'Cancel')
'ui.yes'                 = @('是',                    'Yes')
'ui.no'                  = @('否',                    'No')
'ui.error'               = @('错误',                  'Error')
'ui.warning'             = @('警告',                  'Warning')
'ui.info'                = @('提示',                  'Information')
'ui.success'             = @('成功',                  'Success')
'ui.failed'              = @('失败',                  'Failed')
'ui.browse'              = @('浏览',                  'Browse')
'ui.clear'               = @('清空',                  'Clear')
'ui.remove'              = @('删除',                  'Remove')
'ui.add'                 = @('添加',                  'Add')
'ui.openfolder'          = @('打开目录',              'Open Folder')
'ui.run'                 = @('执行',                  'Run')
'ui.show'                = @('显示',                  'Show')
'ui.log'                 = @('日志',                  'Log')

# ---------------- 标签页 1: 生成 CSR ----------------
'csr.group.subject'      = @('主题信息 (Subject)',    'Subject')
'csr.label.cn'           = @('通用名称 CN *',         'Common Name CN *')
'csr.label.o'            = @('组织 O',                'Organization O')
'csr.label.ou'           = @('部门 OU',               'Organizational Unit OU')
'csr.label.l'            = @('城市 L',                'City L')
'csr.label.s'            = @('省份 S',                'State S')
'csr.label.c'            = @('国家 C',                'Country C')
'csr.label.e'            = @('邮箱 E',                'Email E')
'csr.hint.cn'            = @('例: NAS-Monitor-I',     'e.g. NAS-Monitor-I')

'csr.group.eku'          = @('证书用途 Enhanced Key Usage (可多选)', 'Certificate Usage / Enhanced Key Usage (multi-select)')
'csr.label.customoid'    = @('自定义 OID',            'Custom OID')
'csr.hint.customoid'     = @('多个用逗号分隔, 如 1.2.3.4,1.2.3.5', 'Comma separated, e.g. 1.2.3.4,1.2.3.5')

'csr.group.key'          = @('密钥选项',              'Key Options')
'csr.label.keylen'       = @('密钥长度',              'Key Length')
'csr.label.hashalg'      = @('签名算法',              'Hash Algorithm')
'csr.chk.exportable'     = @('密钥可导出',            'Key exportable')
'csr.chk.machine'        = @('使用机器密钥存储 (给网站/服务用)', 'Use machine key store (for services)')
'csr.hint.machine'       = @('密钥存放在哪由所选后端决定; 与证书导入位置一致才不会报 0x80090010', 'Keep the key location consistent with where the certificate is imported, or you will hit 0x80090010')
'csr.chk.savekey'        = @('同时把私钥写入文件 (可移植模式)', 'Also save the private key to a file (portable mode)')
'csr.hint.savekey'       = @('不写入任何证书存储, 可在任何系统上使用; 生成后立刻拿到 .key 备份', 'Writes nothing to any certificate store; works on every OS and gives you a .key backup right away')
'csr.chk.portable'       = @('用 .NET 直接生成 CSR (不调用 certreq)', 'Generate the CSR directly with .NET (no certreq)')

'csr.group.san'          = @('主题备用名称 SAN (服务器证书必填)', 'Subject Alternative Name SAN (required for server certificates)')
'csr.label.santype'      = @('类型',                  'Type')
'csr.label.sanvalue'     = @('值',                    'Value')
'csr.san.dns'            = @('DNS 域名',              'DNS Name')
'csr.san.ip'             = @('IP 地址',               'IP Address')
'csr.san.email'          = @('Email',                 'Email')
'csr.san.upn'            = @('UPN',                   'UPN')
'csr.san.url'            = @('URL',                   'URL')

'csr.group.out'          = @('输出',                  'Output')
'csr.label.saveas'       = @('保存为',                'Save as')
'csr.chk.saveinf'        = @('同时保存 INF 便于复查', 'Also keep the INF file for review')
'csr.hint.outname'       = @('文件名会随 CN 自动变化', 'File name follows CN automatically')
'csr.btn.generate'       = @('生成 CSR',              'Generate CSR')
'csr.btn.preview'        = @('预览 INF',              'Preview INF')
'csr.preview.title'      = @('INF 预览',              'INF Preview')

# ---------------- 标签页 2: 合并 / 拆解 ----------------
'merge.group.mode'       = @('操作模式',              'Operation Mode')
'merge.mode.0'           = @('证书文件 + 本机存储的私钥   →   合并成 PFX', 'Certificate + private key from this machine   →   PFX')
'merge.mode.0.desc'      = @('把 CA 签发的 .cer 和本机私钥合成可用的 PFX', 'Combine the CA-issued .cer with the local private key')
'merge.mode.1'           = @('证书文件 + 私钥文件         →   合并成 PFX', 'Certificate + private key file   →   PFX')
'merge.mode.1.desc'      = @('私钥是独立的 .key / .pem 文件时用这个', 'Use this when the private key is a separate .key / .pem file')
'merge.mode.2'           = @('证书文件 + 私钥文件         →   合并成 PEM', 'Certificate + private key file   →   PEM bundle')
'merge.mode.2.desc'      = @('输出一个把证书和私钥拼在一起的 .pem, 给 nginx/apache 之类用', 'One .pem holding both certificate and key, for nginx/apache')
'merge.mode.3'           = @('PFX 文件                    →   拆解', 'PFX file                    →   Split')
'merge.mode.3.desc'      = @('从 PFX 里拆出证书和私钥 (可输出 PEM 或 DER)', 'Extract certificate and key from a PFX (PEM or DER)')

'merge.group.files'      = @('文件',                  'Files')
'merge.label.certfile'   = @('证书文件',              'Certificate File')
'merge.label.keyfile'    = @('私钥文件',              'Private Key File')
'merge.label.pfxpwd'     = @('PFX 密码',              'PFX Password')
'merge.label.outfile'    = @('输出文件',              'Output File')
'merge.hint.pfxpwd'      = @('用于导出/读取 PFX (导入时用同一个密码)', 'Used to write/read the PFX (use the same password when importing)')

'merge.group.options'    = @('选项',                  'Options')
'merge.chk.chain'        = @('PFX 里包含证书链 (把 CA 证书一并打包)', 'Include the certificate chain in the PFX')
'merge.chk.der'          = @('拆解时同时输出 DER 格式', 'Also write a DER copy when splitting')
'merge.chk.install'      = @('允许 certreq -accept 自动配对 (会把证书装入本机证书存储)', 'Allow certreq -accept auto-pairing (installs the certificate into the local store)')
'merge.hint.install'     = @('默认关闭; 只在「合并成 PFX」时生效', 'Off by default; only applies to "merge to PFX"')

'merge.btn.certinfo'     = @('查看证书详情',          'Certificate Details')
'merge.btn.verify'       = @('验证密钥匹配',          'Verify Key Match')
'merge.btn.exportkey'    = @('导出私钥',              'Export Private Key')
'merge.group.log'        = @('日志 / 证书详情',       'Log / Certificate Details')

# ---------------- 证书详情 ----------------
'cert.subject'           = @('主题',                  'Subject')
'cert.issuer'            = @('颁发者',                'Issuer')
'cert.serial'            = @('序列号',                'Serial number')
'cert.thumb'             = @('指纹(SHA1)',            'Thumbprint (SHA1)')
'cert.validity'          = @('有效期',                'Validity')
'cert.daysleft'          = @('剩余天数',              'Days left')
'cert.hasprivatekey'     = @('有私钥',                'Has private key')
'cert.sigalg'            = @('签名算法',              'Signature algorithm')
'cert.extensions'        = @('扩展',                  'Extensions')
'cert.expired'           = @('【已过期】',            '[EXPIRED]')
'cert.expiring'          = @('【即将过期】',          '[EXPIRING SOON]')
'csr.subject'            = @('主题',                  'Subject')
'csr.extension'          = @('扩展',                  'Extension')
'csr.unparsed'           = @('(无法解析 CSR 内容)',   '(could not parse the CSR)')

# ---------------- 校验 / 对话框 ----------------
'val.err.len'            = @('[{0} {1}] 有 {2} 个字符, 超过上限 {3}', '[{0} {1}] has {2} characters, limit is {3}')
'val.err.char'           = @('[{0} {1}] 的值里含有 {2}  →  {3}', '[{0} {1}] contains "{2}"  →  {3}')
'val.warn.country'       = @('[国家 C] 应该是 2 个字母的国家代码, 例如 CN / US / JP', '[Country C] should be a 2-letter country code, e.g. CN / US / JP')
'val.warn.email'         = @('[邮箱 E] 不是合法邮箱 (需要形如 user@example.com)', '[Email E] is not a valid address (expected user@example.com)')
'val.err.total'          = @('主题总长度约 {0} 个字符, 超过上限 {1}', 'Subject is about {0} characters, limit is {1}')
'val.dn.comma'           = @('逗号是 RDN 之间的分隔符, 会被当成多个值的分界', 'A comma separates RDNs and would split your value')
'val.dn.plus'            = @('加号表示多值 RDN',      'A plus sign starts a multi-valued RDN')
'val.dn.quote'           = @('双引号是引用符',        'A double quote is an escape character')
'val.dn.backslash'       = @('反斜杠是转义符',        'A backslash is an escape character')
'val.dn.angleopen'       = @('尖括号在 DN 里有特殊含义', 'Angle brackets are special in a DN')
'val.dn.angleclose'      = @('尖括号在 DN 里有特殊含义', 'Angle brackets are special in a DN')
'val.dn.semicolon'       = @('分号是 RDN 分隔符',     'A semicolon separates RDNs')
'val.status.ok'          = @('✓ 主题信息没问题',      '✓ Subject looks good')
'val.status.warn'        = @('⚠ {0}',                 '⚠ {0}')
'val.status.err'          = @('✗ {0}',                '✗ {0}')
'val.status.more'        = @('(还有 {0} 处)',         '({0} more)')

'msg.title.invalid'      = @('主题信息不合法',        'Invalid Subject')
'msg.title.remind'       = @('主题信息提醒',          'Subject Warning')
'msg.title.missing'      = @('缺少必填项',            'Missing Required Field')
'msg.title.exists'       = @('文件已存在',            'File Already Exists')
'msg.cn.required'        = @('【通用名称 CN】不能为空。', 'The Common Name (CN) cannot be empty.')
'msg.out.required'       = @('请填写输出路径。',      'Please provide an output path.')
'msg.cert.required'      = @('请先选择证书文件。',    'Please choose a certificate file first.')
'msg.key.required'       = @('请选择私钥文件',        'Please choose a private key file')
'msg.outpath.required'   = @('请填写输出文件路径',    'Please provide an output file path')
'msg.pwd.required'       = @('请设置 PFX 密码',       'Please set a PFX password')
'msg.pfx.pwd.required'   = @('请输入 PFX 密码',       'Please enter the PFX password')
'msg.invalid.header'     = @('主题信息有问题, 先修好再生成:', 'The subject has problems; fix them before generating:')
'msg.invalid.limits'     = @('【各字段上限】CN 64 / O 64 / OU 64 / L 128 / S 128 / C 2 / E 128, 整个主题不超过 256', '[Field limits] CN 64 / O 64 / OU 64 / L 128 / S 128 / C 2 / E 128, whole subject <= 256')
'msg.invalid.chars'      = @('【不能用的字符】, + " \ < > ;   —— 逗号是最常见的坑', '[Forbidden characters] , + " \ < > ;   — the comma is the usual trap')
'msg.warn.header'        = @('主题信息有需要注意的地方:', 'The subject needs attention:')
'msg.warn.footer'        = @('这些不一定会被 CA 拒绝, 但建议先改好。仍要继续生成吗?', 'A CA may still accept it, but fixing it first is recommended. Continue anyway?')
'msg.eku.none'           = @('没有选择证书用途 (EKU)。`n不带用途的证书会被很多系统拒绝。`n`n继续吗?', 'No usage (EKU) selected.`nCertificates without EKU are rejected by many systems.`n`nContinue?')
'msg.exists.body'        = @('文件已存在, 会被覆盖:`n`n{0}`n(修改时间 {1})`n`n继续覆盖吗?`n选「否」可改用新文件名。', 'The file already exists:`n`n{0}`n(modified {1})`n`nOverwrite it?`nChoose No to use a new file name.')
'msg.renamed'            = @('已改用新文件名: {0}',   'Switched to a new file name: {0}')
'msg.preview.failed'     = @('预览失败',              'Preview Failed')
'msg.generating'         = @('正在生成 ...',          'Generating ...')
'msg.csr.ok.body'        = @('CSR 生成成功!`n`n{0}`n{1} 字节`n`n现在去「合并 / 拆解」页, 把 CA 签发的 .cer 和私钥合成 PFX 吧。`n`n是否打开所在文件夹?', 'CSR generated successfully!`n`n{0}`n{1} bytes`n`nNext: open the Merge / Split tab to combine the CA-issued .cer with your key.`n`nOpen the containing folder?')
'msg.pfx.ok.body'        = @('合并成功!`n`n{0}`n{1} 字节`n含私钥: {2}', 'Merge succeeded!`n`n{0}`n{1} bytes`nContains private key: {2}')
'msg.pem.ok.body'        = @('合并 PEM 成功!`n`n{0}',  'PEM bundle written!`n`n{0}')
'msg.split.ok.body'      = @('拆解成功!`n`n证书: {0}`n私钥: {1}', 'Split succeeded!`n`nCertificate: {0}`nKey: {1}')
'msg.inftheory'          = @('继续覆盖吗?',           'Overwrite?')

# ---------------- 日志 ----------------
'log.started'            = @('证书工具箱 已启动',     'Certificate Toolkit started')
'log.host'               = @('主机: {0}   用户: {1}   平台: {2}', 'Host: {0}   User: {1}   Platform: {2}')
'log.hint.csr'           = @('填主题 -> 选用途 -> 点【生成 CSR】', 'Fill in the subject, pick usages, then click Generate CSR')
'log.hint.store'         = @('提示: 私钥留在本机才能合并 PFX; 生成后请立刻导出 .key 备份。', 'Tip: the key must stay local to build a PFX; export a .key backup right after generating.')
'log.merge.help.title'   = @('合并 / 拆解 使用说明',  'Merge / Split — how to use')
'log.merge.help.0'       = @('模式1  证书 + 本机私钥 -> PFX     (最常用)', 'Mode 1  Certificate + local key -> PFX     (most common)')
'log.merge.help.1'       = @('模式2  证书 + 私钥文件 -> PFX',            'Mode 2  Certificate + key file -> PFX')
'log.merge.help.2'       = @('模式3  证书 + 私钥文件 -> 合并 PEM',        'Mode 3  Certificate + key file -> PEM bundle')
'log.merge.help.3'       = @('模式4  PFX -> 拆解出证书和私钥',            'Mode 4  PFX -> split into certificate and key')
'log.merge.help.pem'     = @('支持 PEM 私钥格式: PKCS#1 (BEGIN RSA PRIVATE KEY) / PKCS#8 (BEGIN PRIVATE KEY)', 'Supported key PEM formats: PKCS#1 (BEGIN RSA PRIVATE KEY) / PKCS#8 (BEGIN PRIVATE KEY)')
'log.form.cleared'       = @('表单已清空',            'Form cleared')

'log.csr.header'         = @('========== 生成 CSR ==========', '========== Generate CSR ==========')
'log.csr.output'         = @('输出: {0}',             'Output: {0}')
'log.csr.eku'            = @('用途: {0}',             'Usage: {0}')
'log.csr.key'            = @('密钥: {0} 位 / {1} / 机器存储={2}', 'Key: {0} bit / {1} / machine store={2}')
'log.csr.san'            = @('SAN : {0}',             'SAN : {0}')
'log.csr.backend'        = @('后端: {0}',             'Backend: {0}')
'log.csr.failed'         = @('生成失败',              'Generation failed')
'log.csr.done'           = @('完成! {0}  ({1} 字节)', 'Done! {0}  ({1} bytes)')
'log.csr.keynotfile'     = @('私钥保存在本机, 未写入 CSR 文件。', 'The private key stays on this machine; the CSR itself carries no secret.')
'log.csr.container'      = @('私钥密钥容器: {0}   (KeyNumber={1}, 机器存储={2})', 'Private key container: {0}   (KeyNumber={1}, machine store={2})')
'log.csr.containerhint'  = @('  已确认私钥存在且可导出。重开工具后若提示找不到私钥, 到「合并 / 拆解」页点「导出私钥」。', '  Key confirmed and exportable. If it goes missing later, use "Export Private Key" on the Merge / Split tab.')
'log.csr.containernone'  = @('⚠ 没能定位到私钥的密钥容器, 建议立刻点「导出私钥」确认一下。', 'Warning: could not locate the private key container. Use "Export Private Key" to confirm it now.')
'log.csr.containerskip'  = @('密钥容器检查跳过: {0}', 'Container check skipped: {0}')
'log.csr.keyfile'        = @('私钥已写入文件: {0}',   'Private key written to: {0}')
'log.csr.keyfilewarn'    = @('  这是明文私钥, 等于你的身份, 不要外发。', '  This is an unencrypted private key: treat it as your identity, never share it.')
'log.csr.nextstep1'      = @('下一步: certreq -submit -config - "{0}" issued.cer', 'Next: certreq -submit -config - "{0}" issued.cer')
'log.csr.nextstep2'      = @('        certreq -accept issued.cer', '        certreq -accept issued.cer')

'log.cert'               = @('证书: {0}',             'Certificate: {0}')
'log.thumb'              = @('指纹: {0}',             'Thumbprint: {0}')
'log.keyfile.src'        = @('私钥文件: {0}',         'Key file: {0}')
'log.store.found'        = @('本机存储找到: {0}',     'Found in local store: {0}')
'log.scan.containers'    = @('证书存储里没有配对私钥, 正在扫描密钥容器 ...', 'No paired key in the certificate store; scanning key containers ...')
'log.orphan.found'       = @('★ 已从密钥容器找回孤立私钥: {0}', '★ Recovered orphan private key from container: {0}')
'log.orphan.meta'        = @('   KeyNumber={0}  机器存储={1}', '   KeyNumber={0}  machine store={1}')
'log.orphan.readfail'    = @('✗ 找到了私钥容器, 但读取私钥失败: {0}', 'Could not read the key from the container: {0}')
'log.orphan.nonexport'   = @('  最常见原因: 生成 CSR 时没有勾「密钥可导出」; 这种私钥无法打包成 PFX。', '  Most likely the CSR was generated without "Key exportable"; such a key cannot be packed into a PFX.')
'log.no.key'             = @('没有找到任何能用于这张证书的私钥 (证书存储 + 密钥容器都找过了)。', 'No private key for this certificate was found (checked both the store and all containers).')
'log.no.key.hint'        = @('若 CSR 是用「机器密钥存储」生成的, 请用管理员身份重开本工具再试。', 'If the CSR used the machine key store, reopen this tool as Administrator.')
'log.match.ok'           = @('★ 私钥与证书匹配 ✓',    '★ Private key matches the certificate ✓')
'log.match.bad'          = @('★ 私钥与证书不匹配 ✗  这张私钥不能用于该证书', '★ Key does NOT match the certificate ✗  This key cannot be used for it')
'log.verify.pass'        = @('密钥匹配校验: 通过 ✓',  'Key match check: passed ✓')
'log.verify.fail'        = @('验证失败: {0}',         'Verification failed: {0}')
'log.exported'           = @('★ 私钥已导出: {0}',     '★ Private key exported: {0}')
'log.export.src'         = @('   来源: {0}',          '   Source: {0}')
'log.export.fmt'         = @('   格式: {0}, 未加密。', '   Format: {0}, unencrypted.')
'log.export.warn'        = @('   ★ 请妥善保管: 这个文件等于你的身份, 不要外发。', '   ★ Keep it safe: this file is your identity, never share it.')
'log.export.next'        = @('   现在可以用「证书文件 + 私钥文件」模式合并, 或永久备份它。', '   You can now merge it with "Certificate + key file", or keep it as a backup.')
'log.export.fail'        = @('导出失败: {0}',         'Export failed: {0}')
'log.export.failhint'    = @('提示: 若报「密钥不可导出」, 说明生成 CSR 时没勾选「密钥可导出」。', 'Hint: "key not exportable" means the CSR was created without "Key exportable".')
'log.read.fail'          = @('读取失败: {0}',         'Read failed: {0}')
'log.mode.header'        = @('========== {0} ==========', '========== {0} ==========')
'log.chain.count'        = @('证书链: 附带 {0} 张',   'Chain: {0} extra certificate(s)')
'log.out.size'           = @('输出: {0}  ({1} 字节)', 'Output: {0}  ({1} bytes)')
'log.readback'           = @('回读验证: HasPrivateKey={0}', 'Read-back check: HasPrivateKey={0}')
'log.pfx.good'           = @('★ PFX 完整可用 ✓',     '★ PFX is complete and usable ✓')
'log.pfx.bad'            = @('★ PFX 里没有私钥 ✗',   '★ The PFX has no private key ✗')
'log.pem.note'           = @('(证书在前, 私钥在后, 可直接给 nginx 用)', '(certificate first, key after — ready for nginx)')
'log.split.count'        = @('PFX 内含 {0} 张证书',   'The PFX contains {0} certificate(s)')
'log.split.item'         = @('  - {0}   HasPrivateKey={1}', '  - {0}   HasPrivateKey={1}')
'log.split.noLeaf'       = @('PFX 里没有带私钥的证书', 'No certificate with a private key in this PFX')
'log.split.cert'         = @('证书: {0}',             'Certificate: {0}')
'log.split.key'          = @('私钥: {0}',             'Private key: {0}')
'log.split.der'          = @('证书DER: {0}',          'Certificate DER: {0}')
'log.split.done'         = @('★ 拆解完成 ✓',          '★ Split finished ✓')
'log.install.requested'  = @('已勾选自动配对, 正在执行 certreq -accept (会把证书装入本机证书存储) ...', 'Auto-pairing enabled; running certreq -accept (this installs the certificate into the local store) ...')
'log.install.paired'     = @('配对成功, 私钥已和证书关联 ✓', 'Paired successfully; the key is now linked to the certificate ✓')
'log.install.skipped'    = @('证书存储里没有已配对的私钥; 按设置不执行 certreq -accept (本机证书存储保持不动)', 'No paired key in the store; certreq -accept skipped as configured (the store is left untouched)')
'log.use.portable'       = @('私钥是直接从密钥容器读出来的, 本机证书存储没有被改动。', 'The key came straight from its container; the local certificate store was not modified.')
'log.portable.notice'    = @('可移植模式: 私钥只写入文件, 不会碰任何证书存储。', 'Portable mode: the key is only written to a file; no certificate store is touched.')

# ---------------- 错误 ----------------
'err.der.overflow'       = @('DER 数据越界',          'DER data out of range')
'err.der.length.too.long'= @('DER 长度字段过长',      'DER length field too long')
'err.der.content.overflow'= @('DER 内容越界',          'DER content out of range')
'err.oid.invalid'        = @('OID 不合法: {0}',       'Invalid OID: {0}')
'err.dn.empty'           = @('主题信息为空, 至少要填一个字段', 'The subject is empty; fill in at least one field')
'err.san.format'         = @('SAN 条目格式不正确: {0}  (应为 type=value)', 'Bad SAN entry: {0}  (expected type=value)')
'err.san.value.empty'    = @('SAN 条目的值为空: {0}', 'SAN entry has an empty value: {0}')
'err.san.type'           = @('不支持的 SAN 类型: {0}', 'Unsupported SAN type: {0}')
'err.san.ip'             = @('不是合法的 IP 地址: {0}', 'Not a valid IP address: {0}')
'err.pkcs1.structure'    = @('PKCS#1 结构异常 (不是 SEQUENCE)', 'Malformed PKCS#1 (not a SEQUENCE)')
'err.pkcs8.structure'    = @('PKCS#8 结构异常 (不是 SEQUENCE)', 'Malformed PKCS#8 (not a SEQUENCE)')
'err.pkcs8.octet'        = @('PKCS#8 结构异常 (缺少 OCTET STRING)', 'Malformed PKCS#8 (missing OCTET STRING)')
'err.pem.no.block'       = @('没有找到 PEM 块 (需要 -----BEGIN ... PRIVATE KEY-----)', 'No PEM block found (expected -----BEGIN ... PRIVATE KEY-----)')
'err.key.encrypted'      = @('这是加密的私钥 (ENCRYPTED PRIVATE KEY)。请先解密: openssl pkcs8 -in key.pem -out key-dec.pem', 'This is an encrypted key (ENCRYPTED PRIVATE KEY). Decrypt it first: openssl pkcs8 -in key.pem -out key-dec.pem')
'err.key.openssh'        = @('这是 OpenSSH 格式的私钥, 不受支持。请先转换: ssh-keygen -p -m PEM -f id_rsa', 'OpenSSH private keys are not supported. Convert first: ssh-keygen -p -m PEM -f id_rsa')
'err.key.ec'             = @('这是 EC 私钥; 本工具只支持 RSA。请转换: openssl rsa -in ec.key -out rsa.key', 'This is an EC key; only RSA is supported. Convert with: openssl rsa -in ec.key -out rsa.key')
'err.key.no.rsa'         = @('没有找到可识别的 RSA 私钥块', 'No recognizable RSA private key block found')
'err.file.notfound'      = @('文件不存在: {0}',       'File not found: {0}')
'err.key.unreadable'     = @('无法解析私钥文件: {0}', 'Cannot parse the private key file: {0}')
'err.hash.unsupported'   = @('不支持的签名算法: {0}', 'Unsupported hash algorithm: {0}')
'err.no.certificaterequest' = @('当前 .NET 运行时不支持 CertificateRequest (需要 .NET Framework 4.7.2+ 或 .NET Core 2.0+)。请改用 certreq 后端。', 'This .NET runtime has no CertificateRequest (needs .NET Framework 4.7.2+ or .NET Core 2.0+). Use the certreq backend instead.')
'err.is.pfx'             = @('这是 PFX 文件, 请用「拆解」模式', 'That is a PFX file; use the Split mode')
'err.cert.unreadable'    = @('无法解析证书文件: {0}', 'Cannot parse the certificate file: {0}')
'err.pfx.load'           = @('无法读取 PFX: {0}',     'Cannot read the PFX: {0}')
'err.cert.missing'       = @('缺少证书对象',          'Missing certificate object')
'err.key.missing'        = @('缺少私钥参数',          'Missing private key parameters')
'err.pfx.nokey'          = @('合并后仍然没有私钥',    'Still no private key after attaching it')
'err.pfx.portable.framework' = @('在 .NET Framework 上用 RSA.Create() 导出的 PFX, 私钥以后无法再导出 (这是 .NET Framework 的已知限制)。请改用 CSP 容器路径 (不要加 -Portable), 或改用 PowerShell 7。', 'On .NET Framework a PFX built from RSA.Create() carries a private key that can never be exported again (a known .NET Framework limitation). Use the CSP container path (drop -Portable) or switch to PowerShell 7.')
'err.certreq.missing'    = @('找不到 certreq.exe (仅 Windows 可用)', 'certreq.exe not found (Windows only)')
'err.generic'            = @('出错: {0}',             'Error: {0}')
'err.key.not.exportable' = @('私钥不可导出: 生成 CSR 时没有勾选「密钥可导出」', 'The private key is not exportable: the CSR was generated without "Key exportable"')

# ---------------- 菜单 / 关于 ----------------
'app.menu.language'      = @('语言 (Language)',       'Language')
'app.menu.exit'          = @('退出',                  'Exit')
'app.about.title'        = @('关于',                  'About')
'app.about.body'         = @('证书工具箱 {0}`n`nCSR 生成 / 证书与私钥合并`n跨平台版本, 支持 Windows PowerShell 5.1 与 PowerShell 7+`n`n平台: {1}', 'Certificate Toolkit {0}`n`nCSR generation and certificate/key merging`nCross-platform build for Windows PowerShell 5.1 and PowerShell 7+`n`nPlatform: {1}')
'csr.hint.portable'      = @('不写证书存储; 私钥会存成 <文件名>-key.pem', 'No certificate store is touched; the key is saved as <name>-key.pem')

# ---------------- EKU 名称 ----------------
'eku.client'             = @('客户端身份验证',        'Client Authentication')
'eku.server'             = @('服务器身份验证',        'Server Authentication')
'eku.code'               = @('代码签名',              'Code Signing')
'eku.email'              = @('电子邮件保护',          'Email Protection')
'eku.ipsec.end'          = @('IPsec 终端',            'IPsec End System')
'eku.ipsec.tunnel'       = @('IPsec 隧道',            'IPsec Tunnel')
'eku.ipsec.user'         = @('IPsec 用户',            'IPsec User')
'eku.timestamp'          = @('时间戳',                'Time Stamping')
'eku.ocsp'               = @('OCSP 签名',            'OCSP Signing')
'eku.smartcard'          = @('智能卡登录',            'Smart Card Logon')
'eku.rdp'                = @('远程桌面身份验证',      'RDP Authentication')

# ---------------- CLI ----------------
'cli.desc'               = @('证书工具箱命令行 —— CSR 生成 / 证书与私钥合并', 'Certificate Toolkit CLI — CSR generation and certificate/key merging')
'cli.usage'              = @("用法: csrtool.ps1 <命令> [选项]`n`n命令:`n  new-csr      生成 CSR (需求文件) 与私钥`n  merge-pfx    证书 + 私钥 -> PFX`n  merge-pem    证书 + 私钥 -> 合并 PEM`n  split-pfx    PFX -> 证书 + 私钥`n  info         显示证书详情`n  verify       验证私钥与证书是否匹配`n  export-key   导出证书对应的私钥`n  scan-keys    扫描本机密钥容器 (仅 Windows)`n  serve        显示交互式菜单`n`n通用选项:`n  -Language zh|en     界面语言`n  -Help               显示本命令帮助`n`n示例:`n  csrtool.ps1 new-csr -CN nas.example.com -San dns=nas.example.com -KeyOut ./nas.key`n  csrtool.ps1 merge-pfx -Cert issued.cer -Key nas.key -Out nas.pfx -Password secret`n  csrtool.ps1 split-pfx my.pfx -Password secret -Out ./out", 'Usage: csrtool.ps1 <command> [options]`n`nCommands:`n  new-csr      Generate a CSR and a private key`n  merge-pfx    Certificate + key -> PFX`n  merge-pem    Certificate + key -> PEM bundle`n  split-pfx    PFX -> certificate + key`n  info         Show certificate details`n  verify       Check that a key matches a certificate`n  export-key   Export the private key for a certificate`n  scan-keys    List local key containers (Windows only)`n  serve        Show the interactive menu`n`nGlobal options:`n  -Language zh|en     UI language`n  -Help               Show help for a command`n`nExamples:`n  csrtool.ps1 new-csr -CN nas.example.com -San dns=nas.example.com -KeyOut ./nas.key`n  csrtool.ps1 merge-pfx -Cert issued.cer -Key nas.key -Out nas.pfx -Password secret`n  csrtool.ps1 split-pfx my.pfx -Password secret -Out ./out')
'cli.unknown.cmd'        = @('未知命令: {0}',         'Unknown command: {0}')
'cli.help.hint'          = @('用 -Help 查看用法',     'Use -Help for usage')
'cli.help.new-csr'       = @("new-csr 参数:`n  -CN <name>            通用名称 (必填)`n  -O / -OU / -L / -S / -C / -E   其它主题字段`n  -Eku <oid,...>        证书用途 OID, 逗号分隔 (默认客户端身份验证)`n  -San <type=value,...> SAN 条目: dns= / ipaddress= / email= / upn= / URL=`n  -KeySize <bits>       2048 (默认) / 3072 / 4096`n  -Hash <alg>           SHA256 (默认) / SHA384 / SHA512`n  -Out <file.csr>       CSR 输出路径`n  -KeyOut <file.key>    私钥输出路径 (不填则不导出私钥)`n  -KeyFormat <fmt>      Pkcs1 (默认) / Pkcs8`n  -Backend <name>       auto (默认) / dotnet / certreq`n  -Force                覆盖已存在的输出文件", "new-csr options:`n  -CN <name>            Common name (required)`n  -O / -OU / -L / -S / -C / -E   Other subject fields`n  -Eku <oid,...>        Usage OIDs, comma separated (default: client auth)`n  -San <type=value,...> SAN entries: dns= / ipaddress= / email= / upn= / URL=`n  -KeySize <bits>       2048 (default) / 3072 / 4096`n  -Hash <alg>           SHA256 (default) / SHA384 / SHA512`n  -Out <file.csr>       CSR output path`n  -KeyOut <file.key>    Private key output path (omit to skip)`n  -KeyFormat <fmt>      Pkcs1 (default) / Pkcs8`n  -Backend <name>       auto (default) / dotnet / certreq`n  -Force                Overwrite existing output files")
'cli.help.merge-pfx'     = @("merge-pfx 参数:`n  -Cert <file>          证书文件 (.cer/.crt/.pem)`n  -Key <file>           私钥文件; 留空则从本机证书存储 / 密钥容器查找`n  -Chain <file>         额外的证书链文件 (可选)`n  -Out <file.pfx>       输出 PFX`n  -Password <pwd>       PFX 密码`n  -KeyFormat <fmt>      导出的私钥格式 (仅导出时用)`n  -NoChain              不要把证书链打进 PFX`n  -Force                覆盖已存在的输出文件", "merge-pfx options:`n  -Cert <file>          Certificate file (.cer/.crt/.pem)`n  -Key <file>           Private key file; omitted = look in the local store / containers`n  -Chain <file>         Extra chain file (optional)`n  -Out <file.pfx>       Output PFX`n  -Password <pwd>       PFX password`n  -NoChain              Do not embed the chain`n  -Force                Overwrite existing output files")
'cli.help.merge-pem'     = @('merge-pem 参数: -Cert / -Key / -Chain / -Out / -NoChain / -Force', 'merge-pem options: -Cert / -Key / -Chain / -Out / -NoChain / -Force')
'cli.help.split-pfx'     = @("split-pfx 参数:`n  -In <file.pfx>        PFX 文件 (也可用第一个位置参数)`n  -Password <pwd>       PFX 密码`n  -Out <name>           输出前缀 (决定目录和文件名)`n  -Der                  同时输出证书 DER`n  -Force                覆盖已存在的输出文件", "split-pfx options:`n  -In <file.pfx>        PFX file (or first positional argument)`n  -Password <pwd>       PFX password`n  -Out <name>           Output prefix (directory + file name)`n  -Der                  Also write the certificate as DER`n  -Force                Overwrite existing output files")
'cli.help.info'          = @('info 参数: -Cert <file> / -Password <pwd>  (PFX 需要密码)', 'info options: -Cert <file> / -Password <pwd>  (required for PFX)')
'cli.help.verify'        = @('verify 参数: -Cert <file> / -Key <file>', 'verify options: -Cert <file> / -Key <file>')
'cli.help.export-key'    = @('export-key 参数: -Cert <file> / -Out <file.key> / -KeyFormat', 'export-key options: -Cert <file> / -Out <file.key> / -KeyFormat')
'cli.help.scan-keys'     = @('scan-keys 参数: -Machine (同时扫描机器容器, 需管理员)', 'scan-keys options: -Machine (also scan machine containers; needs admin)')
'cli.param.value'        = @('参数 {0} 需要一个值',    'Option {0} needs a value')
'cli.param.missing'      = @('缺少必需参数: {0}',     'Missing required option: {0}')
'cli.param.invalid'      = @('参数 {0} 的值不合法: {1}', 'Invalid value for {0}: {1}')
'cli.overwrite.blocked'  = @('文件已存在, 加 -Force 才会覆盖: {0}', 'File exists; pass -Force to overwrite: {0}')
'cli.ok'                 = @('完成',                  'Done')
'cli.fail'               = @('失败',                  'Failed')
'cli.csr.written'        = @('CSR: {0}  ({1} 字节)',  'CSR: {0}  ({1} bytes)')
'cli.key.written'        = @('私钥: {0}',             'Private key: {0}')
'cli.key.none'           = @('未导出私钥 (未指定 -KeyOut)', 'Private key not written (no -KeyOut)')
'cli.csr.subject'        = @('主题: {0}',             'Subject: {0}')
'cli.csr.certreq.only'   = @('certreq 后端只能在 Windows 上使用', 'The certreq backend is Windows only')
'cli.csr.certreq.keynote'= @('certreq 把私钥留在本机密钥容器 (tq-<GUID>), 不会写入文件。', 'certreq keeps the key in a local container (tq-<GUID>); it is not written to a file.')
'cli.csr.portable.note'  = @('私钥由 .NET 生成; 不写入任何证书存储。', 'The key was generated by .NET; no certificate store was touched.')
'cli.no.key.found'       = @('没有找到匹配的私钥',    'No matching private key was found')
'cli.key.from.store'     = @('私钥来源: 本机证书存储 {0}', 'Key source: local certificate store {0}')
'cli.key.from.container' = @('私钥来源: 密钥容器 {0}', 'Key source: key container {0}')
'cli.key.from.file'      = @('私钥来源: 文件 {0}',    'Key source: file {0}')
'cli.scan.header'        = @('密钥容器 (用户存储):',  'Key containers (user store):')
'cli.scan.machine'       = @('密钥容器 (机器存储):',  'Key containers (machine store):')
'cli.scan.empty'         = @('(没有找到容器)',        '(no containers found)')
'cli.scan.count'         = @('共 {0} 个容器',         '{0} container(s) total')
'cli.lang.invalid'       = @('不支持的语言: {0} (可用: zh, en)', 'Unsupported language: {0} (available: zh, en)')
'cli.pw.prompt'          = @('PFX 密码 (留空表示无密码): ', 'PFX password (empty for none): ')
'cli.confirm.overwrite'  = @('覆盖 {0} ? [y/N] ',      'Overwrite {0}? [y/N] ')

# ---------------- 交互菜单 ----------------
'menu.title'             = @('证书工具箱  (交互模式)', 'Certificate Toolkit (interactive)')
'menu.choose'            = @('请选择操作:',           'Choose an action:')
'menu.0'                 = @('生成 CSR',              'Generate a CSR')
'menu.1'                 = @('证书 + 私钥 -> PFX',    'Certificate + key -> PFX')
'menu.2'                 = @('证书 + 私钥 -> 合并 PEM', 'Certificate + key -> PEM bundle')
'menu.3'                 = @('PFX -> 拆解',           'PFX -> split')
'menu.4'                 = @('查看证书详情',          'Show certificate details')
'menu.5'                 = @('验证密钥匹配',          'Verify key match')
'menu.6'                 = @('切换语言',              'Switch language')
'menu.7'                 = @('退出',                  'Quit')
'menu.prompt'            = @('请输入编号: ',          'Enter a number: ')
'menu.invalid'           = @('无效的选择',            'Invalid choice')
'menu.label.cn'          = @('通用名称 CN: ',         'Common name CN: ')
'menu.label.san'         = @('SAN (逗号分隔, 可留空): ', 'SAN (comma separated, optional): ')
'menu.label.out'         = @('输出文件 (直接回车用默认): ', 'Output file (Enter for default): ')
'menu.label.cert'        = @('证书文件: ',            'Certificate file: ')
'menu.label.key'         = @('私钥文件 (留空=本机查找): ', 'Key file (empty = search this machine): ')
'menu.label.pfx'         = @('PFX 文件: ',            'PFX file: ')
'menu.label.pwd'         = @('密码: ',                'Password: ')
'menu.bye'               = @('再见',                  'Bye')
'menu.press.enter'       = @('按回车继续 ...',        'Press Enter to continue ...')
}

# ------------------------------------------------------------
#  语言选择
# ------------------------------------------------------------
function Get-CertSupportedLanguages { return @('zh', 'en') }

function Set-CertLanguage {
    param([string]$Language)
    $lang = ([string]$Language).Trim().ToLowerInvariant()
    if ($lang -eq '' -or $lang -eq 'auto') { $script:CertLang = $null; return (Get-CertLanguage) }
    if ($lang -like 'zh*') { $script:CertLang = 'zh'; return 'zh' }
    if ($lang -like 'en*') { $script:CertLang = 'en'; return 'en' }
    throw (Get-CertText 'cli.lang.invalid' $Language)
}

function Get-CertLanguage {
    if ($script:CertLang) { return $script:CertLang }

    $envLang = $env:CERDTOOL_LANG
    if ($envLang) {
        if ($envLang -like 'zh*') { return 'zh' }
        if ($envLang -like 'en*') { return 'en' }
    }

    $culture = ''
    try { $culture = [System.Globalization.CultureInfo]::CurrentUICulture.Name } catch { }
    if (-not $culture) { try { $culture = $PSUICulture } catch { } }
    if ($culture -like 'zh*') { return 'zh' }
    return 'en'
}

function Get-CertText {
    <# 取当前语言的文案; 找不到 key 时返回 key 本身 (便于发现遗漏) #>
    param(
        [string]$Key,
        [object]$Arg1 = $null,
        [object]$Arg2 = $null,
        [object]$Arg3 = $null,
        [object]$Arg4 = $null
    )
    $entry = $script:CertStrings[$Key]
    if (-not $entry) { return $Key }

    $lang = Get-CertLanguage
    $text = if ($lang -eq 'zh') { $entry[0] } else { $entry[1] }

    # 文案表里用单引号书写, 所以 `n 是两个字面字符; 这里统一还原成真正的换行,
    # 让 MessageBox 能正常换行 (文案里不会出现合法的反引号+n)。
    if ($text.Contains('`n')) { $text = $text.Replace('`n', "`n") }

    $fmt = @()
    foreach ($a in @($Arg1, $Arg2, $Arg3, $Arg4)) { if ($null -ne $a) { $fmt += $a } }
    if ($fmt.Count -gt 0) {
        try { return [string]::Format($text, [object[]]$fmt) } catch { return $text }
    }
    return $text
}

function Get-CertAllTextKeys {
    <# 供自检使用: 返回所有已定义的 key #>
    return @($script:CertStrings.Keys | Sort-Object)
}

function Get-CertTextTable {
    <# 供自检使用: 返回 key -> @(zh, en) 的哈希表 #>
    return $script:CertStrings
}

function T {
    param([string]$Key, [object]$A1 = $null, [object]$A2 = $null, [object]$A3 = $null, [object]$A4 = $null)
    return (Get-CertText -Key $Key -Arg1 $A1 -Arg2 $A2 -Arg3 $A3 -Arg4 $A4)
}

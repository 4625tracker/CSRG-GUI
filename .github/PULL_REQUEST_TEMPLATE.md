<!--
  提交前请确认 CI 是绿的。
  详细规则见 CONTRIBUTING.md —— 尤其是"文件编码"和"跨 PowerShell 版本"两节。
-->

## 改了什么 / What

<!-- 一两句话说明改动内容。 -->

## 为什么 / Why

<!-- 解决的问题、相关 issue 编号 (例如 Closes #12)。 -->

## 怎么验证的 / How it was tested

贴一下测试输出摘要（`RESULT: N passed, 0 failed`）。

```powershell
pwsh -NoProfile -File .\tests\selftest.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File .\tests\selftest.ps1
pwsh -NoProfile -File .\tests\clitest.ps1
```

## 检查清单 / Checklist

- [ ] 三个测试套件在 **PS 5.1 与 PS 7** 上都是 `0 failed`
- [ ] 改了界面/生成/合并流程时，跑过 `CertToolkit.ps1 -SelfTest`
- [ ] 新增或修改的用户可见文案，**中英文都补了**，且 `{n}` 占位符数量一致
- [ ] 没有使用 PS 7 专属语法（三元、`??`、`$IsWindows`），平台判断走 `Test-IsWindowsHost`
- [ ] `*.ps1` 仍是 **UTF-8 带 BOM**；`*.bat` 是 **纯 ASCII 无 BOM**；`*.sh` 是 **LF**
- [ ] 没有把私钥、证书、PFX、口令提交进仓库（`git status` 已确认）
- [ ] 没有删除或改名 `CertHelper.ps1` 暴露的旧公共函数

## 兼容性影响 / Compatibility

<!--
  是否改变了默认行为？（例如默认后端、默认输出路径、默认勾选项）
  是否影响旧脚本调用方式？是否需要在 README / 使用说明里同步更新？
  写"无"也可以，但请确认过。
-->

## 截图 / Screenshots

<!-- 界面改动请附上改动前后的截图；纯逻辑改动可以删掉这一节。 -->

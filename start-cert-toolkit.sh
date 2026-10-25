#!/usr/bin/env bash
# ------------------------------------------------------------
#  证书工具箱 / Certificate Toolkit  ——  Linux & macOS 启动器
#
#  图形界面依赖 WinForms, 只有 Windows 才有;
#  在 Linux / macOS 上这里启动的是命令行交互菜单。
#
#  用法:
#      ./start-cert-toolkit.sh                 # 交互菜单
#      ./start-cert-toolkit.sh --help          # 命令行用法
#      ./start-cert-toolkit.sh new-csr -CN a.example.com -KeyOut ./a.key
# ------------------------------------------------------------
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v pwsh >/dev/null 2>&1; then
    cat >&2 <<'MSG'
[错误] 找不到 pwsh (PowerShell 7+)。

  安装方法:
    macOS          brew install --cask powershell
    Debian/Ubuntu  https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux
    Fedora/RHEL    sudo dnf install powershell

  安装后重新运行本脚本。

[error] pwsh (PowerShell 7+) not found.
  macOS:         brew install --cask powershell
  Linux:         https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-linux
MSG
    exit 1
fi

exec pwsh -NoProfile -File "$DIR/csrtool.ps1" "$@"

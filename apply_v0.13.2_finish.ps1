$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Cache = Join-Path $Root ".godot"
if (Test-Path -LiteralPath $Cache) {
    Remove-Item -LiteralPath $Cache -Recurse -Force
    Write-Host "已删除 .godot 导入缓存。"
}
Write-Host "v0.13.2 覆盖完成，可以重新打开 project.godot。"

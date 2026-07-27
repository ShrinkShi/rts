$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ListPath = Join-Path $ProjectRoot "V0.13.1_STALE_PREVIEW_FILES.txt"

if (Test-Path -LiteralPath $ListPath) {
    $removed = 0
    Get-Content -LiteralPath $ListPath -Encoding UTF8 | ForEach-Object {
        $relative = $_.Trim()
        if ($relative.Length -eq 0) {
            return
        }
        $target = Join-Path $ProjectRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
            $removed++
        }
    }
    Write-Host "已删除废弃预览文件：$removed"
}

$GodotCache = Join-Path $ProjectRoot ".godot"
if (Test-Path -LiteralPath $GodotCache) {
    Remove-Item -LiteralPath $GodotCache -Recurse -Force
    Write-Host "已删除 Godot 导入缓存。"
}

Write-Host "v0.13.1 清理完成。现在可以重新打开 project.godot。"

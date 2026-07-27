$ErrorActionPreference = "Stop"
$ProjectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$DeleteList = Join-Path $ProjectRoot "V0.15.0_FILES_TO_DELETE.txt"
$removed = 0
if (Test-Path -LiteralPath $DeleteList) {
    Get-Content -LiteralPath $DeleteList -Encoding UTF8 | ForEach-Object {
        $relative = $_.Trim()
        if ($relative.Length -eq 0) { return }
        $target = Join-Path $ProjectRoot ($relative -replace '/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            Remove-Item -LiteralPath $target -Force
            $removed++
        }
    }
}
$GodotCache = Join-Path $ProjectRoot ".godot"
if (Test-Path -LiteralPath $GodotCache) {
    Remove-Item -LiteralPath $GodotCache -Recurse -Force
}
Write-Host "v0.15.0 增量补丁清理完成。"
Write-Host "已删除旧文件：$removed"
Write-Host "现在可以重新打开 project.godot。"

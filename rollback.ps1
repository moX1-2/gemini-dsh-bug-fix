#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string] $InstallDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedAsar = '983CA71114E6DFD353FC79AF5A1F9481A250EE64C2A3C757673029B811B23BC2'
$patchedIndex = '3AD573056333908F42A123A033CC911742CA0EF0DCB550666595057886FAC449'
$patchedPtc = '63EAA40FFF8E0F43C808DE9EED8959A9D6DB15A4B5DB42B05A74DE977AE3D39F'

function Assert-Hash {
    param([string] $Path, [string] $Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "缺少文件：$Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        throw "文件哈希不匹配：$Path。请保留现有文件并手动核对。"
    }
}

if (-not (Test-Path -LiteralPath $InstallDir -PathType Container)) {
    throw "安装目录不存在：$InstallDir"
}
$root = (Resolve-Path -LiteralPath $InstallDir).ProviderPath
$exe = Join-Path $root 'DeepSeek Harness.exe'
$resources = Join-Path $root 'resources'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
    throw "未找到 DeepSeek Harness.exe：$exe"
}
if (-not (Test-Path -LiteralPath $resources -PathType Container)) {
    throw "未找到 resources 目录：$resources"
}

$asar = Join-Path $resources 'app.asar'
$original = Join-Path $resources 'app.asar.original'
$app = Join-Path $resources 'app'
$lib = Join-Path $app 'dsh\node_modules\@deepseek-ai\dsh-tools\lib'
$archive = Join-Path $resources ('app.patched-' +
    (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N'))
$base = [IO.Path]::GetFullPath($resources).TrimEnd([char]92) + [char]92
foreach ($path in @($app, $archive)) {
    if (-not ([IO.Path]::GetFullPath($path)).StartsWith(
        $base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "目标路径超出 resources 目录：$path"
    }
}

$running = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe })
if ($running.Count -gt 0) {
    throw 'DeepSeek Harness 仍在运行。请退出窗口和托盘进程后重试。'
}
if (Test-Path -LiteralPath $asar) {
    throw 'app.asar 已存在。为避免覆盖现有版本，回退停止。'
}
if (-not (Test-Path -LiteralPath $app -PathType Container)) {
    throw '未找到已解包的 app 目录。'
}
Assert-Hash $original $expectedAsar
Assert-Hash (Join-Path $lib 'index.js') $patchedIndex
Assert-Hash (Join-Path $lib 'types\ptc.js') $patchedPtc

Move-Item -LiteralPath $app -Destination $archive
try {
    Move-Item -LiteralPath $original -Destination $asar
}
catch {
    Move-Item -LiteralPath $archive -Destination $app
    throw
}
Write-Host "回退完成。修改后的 app 目录保存在 $archive。"

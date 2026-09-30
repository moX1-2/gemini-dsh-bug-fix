#Requires -Version 5.1
param(
    [Parameter(Mandatory = $true)]
    [string] $InstallDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$expectedAsar = '983CA71114E6DFD353FC79AF5A1F9481A250EE64C2A3C757673029B811B23BC2'
$expectedSpec = 'FFA5E40505E6A2C6252BA754B380F41376A3B4962A47DAB895D968D78AF852E7'
$originalIndex = '40F47709337C3C205D4E09E647F8588F4977E66F6D52F019B3CC7EF81159D84F'
$originalPtc = '3BB2D4B127BD21DD2B17C0AE219F851C4E37420A9BAB73AB13D9FC51CA9131D5'
$patchedIndex = '3AD573056333908F42A123A033CC911742CA0EF0DCB550666595057886FAC449'
$patchedPtc = '63EAA40FFF8E0F43C808DE9EED8959A9D6DB15A4B5DB42B05A74DE977AE3D39F'
$buildCommit = '04f392c9ddd144fa426da2045178797da6db6c11'

function Assert-Hash {
    param([string] $Path, [string] $Expected)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "缺少文件：$Path"
    }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    if ($actual -ne $Expected) {
        throw "文件哈希不匹配：$Path。预期 $Expected，实际 $actual"
    }
}

function Assert-UnderResources {
    param([string] $Path)
    $base = [IO.Path]::GetFullPath($resources).TrimEnd([char]92) + [char]92
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.StartsWith($base, [StringComparison]::OrdinalIgnoreCase)) {
        throw "目标路径超出 resources 目录：$full"
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
$specPath = Join-Path $PSScriptRoot 'patch-spec.json'
$relativeLib = 'dsh\node_modules\@deepseek-ai\dsh-tools\lib'
$installedIndex = Join-Path (Join-Path $app $relativeLib) 'index.js'
$installedPtc = Join-Path (Join-Path $app $relativeLib) 'types\ptc.js'

Assert-Hash $specPath $expectedSpec

if ((-not (Test-Path -LiteralPath $asar)) -and
    (Test-Path -LiteralPath $original -PathType Leaf) -and
    (Test-Path -LiteralPath $app -PathType Container)) {
    Assert-Hash $original $expectedAsar
    Assert-Hash $installedIndex $patchedIndex
    Assert-Hash $installedPtc $patchedPtc
    Write-Host '补丁已安装，无需重复操作。'
    return
}

if ((Test-Path -LiteralPath $original) -or (Test-Path -LiteralPath $app)) {
    throw '检测到已有 app 或 app.asar.original。请先核对现有安装状态，脚本不会覆盖。'
}
Assert-Hash $asar $expectedAsar

$running = @(Get-Process -Name 'DeepSeek Harness' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -eq $exe })
if ($running.Count -gt 0) {
    throw 'DeepSeek Harness 仍在运行。请退出窗口和托盘进程后重试。'
}

$npx = (Get-Command 'npx.cmd' -ErrorAction Stop).Source
$node = (Get-Command 'node.exe' -ErrorAction Stop).Source
$stage = Join-Path $resources ('.dsh-patch-stage-' + [guid]::NewGuid().ToString('N'))
$stageApp = Join-Path $stage 'app'
Assert-UnderResources $stage
Assert-UnderResources $stageApp
New-Item -ItemType Directory -Path $stage | Out-Null
$movedOriginal = $false

try {
    & $npx --yes '@electron/asar@4.3.1' extract $asar $stageApp
    if ($LASTEXITCODE -ne 0) { throw 'app.asar 解包失败。' }

    $meta = Get-Content -LiteralPath (Join-Path $stageApp 'package.json') -Raw -Encoding UTF8 |
        ConvertFrom-Json
    if ($meta.version -ne '0.2.0-rc.2' -or $meta.dshBuildCommit -ne $buildCommit) {
        throw 'DSH 构建版本不匹配。'
    }

    $lib = Join-Path $stageApp $relativeLib
    $index = Join-Path $lib 'index.js'
    $ptc = Join-Path $lib 'types\ptc.js'
    Assert-Hash $index $originalIndex
    Assert-Hash $ptc $originalPtc

    $spec = Get-Content -LiteralPath $specPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($spec.formatVersion -ne 1 -or @($spec.files).Count -ne 2) {
        throw '补丁规则格式不匹配。'
    }
    $utf8Strict = [Text.UTF8Encoding]::new($false, $true)
    $utf8NoBom = [Text.UTF8Encoding]::new($false)
    foreach ($fileSpec in $spec.files) {
        $filePath = Join-Path $stageApp $fileSpec.path.Replace('/', '\')
        Assert-UnderResources $filePath
        Assert-Hash $filePath $fileSpec.sourceSha256
        $content = [IO.File]::ReadAllText($filePath, $utf8Strict)
        foreach ($hunk in $fileSpec.hunks) {
            $old = [string] $hunk.old
            $new = [string] $hunk.new
            if ($old.Length -eq 0) { throw "补丁规则含空匹配段：$filePath" }
            $first = $content.IndexOf($old, [StringComparison]::Ordinal)
            if ($first -lt 0) { throw "补丁片段未命中：$filePath" }
            $second = $content.IndexOf($old, $first + $old.Length, [StringComparison]::Ordinal)
            if ($second -ge 0) { throw "补丁片段命中多次：$filePath" }
            $content = $content.Substring(0, $first) + $new +
                $content.Substring($first + $old.Length)
        }
        [IO.File]::WriteAllText($filePath, $content, $utf8NoBom)
        Assert-Hash $filePath $fileSpec.targetSha256
    }

    Assert-Hash $index $patchedIndex
    Assert-Hash $ptc $patchedPtc
    & $node --check $index
    if ($LASTEXITCODE -ne 0) { throw 'index.js 语法检查失败。' }
    & $node --check $ptc
    if ($LASTEXITCODE -ne 0) { throw 'ptc.js 语法检查失败。' }

    if ((Test-Path -LiteralPath $original) -or (Test-Path -LiteralPath $app)) {
        throw '完成前发现目标路径已被占用，安装停止。'
    }
    Assert-UnderResources $app
    Move-Item -LiteralPath $asar -Destination $original
    $movedOriginal = $true
    Move-Item -LiteralPath $stageApp -Destination $app
    if (Test-Path -LiteralPath $stage) {
        Remove-Item -LiteralPath $stage -Force
    }
    Write-Host '补丁安装完成。原始归档保存在 resources\app.asar.original。请启动 DSH 并新建会话测试。'
}
catch {
    if ($movedOriginal -and
        (Test-Path -LiteralPath $original -PathType Leaf) -and
        (-not (Test-Path -LiteralPath $asar)) -and
        (-not (Test-Path -LiteralPath $app))) {
        Move-Item -LiteralPath $original -Destination $asar
    }
    Write-Warning "安装未完成。临时目录保留在 $stage，便于检查。"
    throw
}

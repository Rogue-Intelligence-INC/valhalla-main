param([ValidateSet('main','edu','student','all')][string]$Edition = 'all')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$sevenZip = 'C:\Program Files\7-Zip\7z.exe'
$sfx = Join-Path $PSScriptRoot 'sfx\7zSD.sfx'
foreach ($p in @($sevenZip, $sfx)) { if (-not (Test-Path $p)) { throw "missing: $p" } }

$editions = @{
    main    = @{ Pkg = 'VAL-DAL_A测版_安装包';       Setup = '瓦序VAL-DAL安装.exe';       Label = '瓦序 VAL-DAL';        Out = '瓦序VAL-DAL_A测版_安装程序.exe' }
    edu     = @{ Pkg = 'VAL-DAL教育版_A测版_安装包'; Setup = '瓦序VAL-DAL教育版安装.exe'; Label = '瓦序 VAL-DAL 教育版'; Out = '瓦序VAL-DAL教育版_A测版_安装程序.exe' }
    student = @{ Pkg = 'VAL-DAL学生版_A测版_安装包'; Setup = '瓦序VAL-DAL学生版安装.exe'; Label = '瓦序 VAL-DAL 学生版'; Out = '瓦序VAL-DAL学生版_A测版_安装程序.exe' }
}

function Build-One($key) {
    $e = $editions[$key]
    $pkg = Join-Path $root "release\$($e.Pkg)"
    if (-not (Test-Path (Join-Path $pkg $e.Setup))) { throw "missing package: $pkg" }
    $work = Join-Path $root "release\_sfx_$key"
    if (Test-Path $work) { Remove-Item $work -Recurse -Force }
    New-Item -ItemType Directory -Force $work | Out-Null
    $archive = Join-Path $work 'payload.7z'

    Push-Location $pkg
    & $sevenZip a -t7z -mx=5 -mmt=on $archive '*' | Out-Null
    if ($LASTEXITCODE -ne 0) { Pop-Location; throw "7z failed for $key" }
    Pop-Location

    $cfg = @(
        ';!@Install@!UTF-8!'
        "Title=`"$($e.Label) 安装`""
        'ExtractTitle="正在解压安装文件，请稍候…"'
        'ExtractDialogText="正在准备安装（约 1.7 GB），请稍候…"'
        "RunProgram=`"$($e.Setup)`""
        ';!@InstallEnd@!'
    ) -join "`r`n"
    $cfgPath = Join-Path $work 'config.txt'
    [IO.File]::WriteAllText($cfgPath, $cfg, (New-Object Text.UTF8Encoding($false)))

    $out = Join-Path $root "release\$($e.Out)"
    if (Test-Path $out) { Remove-Item $out -Force }
    $fs = [IO.File]::Create($out)
    try {
        foreach ($part in @($sfx, $cfgPath, $archive)) {
            $in = [IO.File]::OpenRead($part)
            try { $in.CopyTo($fs) } finally { $in.Dispose() }
        }
    } finally { $fs.Dispose() }
    Remove-Item $work -Recurse -Force
    Write-Host ("Built {0} ({1:N0} MB)" -f $out, ((Get-Item $out).Length / 1MB))
}

if ($Edition -eq 'all') { 'main','edu','student' | ForEach-Object { Build-One $_ } } else { Build-One $Edition }

param([ValidateSet('edu','student','all')][string]$Edition = 'all')
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$setupExe = Join-Path $PSScriptRoot 'dist\ValhallaSetup.exe'
$engineExe = 'C:\Ai\Valhalla-main\target\release\valhalla_base.exe'
$modelSrc = 'C:\Ai\models\Qwen2.5-0.5B-Instruct'
foreach ($p in @($setupExe, $engineExe, $modelSrc)) {
    if (-not (Test-Path $p)) { throw "missing: $p" }
}

$editions = @{
    edu = @{
        SrcDist = Join-Path $root 'education\dist'
        PkgName = 'VAL-DAL教育版_A测版_安装包'
        SetupName = '瓦序VAL-DAL教育版安装.exe'
        Label = '瓦序 VAL-DAL 教育版'
        Exe = 'ValhallaEdu.exe'
        DataSub = 'edu'
        Note = '教育版：对话出卷、读取试卷、批量批阅、题库。'
    }
    student = @{
        SrcDist = Join-Path $root 'student\dist'
        PkgName = 'VAL-DAL学生版_A测版_安装包'
        SetupName = '瓦序VAL-DAL学生版安装.exe'
        Label = '瓦序 VAL-DAL 学生版'
        Exe = 'ValhallaStudent.exe'
        DataSub = 'student'
        Note = '学生版：和学伴聊天、课程表、扫描课本讲解。'
    }
}

function Build-One($key) {
    $e = $editions[$key]
    if (-not (Test-Path (Join-Path $e.SrcDist $e.Exe))) { throw "missing dist exe: $($e.SrcDist)\$($e.Exe)" }
    $pkg = Join-Path $root "release\$($e.PkgName)"
    if (Test-Path $pkg) { Remove-Item $pkg -Recurse -Force }
    New-Item -ItemType Directory -Force "$pkg\payload\app", "$pkg\payload\models\Qwen2.5-0.5B-Instruct" | Out-Null

    Copy-Item $setupExe (Join-Path $pkg $e.SetupName)
    $cfg = [ordered]@{
        label = $e.Label; target = 'C:/Ai/VAL-DAL'; exe = $e.Exe
        shortcut = $e.Label; dataSub = $e.DataSub
    }
    $cfg | ConvertTo-Json | Set-Content (Join-Path $pkg 'setup.json') -Encoding utf8
    Copy-Item (Join-Path $PSScriptRoot 'dist\Qt6*.dll') $pkg
    if (Test-Path (Join-Path $PSScriptRoot 'dist\platforms')) {
        Copy-Item (Join-Path $PSScriptRoot 'dist\platforms') $pkg -Recurse
    }

    Copy-Item "$($e.SrcDist)\*" "$pkg\payload\app\" -Recurse -Force
    Get-ChildItem "$pkg\payload\app" -Filter *.pdb -Recurse -File -ErrorAction SilentlyContinue | Remove-Item -Force
    Copy-Item $engineExe "$pkg\payload\app\"
    # The engine needs the CUDA runtime next to it; not every edition's dist carries it.
    $cudaSrc = Join-Path $root 'qt\dist'
    foreach ($dll in 'cublas64_12.dll','cublasLt64_12.dll','cudart64_12.dll','curand64_10.dll','nvrtc64_120_0.dll','nvrtc-builtins64_128.dll') {
        $dest = "$pkg\payload\app\$dll"
        if (-not (Test-Path $dest)) { Copy-Item (Join-Path $cudaSrc $dll) $dest }
    }
    Copy-Item "$modelSrc\*" "$pkg\payload\models\Qwen2.5-0.5B-Instruct\"

    @(
        "$($e.Label) A测版安装包"
        "双击 $($e.SetupName) 开始安装（不需要联网，不需要管理员）。"
        $e.Note
        '全部装到 C:\Ai\VAL-DAL：程序在根目录，小模型在 models，数据在 data\<版本>，和主程序共用一份模型。'
        'Rogue Intelligence Inc. (Delaware, USA)'
    ) | Set-Content (Join-Path $pkg '安装说明.txt') -Encoding utf8

    $size = [math]::Round(((Get-ChildItem $pkg -Recurse -File | Measure-Object Length -Sum).Sum / 1MB))
    Write-Host "Packaged $key -> $pkg (${size}MB)"
}

if ($Edition -eq 'all') { Build-One 'edu'; Build-One 'student' } else { Build-One $Edition }

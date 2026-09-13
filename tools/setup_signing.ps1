# Elychron 正式签名一键配置（本地脚本，不需要管理员权限）
#
# 交互式用法（推荐，密码只在本地输入）：
#   powershell -ExecutionPolicy Bypass -File tools\setup_signing.ps1
#
# 非交互用法（自动化 / 自测用）：
#   powershell -ExecutionPolicy Bypass -File tools\setup_signing.ps1 -DryRun
#   powershell -ExecutionPolicy Bypass -File tools\setup_signing.ps1 -StorePass 'xxxxxx'
#
# 做三件事：
#   1. 生成 release keystore（如果还没有），DN 只写 Elychron，不含任何真实身份信息
#   2. 写 android/key.properties（已 gitignore，不会进仓库）
#   3. 打印下一步构建与验签命令
#
# ⚠️ 本脚本默认会等你输入密码；在**没有控制台**的环境里（stdin 被重定向）
#    它会直接报错退出而不是卡住 —— 这是刻意加的守卫（见 Test-Interactive）。
#    原因：Read-Host 不读管道，没有守卫时自动化调用会永久挂住。

[CmdletBinding()]
param(
    [string]$StorePass = '',
    [switch]$DryRun,
    [string]$KeyStorePath = 'D:\keys\elychron-release.jks',
    [string]$Alias = 'elychron'
)

$ErrorActionPreference = 'Stop'

$repoRoot = Split-Path -Parent $PSScriptRoot
$keyStore = $KeyStorePath
$keyProps = Join-Path $repoRoot 'android\key.properties'

function Test-Interactive {
    # stdin 被重定向时 Read-Host 会等一个永远不来的输入，必须提前拦住
    if ([Console]::IsInputRedirected) { return $false }
    return [Environment]::UserInteractive
}

Write-Host ''
Write-Host '=== Elychron 正式签名配置 ===' -ForegroundColor Cyan
Write-Host ''

if (-not (Get-Command keytool -ErrorAction SilentlyContinue)) {
    throw 'PATH 上找不到 keytool。请确认 JDK 已安装并在 PATH 里。'
}

$keystoreExists = Test-Path $keyStore

if ($DryRun) {
    Write-Host '[DryRun] 不做任何改动，只报告将要做什么：' -ForegroundColor Yellow
    Write-Host ("  keystore         : {0}  ({1})" -f $keyStore, $(if ($keystoreExists) { '已存在，将复用' } else { '不存在，将新建' }))
    Write-Host ("  key.properties   : {0}" -f $keyProps)
    Write-Host ("  alias            : {0}" -f $Alias)
    Write-Host  "  DN               : CN=Elychron, O=Elychron, C=CN"
    Write-Host ("  会写文件吗       : {0}" -f $(if ($keystoreExists) { '只写 key.properties' } else { '写 key.properties + 生成 keystore' }))
    Write-Host ''
    Write-Host 'DryRun 结束，没有改动任何文件 ✓' -ForegroundColor Green
    return
}

if ($keystoreExists -and -not (Test-Interactive)) {
    throw "keystore 已存在（$keyStore），非交互模式下无法询问是否复用它。请改用 -DryRun 查看，或先手动处理它。"
}

if ($keystoreExists) {
    Write-Host "keystore 已存在：$keyStore" -ForegroundColor Yellow
    $reuse = Read-Host '直接回车＝复用它并继续／输入 regen＝中止让我手动处理'
    if ($reuse -eq 'regen') {
        throw "请先手动删除或改名 $keyStore 再重跑（脚本不替你做不可逆的删除）"
    }
}

$plain = $StorePass
if ([string]::IsNullOrWhiteSpace($plain)) {
    if (-not (Test-Interactive)) {
        throw '需要密码但当前 stdin 被重定向（无法交互）。请用 -StorePass 传入，或加 -DryRun 只预览。'
    }
    Write-Host ''
    Write-Host '请输入一个密码（库密码与 key 密码用同一个，至少 6 位）。'
    Write-Host '⚠️ 这个密码丢了就再也发不了升级包，请立刻存进密码管理器。' -ForegroundColor Yellow
    $secure = Read-Host '密码' -AsSecureString
    $plain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
if ($plain.Length -lt 6) { throw '密码至少 6 位。' }

try {
    if (-not $keystoreExists) {
        New-Item -ItemType Directory -Force -Path (Split-Path $keyStore -Parent) | Out-Null
        Write-Host ''
        Write-Host '正在生成 keystore...' -ForegroundColor Cyan
        # DN 保持中性：它会写进 APK 的签名证书，任何人 apksigner 都能看到
        & keytool -genkeypair -v `
            -keystore $keyStore `
            -storetype PKCS12 `
            -keyalg RSA -keysize 2048 -validity 10000 `
            -alias $Alias `
            -dname 'CN=Elychron, O=Elychron, C=CN' `
            -storepass $plain -keypass $plain
        if ($LASTEXITCODE -ne 0) { throw "keytool 失败（退出码 $LASTEXITCODE）" }
    }

    Write-Host ''
    Write-Host '正在写 android/key.properties ...' -ForegroundColor Cyan
    $content = @(
        '# 由 tools/setup_signing.ps1 生成；本文件已在 android/.gitignore 中，不会进仓库',
        "storePassword=$plain",
        "keyPassword=$plain",
        "keyAlias=$Alias",
        "storeFile=$($keyStore -replace '\\', '/')"
    ) -join "`n"
    [IO.File]::WriteAllText($keyProps, $content + "`n", (New-Object Text.UTF8Encoding($false)))

    Write-Host ''
    Write-Host '完成 ✓' -ForegroundColor Green
    Write-Host ''
    Write-Host '接下来（在仓库的 ASCII 路径下构建）：' -ForegroundColor Cyan
    Write-Host '  cd D:\celechron-mod\Celechron'
    Write-Host '  & ''D:\flutter\bin\flutter.bat'' build apk --release --target-platform android-arm64 --no-tree-shake-icons'
    Write-Host '  & ''C:\Android\Sdk\build-tools\36.0.0\apksigner.bat'' verify --print-certs build\app\outputs\flutter-apk\app-release.apk'
    Write-Host ''
    Write-Host '验签应看到 CN=Elychron（不是 CN=Android Debug）。' -ForegroundColor Yellow
    Write-Host '然后立刻把这两样备份到两处（例如密码管理器 + 移动硬盘）：' -ForegroundColor Yellow
    Write-Host "  1) $keyStore"
    Write-Host '  2) 上面那个密码'
} finally {
    $plain = $null
    [GC]::Collect()
}

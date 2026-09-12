# 把设计稿（黑白像素风 logo）转成 iOS App 图标：
#   - 输出 1024x1024、不透明（iOS 图标不能带透明通道）
#   - 二值化：把 JPEG 压缩噪点清掉，得到干脆的黑白像素边缘
#   - 如果源图不是 1024x1024，用最近邻整数倍放大并居中留白（像素画不能被平滑插值）
#   - 同时生成深色模式版本（黑白反相）
# 用法： powershell -ExecutionPolicy Bypass -File Tools/make-icon-from-logo.ps1
param(
    [string]$Source = "Design\AppIcon-source.jpeg",
    [string]$OutDir = "EPUBTranslator\Assets.xcassets\AppIcon.appiconset",
    [int]$Threshold = 128
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Drawing

$sourcePath = (Resolve-Path -LiteralPath $Source).Path
$img = [System.Drawing.Image]::FromFile($sourcePath)
$sw = $img.Width
$sh = $img.Height

$size = 1024
$canvas = New-Object System.Drawing.Bitmap($size, $size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$g = [System.Drawing.Graphics]::FromImage($canvas)
$g.Clear([System.Drawing.Color]::White)
$g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::NearestNeighbor
$g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::Half

if ($sw -eq $size -and $sh -eq $size) {
    $g.DrawImageUnscaled($img, 0, 0)
    Write-Host "源图已是 1024x1024，1:1 使用"
}
else {
    # 像素画优先整数倍放大；源图比 1024 还大时退化为按比例缩放到最大
    $scale = [Math]::Max(1, [Math]::Floor($size / [Math]::Max($sw, $sh)))
    $dw = $sw * $scale
    $dh = $sh * $scale
    if ($dw -gt $size -or $dh -gt $size) {
        $scale = [double]$size / [Math]::Max($sw, $sh)
        $dw = [int][Math]::Round($sw * $scale)
        $dh = [int][Math]::Round($sh * $scale)
    }
    $dx = [int](($size - $dw) / 2)
    $dy = [int](($size - $dh) / 2)
    Write-Host ("源图 {0}x{1} → 缩放 {2}x → 居中放在 {3},{4}" -f $sw, $sh, $scale, $dx, $dy)
    $g.DrawImage($img, $dx, $dy, $dw, $dh)
}
$g.Dispose()
$img.Dispose()

function Convert-ToBlackAndWhite {
    param(
        [System.Drawing.Bitmap]$Bitmap,
        [bool]$Invert,
        [int]$Limit
    )
    $rect = New-Object System.Drawing.Rectangle(0, 0, $Bitmap.Width, $Bitmap.Height)
    $data = $Bitmap.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadWrite, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $count = $data.Stride * $data.Height
    $bytes = New-Object byte[] $count
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $bytes, 0, $count)

    for ($i = 0; $i -lt $count; $i += 4) {
        $lum = 0.299 * $bytes[$i + 2] + 0.587 * $bytes[$i + 1] + 0.114 * $bytes[$i]
        $value = if ($lum -ge $Limit) { 255 } else { 0 }
        if ($Invert) { $value = 255 - $value }
        $bytes[$i] = $value
        $bytes[$i + 1] = $value
        $bytes[$i + 2] = $value
        $bytes[$i + 3] = 255
    }

    [System.Runtime.InteropServices.Marshal]::Copy($bytes, 0, $data.Scan0, $count)
    $Bitmap.UnlockBits($data)
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Convert-ToBlackAndWhite -Bitmap $canvas -Invert $false -Limit $Threshold
$lightPath = Join-Path $OutDir "AppIcon-1024.png"
$canvas.Save($lightPath, [System.Drawing.Imaging.ImageFormat]::Png)

Convert-ToBlackAndWhite -Bitmap $canvas -Invert $true -Limit $Threshold
$darkPath = Join-Path $OutDir "AppIcon-1024-dark.png"
$canvas.Save($darkPath, [System.Drawing.Imaging.ImageFormat]::Png)

$canvas.Dispose()

foreach ($path in @($lightPath, $darkPath)) {
    $info = Get-Item -LiteralPath $path
    Write-Host ("  {0}  {1} KB" -f $info.Name, [Math]::Round($info.Length / 1KB))
}

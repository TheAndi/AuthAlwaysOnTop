# Generates AuthAlwaysOnTop.ico from scratch with GDI+.
#
# Original artwork: stylised fingerprint ridges on a rounded badge. Drawn from
# primitives here, so the provenance is unambiguous and it carries the same
# license as the rest of the project. Deliberately NOT a copy of any vendor's
# artwork - a fingerprint as such is a generic motif, a specific logo is not.
#
# Each size is drawn at its own scale rather than downsampled: at 16 px the
# outer ridge is dropped and strokes are widened, otherwise the tray icon
# turns to mush.

param(
    [Parameter(Mandatory = $true)][string]$OutIco,
    [string]$OutPreview = ""
)

Add-Type -AssemblyName System.Drawing

$SIZES_BMP = @(16, 20, 24, 32, 40, 48, 64)
$SIZES_PNG = @(128, 256)

function New-IconBitmap {
    param([int]$Size)

    $bmp = New-Object System.Drawing.Bitmap($Size, $Size, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.Clear([System.Drawing.Color]::Transparent)

    $s = [double]$Size

    # --- rounded badge -----------------------------------------------------
    # A filled badge keeps the glyph readable on both light and dark taskbars;
    # a bare white glyph would disappear in light theme.
    $inset  = [Math]::Max(0.5, $s * 0.03)
    $radius = $s * 0.22
    $rect   = New-Object System.Drawing.RectangleF($inset, $inset, ($s - 2 * $inset), ($s - 2 * $inset))

    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $radius * 2
    $path.AddArc($rect.Left, $rect.Top, $d, $d, 180, 90)
    $path.AddArc($rect.Right - $d, $rect.Top, $d, $d, 270, 90)
    $path.AddArc($rect.Right - $d, $rect.Bottom - $d, $d, $d, 0, 90)
    $path.AddArc($rect.Left, $rect.Bottom - $d, $d, $d, 90, 90)
    $path.CloseFigure()

    $brush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        (New-Object System.Drawing.PointF(0, 0)),
        (New-Object System.Drawing.PointF($s, $s)),
        [System.Drawing.Color]::FromArgb(255, 0, 145, 255),
        [System.Drawing.Color]::FromArgb(255, 0, 80, 179))
    $g.FillPath($brush, $path)
    $brush.Dispose()
    $path.Dispose()

    # --- the two motifs sharing the same strokes ---------------------------
    # Two eyes above a stack of nested upward arcs. The innermost arc is a
    # mouth, the outer ones are ridges, and they are the same strokes: the
    # mark reads as a smile and as a fingerprint at once.
    #
    # An earlier attempt wrapped ridges over and around a face. That never
    # works - anything arcing over a head and down past the cheeks reads as
    # hair long before it reads as a ridge pattern. Keeping every arc below
    # the eyes is what removes the ambiguity.
    $cx = $s * 0.5
    $ay = $s * 0.405                    # centre the arcs share

    # Arcs are shed as the icon shrinks; the innermost one is the mouth and
    # always survives, so the silhouette stays the same mark at every size.
    if ($Size -le 20) {
        $arcs = @(0.150)
        $strokeRatio = 0.100
    } elseif ($Size -le 32) {
        $arcs = @(0.135, 0.245)
        $strokeRatio = 0.082
    } elseif ($Size -le 48) {
        $arcs = @(0.125, 0.215, 0.305)
        $strokeRatio = 0.060
    } else {
        $arcs = @(0.118, 0.187, 0.256, 0.325)
        $strokeRatio = 0.047
    }

    $stroke = [Math]::Max(1.0, $s * $strokeRatio)
    $ink = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
    $pen = New-Object System.Drawing.Pen($ink, [float]$stroke)
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $fill = New-Object System.Drawing.SolidBrush($ink)

    # Slightly wider than tall, the way a smile is.
    foreach ($r in $arcs) {
        $ry = $s * [double]$r
        $rx = $ry * 1.06
        $g.DrawArc($pen, [float]($cx - $rx), [float]($ay - $ry), [float]($rx * 2), [float]($ry * 2),
                   [float]22, [float]136)
    }

    # Eyes, clear of the topmost arc ends.
    if ($Size -le 20) { $eyeDx = $s * 0.150 } else { $eyeDx = $s * 0.138 }
    $eyeY = $s * 0.318
    $eyeR = [Math]::Max(0.9, $s * 0.052)
    foreach ($sx in @(-1, 1)) {
        $ex = $cx + $sx * $eyeDx
        $g.FillEllipse($fill, [float]($ex - $eyeR), [float]($eyeY - $eyeR),
                       [float]($eyeR * 2), [float]($eyeR * 2))
    }

    $fill.Dispose()
    $pen.Dispose()
    $g.Dispose()
    return $bmp
}

function Get-BgraRows {
    param([System.Drawing.Bitmap]$Bmp)

    $w = $Bmp.Width; $h = $Bmp.Height
    $rect = New-Object System.Drawing.Rectangle(0, 0, $w, $h)
    $data = $Bmp.LockBits($rect, [System.Drawing.Imaging.ImageLockMode]::ReadOnly,
                          [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $stride = $data.Stride
    $buf = New-Object byte[] ($stride * $h)
    [System.Runtime.InteropServices.Marshal]::Copy($data.Scan0, $buf, 0, $buf.Length)
    $Bmp.UnlockBits($data)

    return @{ Buffer = $buf; Stride = $stride; Width = $w; Height = $h }
}

# 32-bit DIB entry: BITMAPINFOHEADER with doubled height, bottom-up BGRA,
# then a 1-bpp AND mask. The mask is all zero - alpha does the real work, but
# the structure has to be there or the entry is malformed.
function New-DibEntry {
    param([System.Drawing.Bitmap]$Bmp)

    $px = Get-BgraRows -Bmp $Bmp
    $w = $px.Width; $h = $px.Height
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)

    $bw.Write([uint32]40)          # biSize
    $bw.Write([int32]$w)           # biWidth
    $bw.Write([int32]($h * 2))     # biHeight (XOR + AND)
    $bw.Write([uint16]1)           # biPlanes
    $bw.Write([uint16]32)          # biBitCount
    $bw.Write([uint32]0)           # biCompression = BI_RGB
    $bw.Write([uint32]0)           # biSizeImage
    $bw.Write([int32]0); $bw.Write([int32]0)
    $bw.Write([uint32]0); $bw.Write([uint32]0)

    for ($y = $h - 1; $y -ge 0; $y--) {
        $off = $y * $px.Stride
        $bw.Write($px.Buffer, $off, $w * 4)
    }

    $maskStride = [int](([Math]::Floor(($w + 31) / 32)) * 4)
    $maskRow = New-Object byte[] $maskStride
    for ($y = 0; $y -lt $h; $y++) { $bw.Write($maskRow, 0, $maskStride) }

    $bw.Flush()
    $bytes = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    return $bytes
}

function New-PngEntry {
    param([System.Drawing.Bitmap]$Bmp)
    $ms = New-Object System.IO.MemoryStream
    $Bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $bytes = $ms.ToArray()
    $ms.Dispose()
    return $bytes
}

# --- build all entries -----------------------------------------------------
$entries = @()
$bitmaps = @{}

foreach ($sz in ($SIZES_BMP + $SIZES_PNG)) {
    $bmp = New-IconBitmap -Size $sz
    $bitmaps[$sz] = $bmp
    if ($SIZES_PNG -contains $sz) { $data = New-PngEntry -Bmp $bmp } else { $data = New-DibEntry -Bmp $bmp }
    $entries += [pscustomobject]@{ Size = $sz; Data = $data }
}

# --- assemble the .ico -----------------------------------------------------
$ms = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($ms)

$bw.Write([uint16]0)                  # idReserved
$bw.Write([uint16]1)                  # idType = icon
$bw.Write([uint16]$entries.Count)

$offset = 6 + 16 * $entries.Count
foreach ($e in $entries) {
    if ($e.Size -ge 256) { $dim = 0 } else { $dim = $e.Size }
    $bw.Write([byte]$dim)             # bWidth
    $bw.Write([byte]$dim)             # bHeight
    $bw.Write([byte]0)                # bColorCount
    $bw.Write([byte]0)                # bReserved
    $bw.Write([uint16]1)              # wPlanes
    $bw.Write([uint16]32)             # wBitCount
    $bw.Write([uint32]$e.Data.Length)
    $bw.Write([uint32]$offset)
    $offset += $e.Data.Length
}
foreach ($e in $entries) { $bw.Write($e.Data, 0, $e.Data.Length) }

$bw.Flush()
[System.IO.File]::WriteAllBytes($OutIco, $ms.ToArray())
$bw.Dispose(); $ms.Dispose()

Write-Output ("wrote {0} ({1} entries, {2:N0} bytes)" -f $OutIco, $entries.Count, (Get-Item $OutIco).Length)
foreach ($e in $entries) { Write-Output ("  {0,3}x{0,-3} {1,7:N0} bytes  {2}" -f $e.Size, $e.Data.Length, $(if ($SIZES_PNG -contains $e.Size) { "PNG" } else { "DIB" })) }

# --- preview strip ---------------------------------------------------------
if ($OutPreview -ne "") {
    $shown = @(256, 128, 64, 48, 32, 24, 20, 16)
    $pad = 16
    $totalW = $pad
    foreach ($sz in $shown) { $totalW += $sz + $pad }
    $totalH = 256 + 2 * $pad + 40

    $sheet = New-Object System.Drawing.Bitmap($totalW, ($totalH * 2), [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($sheet)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias

    # top half on light, bottom half on dark - the two taskbar themes
    $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,243,243,243))), 0, 0, $totalW, $totalH)
    $g.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255,32,32,32))), 0, $totalH, $totalW, $totalH)

    $font = New-Object System.Drawing.Font("Segoe UI", 11)
    $x = $pad
    foreach ($sz in $shown) {
        $y = $pad + (256 - $sz)
        $g.DrawImage($bitmaps[$sz], $x, $y, $sz, $sz)
        $g.DrawImage($bitmaps[$sz], $x, ($totalH + $y), $sz, $sz)
        $g.DrawString("${sz}px", $font, [System.Drawing.Brushes]::Black, $x, ($pad + 256 + 8))
        $g.DrawString("${sz}px", $font, [System.Drawing.Brushes]::White, $x, ($totalH + $pad + 256 + 8))
        $x += $sz + $pad
    }
    $g.Dispose()
    $sheet.Save($OutPreview, [System.Drawing.Imaging.ImageFormat]::Png)
    $sheet.Dispose()
    Write-Output ("preview: {0}" -f $OutPreview)
}

foreach ($b in $bitmaps.Values) { $b.Dispose() }

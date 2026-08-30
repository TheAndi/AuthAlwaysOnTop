# Generates AuthAlwaysOnTop.ico from scratch with GDI+.
#
# Original artwork: the letters A, O and T set out as a face -
#
#     A   T
#       O
#
# Drawn from primitives here rather than in an editor, so the provenance is
# reproducible and it carries the same license as the rest of the project.
# Nothing is traced from anyone else's logo or icon set.
#
# Each size is drawn at its own scale rather than downsampled, and the tray
# sizes get their own proportions and no badge, because scaling the large
# layout down leaves a smudge in the middle of an empty square.

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

    # Notification area icons sit among free-standing glyphs on a transparent
    # ground; a filled tile there reads as an app icon someone pasted into the
    # tray. So the badge is only drawn at the sizes Explorer and the file
    # properties dialog use, and the small entries are a coloured glyph on
    # nothing. Blue rather than white, because the taskbar is not always dark.
    $useBadge = ($Size -ge 40)

    if ($useBadge) {
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
    }

    # --- A O T arranged as a face ------------------------------------------
    # The eyes are the letters A and T, the mouth is an O:
    #
    #     A   T
    #       O
    #
    # Two marks up top and a round one below is enough for the eye to resolve
    # a face before it resolves the lettering, so the icon still reads at a
    # glance and spells the application out on a second look.
    $cx = $s * 0.5

    # Proportion decides which reading wins. Letters set large, tall and far
    # apart stop being eyes and become a monogram in a box, so they are kept
    # roughly square and close together - each one then occupies a round-ish
    # patch that the eye takes for an eye before it parses the letter.
    #
    # There is a floor on how squat they can go: the stroke has to stay well
    # under the letter height or the A's counter closes up and its crossbar
    # disappears into the strokes around it.
    # At the badge sizes there are pixels to spare, so the letters are set
    # small against a full-size mouth. Small marks set a little further apart
    # read as a pair of eyes; large ones sitting close read as the word "AT".
    # The stroke thins with them to keep the ratio that leaves the A's
    # crossbar standing.
    if ($useBadge) {
        $eyeDx = 0.176; $eyeY = 0.328
        $moY   = 0.660; $moW  = 0.205; $moTop = 0.086; $moBot = 0.146
        if ($Size -lt 64) {
            # 0.038 of 40 px is a 1.5 px line - too frail. Letters and stroke
            # both grow, keeping the ratio between them.
            $letterW = 0.165; $letterH = 0.155
            $strokeRatio = 0.044
        } else {
            $letterW = 0.150; $letterH = 0.140
            $strokeRatio = 0.038
        }
    } else {
        # No tile to sit in, so the mark grows into the whole square and the
        # stroke thickens as the pixels run out.
        $letterW = 0.212; $letterH = 0.196
        $eyeDx   = 0.188; $eyeY    = 0.322
        $moY     = 0.706; $moW     = 0.230; $moTop = 0.100; $moBot = 0.168
        if     ($Size -le 16) { $strokeRatio = 0.120 }
        elseif ($Size -le 20) { $strokeRatio = 0.108 }
        elseif ($Size -le 24) { $strokeRatio = 0.098 }
        else                  { $strokeRatio = 0.086 }
    }

    $stroke = [Math]::Max(1.0, $s * $strokeRatio)

    if ($useBadge) {
        $ink = [System.Drawing.Color]::FromArgb(255, 255, 255, 255)
        $pen = New-Object System.Drawing.Pen($ink, [float]$stroke)
    } else {
        # Bright enough to hold up on a light taskbar, saturated enough not to
        # wash out on a dark one.
        $glyphBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
            (New-Object System.Drawing.PointF(0, 0)),
            (New-Object System.Drawing.PointF(0, $s)),
            [System.Drawing.Color]::FromArgb(255, 92, 190, 255),
            [System.Drawing.Color]::FromArgb(255, 46, 144, 245))
        $pen = New-Object System.Drawing.Pen($glyphBrush, [float]$stroke)
    }
    $pen.StartCap = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.EndCap   = [System.Drawing.Drawing2D.LineCap]::Round
    $pen.LineJoin = [System.Drawing.Drawing2D.LineJoin]::Round

    $lw = $s * $letterW
    $lh = $s * $letterH

    # A, left eye
    $aCx = $cx - $s * $eyeDx
    $aCy = $s * $eyeY
    $g.DrawLine($pen, [float]($aCx - $lw / 2), [float]($aCy + $lh / 2), [float]$aCx, [float]($aCy - $lh / 2))
    $g.DrawLine($pen, [float]$aCx, [float]($aCy - $lh / 2), [float]($aCx + $lw / 2), [float]($aCy + $lh / 2))
    # Crossbar low enough that a fat stroke does not weld it to the apex.
    $barY = $aCy + $lh * 0.16
    $g.DrawLine($pen, [float]($aCx - $lw * 0.29), [float]$barY, [float]($aCx + $lw * 0.29), [float]$barY)

    # T, right eye
    $tCx = $cx + $s * $eyeDx
    $tCy = $s * $eyeY
    $g.DrawLine($pen, [float]($tCx - $lw / 2), [float]($tCy - $lh / 2), [float]($tCx + $lw / 2), [float]($tCy - $lh / 2))
    $g.DrawLine($pen, [float]$tCx, [float]($tCy - $lh / 2), [float]$tCx, [float]($tCy + $lh / 2))

    # O, the mouth. Built from four quadrant beziers, not two halves: joining
    # two half-curves at the left and right extremes leaves a cusp there, and
    # a shape with pointed ends is an almond - it reads as an eye, not a
    # mouth. Quadrants keep the tangent vertical at both ends, so the ends
    # stay round while the top can still be shallower than the bottom.
    # 0.5523 is the usual cubic-bezier circle constant.
    $mw = $s * $moW
    $mt = $s * $moTop
    $mb = $s * $moBot
    $my = $s * $moY
    $kc = 0.5523

    $mp = New-Object System.Drawing.Drawing2D.GraphicsPath
    # left -> top
    $mp.AddBezier([float]($cx - $mw), [float]$my,
                  [float]($cx - $mw), [float]($my - $mt * $kc),
                  [float]($cx - $mw * $kc), [float]($my - $mt),
                  [float]$cx, [float]($my - $mt))
    # top -> right
    $mp.AddBezier([float]$cx, [float]($my - $mt),
                  [float]($cx + $mw * $kc), [float]($my - $mt),
                  [float]($cx + $mw), [float]($my - $mt * $kc),
                  [float]($cx + $mw), [float]$my)
    # right -> bottom
    $mp.AddBezier([float]($cx + $mw), [float]$my,
                  [float]($cx + $mw), [float]($my + $mb * $kc),
                  [float]($cx + $mw * $kc), [float]($my + $mb),
                  [float]$cx, [float]($my + $mb))
    # bottom -> left
    $mp.AddBezier([float]$cx, [float]($my + $mb),
                  [float]($cx - $mw * $kc), [float]($my + $mb),
                  [float]($cx - $mw), [float]($my + $mb * $kc),
                  [float]($cx - $mw), [float]$my)
    $mp.CloseFigure()
    $g.DrawPath($pen, $mp)
    $mp.Dispose()

    # No second ring inside the O: a dot in the middle of it turns the mouth
    # into an eye and the face reading collapses.

    $pen.Dispose()
    if (-not $useBadge) { $glyphBrush.Dispose() }
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

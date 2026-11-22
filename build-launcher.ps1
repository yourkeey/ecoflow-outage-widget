$ErrorActionPreference='Stop'
Add-Type -AssemblyName System.Drawing
$sizes=@(16,24,32,48,64,128)
$images=@()
foreach($size in $sizes){
 $bitmap=[Drawing.Bitmap]::new($size,$size)
 $graphics=[Drawing.Graphics]::FromImage($bitmap)
 $graphics.SmoothingMode=[Drawing.Drawing2D.SmoothingMode]::AntiAlias
 $graphics.Clear([Drawing.Color]::Transparent)
 $graphics.ScaleTransform(($size/64.0),($size/64.0))
 $path=[Drawing.Drawing2D.GraphicsPath]::new()
 $path.AddArc(2,2,24,24,180,90);$path.AddArc(38,2,24,24,270,90)
 $path.AddArc(38,38,24,24,0,90);$path.AddArc(2,38,24,24,90,90);$path.CloseFigure()
 $dark=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#141C28'))
 $mint=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml('#7CE9C2'))
 $pen=[Drawing.Pen]::new([Drawing.ColorTranslator]::FromHtml('#7CE9C2'),3)
 $graphics.FillPath($dark,$path)
 $graphics.DrawRectangle($pen,14,19,34,28)
 $graphics.FillRectangle($mint,49,27,4,12)
 $bolt=[Drawing.PointF[]]@([Drawing.PointF]::new(33,21),[Drawing.PointF]::new(23,35),[Drawing.PointF]::new(30,35),[Drawing.PointF]::new(28,45),[Drawing.PointF]::new(40,30),[Drawing.PointF]::new(33,30))
 $graphics.FillPolygon($mint,$bolt)
 $stream=[IO.MemoryStream]::new()
 $bitmap.Save($stream,[Drawing.Imaging.ImageFormat]::Png)
 $images+=,[byte[]]$stream.ToArray()
 if($size -eq 128){$bitmap.Save((Join-Path $PSScriptRoot 'launcher-preview.png'),[Drawing.Imaging.ImageFormat]::Png)}
 $stream.Dispose();$graphics.Dispose();$path.Dispose();$dark.Dispose();$mint.Dispose();$pen.Dispose();$bitmap.Dispose()
}
$icon=Join-Path $PSScriptRoot 'EcoFlow Widget.ico'
$file=[IO.File]::Create($icon);$writer=[IO.BinaryWriter]::new($file)
try{
 $writer.Write([uint16]0);$writer.Write([uint16]1);$writer.Write([uint16]$sizes.Count)
 $offset=6+16*$sizes.Count
 for($i=0;$i -lt $sizes.Count;$i++){
  $writer.Write([byte]$sizes[$i]);$writer.Write([byte]$sizes[$i]);$writer.Write([byte]0);$writer.Write([byte]0)
  $writer.Write([uint16]1);$writer.Write([uint16]32);$writer.Write([uint32]$images[$i].Length);$writer.Write([uint32]$offset)
  $offset+=$images[$i].Length
 }
 foreach($bytes in $images){$writer.Write([byte[]]$bytes)}
}finally{$writer.Dispose();$file.Dispose()}
$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
$exe=Join-Path $PSScriptRoot 'EcoFlow Widget.exe'
& $compiler /nologo /target:winexe /optimize+ "/out:$exe" "/win32icon:$icon" /reference:System.Windows.Forms.dll (Join-Path $PSScriptRoot 'Launcher.cs')
if($LASTEXITCODE -ne 0){throw 'Launcher compilation failed'}
$metadata=[Diagnostics.FileVersionInfo]::GetVersionInfo($exe)
if($metadata.ProductName -ne 'EcoFlow Widget' -or $metadata.FileDescription -ne 'EcoFlow Widget'){throw 'Incorrect launcher metadata'}
'Built EcoFlow Widget.exe with custom icon and product metadata.'

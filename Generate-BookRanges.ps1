param(
 [string]$Catalog = (Join-Path $PSScriptRoot 'LongYinLiZhiZhuan-books.json'),
 [string]$OutputDirectory = (Join-Path (Split-Path $Catalog -Parent) 'book-ranges')
)
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$data = Get-Content -LiteralPath $Catalog -Raw -Encoding UTF8 | ConvertFrom-Json
if ($data.schema -ne 'longyi.book-catalog' -or $data.books.Count -ne $data.count) { throw 'Invalid book catalog' }
[void][IO.Directory]::CreateDirectory($OutputDirectory)
function Contains-Cell($r, [int]$x, [int]$y) {
 $ax=[Math]::Abs($x); $ay=[Math]::Abs($y)
 switch ([int]$r.type) {
  0 { $d=$ax+$ay }
  1 { $d=[Math]::Max($ax,$ay) }
  2 { if ($x -ne 0 -and $y -ne 0) { return $false }; $d=$ax+$ay }
  3 { if ($ax -ne $ay) { return $false }; $d=$ax }
  default { return $false }
 }
 return ($d -ge $r.min -and $d -le $r.max)
}
function Contains-Direction($r, [int]$forward, [int]$side) {
 # Reproduced from GameAssembly grid functions, not inferred from enum names.
 # Canonical facing: east; type 6 uses southeast, rotated to four diagonals.
 $start=if ($r.type -eq 6) {[int]$r.min} else {[Math]::Max(1,[int]$r.min)}
 if ($forward -lt $start -or $forward -gt $r.max) {return $false}
 switch ([int]$r.type) {
  4 {return $side -eq 0} # RVA 5E7BB0
  5 {return [Math]::Abs($side) -le ($forward-1)} # RVA 5E80C0
  6 {return $side -eq $forward} # RVA 5E7E90
  8 { # RVA 5E76C0: near/far endpoints narrow, interior is 3 cells wide.
   $halfWidth=if ($forward -eq 1 -or $forward -eq $r.max) {0} else {1}
   return [Math]::Abs($side) -le $halfWidth
  }
  default {return $false}
 }
}
$brushes=@{}
foreach ($entry in @{empty='#E6EAED';attack='#9AC6E7';effect='#EB858B';facing='#A93240';both='#A887C2';ink='#2B3544'}.GetEnumerator()) {
 $brushes[$entry.Key]=[Drawing.SolidBrush]::new([Drawing.ColorTranslator]::FromHtml($entry.Value))
}
$pen=[Drawing.Pen]::new($brushes.ink.Color,1)
$count=0
$directionCount=0
$unsupported=@()
try {
 foreach ($book in $data.books) {
  $id=[int]$book.skill_id
  if ($id -lt 0 -or $id -gt 1000000) { throw 'Invalid skill ID' }
  $bitmap=[Drawing.Bitmap]::new(190,190);$g=[Drawing.Graphics]::FromImage($bitmap)
  try {
   $g.Clear([Drawing.ColorTranslator]::FromHtml('#F5F8FA'))
   $ranges=$book.range_data;$reach=0
   foreach ($r in $ranges.attack) { $reach=[Math]::Max($reach,[int]$r.max) }
   $directional=($null -ne $ranges -and $ranges.attack.Count -eq 1 -and $ranges.attack[0].type -eq 4 -and $reach -eq 0 -and $ranges.damage.type -in @(4,5,6,8))
   if ($directional) {$directionCount++}
   $supported=($null -ne $ranges -and ($directional -or (($ranges.attack | Where-Object {$_.type -notin @(0,1,2,3)}).Count -eq 0 -and $ranges.damage.type -in @(0,1,2,3,7))))
   if (-not $supported) {$unsupported+=$id}
   if ($supported -and ($reach -gt 0 -or $ranges.damage.max -gt 0)) {
    $radius=[Math]::Min(10,[Math]::Max(3,$reach+[int]$ranges.damage.max));$size=2*$radius+1
    if ($directional) {$radius=[Math]::Min(10,[Math]::Max(1,[int]$ranges.damage.max));$size=2*$radius+1}
    $cell=[int][Math]::Floor(182/$size);$offset=[int][Math]::Floor((190-$cell*$size)/2)
    $targets=@();$cells=@()
    for ($y=-$radius;$y -le $radius;$y++) { for ($x=-$radius;$x -le $radius;$x++) {
     $attack=$false
     foreach ($r in $ranges.attack) { if (Contains-Cell $r $x $y) {$attack=$true;break} }
     $c=[pscustomobject]@{x=$x;y=$y;attack=$attack;distance=([Math]::Abs($x)+[Math]::Abs($y))}
     $cells+=$c;if ($attack) {$targets+=$c}
    }}
    $target=$targets | Sort-Object distance,y,x | Select-Object -First 1
    foreach ($c in $cells) {
     $effect=$false
     if ($ranges.damage.type -eq 7) {$effect=$c.attack}
     elseif ($ranges.damage.type -le 3 -and $null -ne $target) {$effect=Contains-Cell $ranges.damage ($c.x-$target.x) ($c.y-$target.y)}
     elseif ($directional) {
      $effect=(Contains-Direction $ranges.damage $c.x $c.y) -or (Contains-Direction $ranges.damage (-$c.y) $c.x) -or (Contains-Direction $ranges.damage (-$c.x) (-$c.y)) -or (Contains-Direction $ranges.damage $c.y (-$c.x))
     }
     $color=if ($effect -and $c.attack) {'both'} elseif ($effect) {'effect'} elseif ($c.attack) {'attack'} else {'empty'}
     if ($directional -and (Contains-Direction $ranges.damage $c.x $c.y)) {$color='facing'}
     $px=$offset+($c.x+$radius)*$cell;$py=$offset+($c.y+$radius)*$cell
     $g.FillRectangle($brushes[$color],$px+1,$py+1,$cell-2,$cell-2)
     $mx=$px+[int][Math]::Floor($cell/2);$my=$py+[int][Math]::Floor($cell/2);$r=[Math]::Max(2,[int][Math]::Floor($cell/5))
     if ($c.x -eq 0 -and $c.y -eq 0) {$g.FillEllipse($brushes.ink,$mx-$r,$my-$r,2*$r,2*$r)}
     if ($null -ne $target -and $c.x -eq $target.x -and $c.y -eq $target.y) {$g.DrawLine($pen,$mx-$r,$my,$mx+$r,$my);$g.DrawLine($pen,$mx,$my-$r,$mx,$my+$r)}
    }
   } else {
    if ($supported) {
     # Explicit no-outward-range symbol, not an empty board.
     $g.DrawEllipse($pen,65,65,60,60);$g.DrawLine($pen,74,116,116,74)
    } else {
     $font=[Drawing.Font]::new('Microsoft YaHei',16)
     try {$g.DrawString('未支持此范围',$font,$brushes.ink,[single]14,[single]78)} finally {$font.Dispose()}
    }
   }
   $bitmap.Save((Join-Path $OutputDirectory "$id.png"),[Drawing.Imaging.ImageFormat]::Png)
  } finally {$g.Dispose();$bitmap.Dispose()}
  $count++
 }
} finally {$pen.Dispose();foreach ($b in $brushes.Values) {$b.Dispose()}}
@{count=$count;directional_count=$directionCount;unsupported_ids=@($unsupported);catalog_sha256=(Get-FileHash -LiteralPath $Catalog -Algorithm SHA256).Hash;note='All current range enum types implemented. Directional ranges show four-facing union; dark red is one example facing (southeast for oblique). Reproduced from GameAssembly RVAs 5E7BB0/5E80C0/5E7E90/5E76C0. No terrain or character bonuses; radius capped at 10.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutputDirectory 'manifest.json') -Encoding UTF8
Write-Output "Generated $count images in $OutputDirectory"

# Refresh the standalone HTML as well: its images are embedded, so changing
# only book-ranges/*.png would leave the browser showing the old diagrams.
$htmlPath=Join-Path (Split-Path $Catalog -Parent) '秘籍查询.html'
if (Test-Path -LiteralPath $htmlPath) {
 $html=[IO.File]::ReadAllText($htmlPath)
 $imageMap=@{}
 foreach ($book in $data.books) {
  $imageMap[[string]$book.skill_id]=[Convert]::ToBase64String([IO.File]::ReadAllBytes((Join-Path $OutputDirectory "$($book.skill_id).png")))
 }
 $imagesJson=ConvertTo-Json -InputObject $imageMap -Compress
 $catalogText=[IO.File]::ReadAllText($Catalog).Replace('<','\u003c')
 $imagePattern='(?s)(<script id="image-data" type="application/json">).*?(</script>)'
 $catalogPattern='(?s)(<script id="catalog-data" type="application/json">).*?(</script>)'
 if (-not [regex]::IsMatch($html,$imagePattern) -or -not [regex]::IsMatch($html,$catalogPattern)) {throw 'HTML data blocks missing; original HTML left unchanged'}
 $backupDir=Join-Path (Split-Path $htmlPath -Parent) 'backups'
 [void][IO.Directory]::CreateDirectory($backupDir)
 Copy-Item -LiteralPath $htmlPath -Destination (Join-Path $backupDir ('catalog-before-image-refresh-'+[DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')+'.html'))
 $html=[regex]::Replace($html,$imagePattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $m.Groups[1].Value+$imagesJson+$m.Groups[2].Value})
 $html=[regex]::Replace($html,$catalogPattern,[Text.RegularExpressions.MatchEvaluator]{param($m) $m.Groups[1].Value+$catalogText+$m.Groups[2].Value})
 [IO.File]::WriteAllText($htmlPath,$html,[Text.UTF8Encoding]::new($false))
 Write-Output "Updated embedded images in $htmlPath (previous HTML backed up)"
}

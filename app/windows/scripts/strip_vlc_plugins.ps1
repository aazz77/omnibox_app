# strip_vlc_plugins.ps1
#
# Run after `flutter build windows --release`. Removes VLC runtime plugins
# not needed for IPTV/local playback, shrinking plugins/ from ~130MB to ~33MB
# (everything outside the whitelist is deleted).
#
# Usage (from the windows directory):
#   powershell -ExecutionPolicy Bypass -File scripts\strip_vlc_plugins.ps1
#
# Adapted from Nexus (apps/windows/scripts/strip_vlc_plugins.ps1); see
# vlc_plugins_reference.md in the same dir for the filename cross-check.
# If you upgrade vlc_player / the VLC runtime, rebuild an unstripped copy and
# re-verify the whitelist filenames -- historically a typo (e.g. writing
# libaccess_http_plugin instead of libhttp_plugin) silently broke the list.

# NOTE: keep this file pure ASCII. Windows PowerShell 5.1 reads a BOM-less
# UTF-8 script using the system ANSI code page, which mangles non-ASCII
# characters inside string literals and causes parse errors.

$ErrorActionPreference = 'Stop'

# 1. Locate the Release directory.
# This script lives at <app>/windows/scripts, so the build output is two
# levels up: <app>/build/windows/x64/runner/Release.
$releaseDir = Join-Path $PSScriptRoot '..\..\build\windows\x64\runner\Release'
if (-not (Test-Path $releaseDir)) {
  # Fallback: find the Release dir that actually contains the built exe,
  # so a different Flutter layout still works.
  $appDir = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
  $candidate = Get-ChildItem -Path (Join-Path $appDir 'build\windows') -Recurse -Directory `
    -Filter 'Release' -ErrorAction SilentlyContinue |
    Where-Object { Get-ChildItem $_.FullName -Filter '*.exe' -ErrorAction SilentlyContinue } |
    Select-Object -First 1
  if ($candidate) { $releaseDir = $candidate.FullName }
}
if (-not (Test-Path $releaseDir)) {
  Write-Error ("Release directory not found: {0}. Run flutter build windows --release first." -f $releaseDir)
  exit 1
}
$releaseDir = (Resolve-Path $releaseDir).Path
Write-Host ("Release directory: {0}" -f $releaseDir)

# 2. Recursively find plugins dirs containing *_plugin.dll (vlc_player may use vlc\plugins or plugins)
$pluginDirs = Get-ChildItem -Path $releaseDir -Recurse -Directory -Filter 'plugins' -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -match 'vlc' -or (Test-Path (Join-Path $_.FullName '..\libvlc.dll')) }
if ($pluginDirs.Count -eq 0) {
  $pluginDirs = Get-ChildItem -Path $releaseDir -Recurse -Directory -Filter 'plugins' -ErrorAction SilentlyContinue |
    Where-Object { (Get-ChildItem $_.FullName -Filter '*_plugin.dll' -ErrorAction SilentlyContinue).Count -gt 0 }
}
if ($pluginDirs.Count -eq 0) {
  Write-Host "No VLC plugins directory found (this build may not bundle the VLC runtime); skipping."
  exit 0
}

# 3. IPTV / local playback plugin whitelist (filenames only, no path)
$keep = @(
  # access / filesystem / network
  'libfilesystem_plugin', 'libhttp_plugin', 'libhttps_plugin',
  'libtcp_plugin', 'libudp_plugin', 'liblive555_plugin',
  'libaccess_concat_plugin', 'libaccess_realrtsp_plugin',
  'libaccess_imem_plugin', 'libimem_plugin',
  # demux -- libadaptive handles HLS(.m3u8)/DASH
  'libts_plugin', 'libadaptive_plugin', 'libasf_plugin', 'libavi_plugin',
  'libes_plugin', 'libmkv_plugin', 'libmp4_plugin', 'libogg_plugin',
  'libps_plugin', 'librawdv_plugin', 'librawvid_plugin', 'libwav_plugin',
  # codec -- avcodec(FFmpeg) covers H.264/H.265/AAC/MP3 etc
  'libavcodec_plugin', 'liba52_plugin', 'libdca_plugin', 'libflac_plugin',
  'libvorbis_plugin', 'libopus_plugin', 'libadpcm_plugin', 'libaraw_plugin',
  'libsubsusf_plugin',
  # packetizer -- TS/PS elementary stream repackaging, required for live TV
  'libpacketizer_h264_plugin', 'libpacketizer_hevc_plugin',
  'libpacketizer_mpeg4audio_plugin', 'libpacketizer_mpegaudio_plugin',
  'libpacketizer_mpegvideo_plugin', 'libpacketizer_copy_plugin',
  'libpacketizer_a52_plugin', 'libpacketizer_dts_plugin',
  # video_chroma -- decode output -> vout pixel format conversion, required
  'libswscale_plugin', 'libi420_rgb_plugin', 'libi420_yuy2_plugin',
  'libi422_yuy2_plugin', 'libi422_i420_plugin', 'libyuvp_plugin', 'libchain_plugin',
  # video_output -- renderers + window/surface providers (incl. vmem texture callback for embedded playback)
  'libdirect3d11_plugin', 'libdirect3d9_plugin', 'libdirectdraw_plugin',
  'libwgl_plugin', 'libgl_plugin', 'libglwin32_plugin', 'libwingdi_plugin',
  'libvmem_plugin', 'libwinhibit_plugin',
  'libdirect3d11_filters_plugin', 'libdirect3d9_filters_plugin',
  # audio_output / mixer / filter
  'libdirectsound_plugin', 'libwasapi_plugin', 'libmmdevice_plugin',
  'libaudio_format_plugin', 'libfloat_mixer_plugin',
  'libsimple_channel_mixer_plugin', 'libspatializer_plugin',
  'libugly_resampler_plugin', 'libscaletempo_plugin',
  # video_filter / subtitles / core misc
  'libdeinterlace_plugin', 'libfreetype_plugin',
  'liblogger_plugin', 'libstats_plugin',
  'libaudioscrobbler_plugin', 'libmemory_keystore_plugin'
)

# 4. Delete plugins outside the whitelist
$totalRemoved = 0
$totalBytesSaved = 0
foreach ($dir in $pluginDirs) {
  $allPlugins = Get-ChildItem -Path $dir.FullName -Recurse -Filter '*_plugin.dll' -ErrorAction SilentlyContinue
  $beforeSize = ($allPlugins | Measure-Object -Property Length -Sum).Sum
  Write-Host ("Processing: {0}  {1} plugins, {2:N1} MB" -f $dir.FullName, $allPlugins.Count, ($beforeSize / 1MB))
  foreach ($p in $allPlugins) {
    if ($keep -notcontains $p.BaseName) {
      $totalBytesSaved += $p.Length
      Remove-Item $p.FullName -Force
      $totalRemoved++
    }
  }
  $afterPlugins = Get-ChildItem -Path $dir.FullName -Recurse -Filter '*_plugin.dll' -ErrorAction SilentlyContinue
  $afterSize = ($afterPlugins | Measure-Object -Property Length -Sum).Sum
  Write-Host ("  Kept {0}, {1:N1} MB" -f $afterPlugins.Count, ($afterSize / 1MB))
}

# 5. Delete extra VLC dirs/files not needed for embedded playback (locale 104 langs ~41MB etc)
$extraDirs = @('locale', 'lua', 'skins', 'hrtfs')
$extraFiles = @('axvlc.dll', 'npvlc.dll', 'debug_log.txt')
foreach ($name in $extraDirs) {
  $p = Join-Path $releaseDir $name
  if (Test-Path $p) {
    $sz = (Get-ChildItem $p -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
    $totalBytesSaved += $sz
    Write-Host ("Removed dir: {0}  ({1:N1} MB)" -f $name, ($sz / 1MB))
  }
}
foreach ($name in $extraFiles) {
  $p = Join-Path $releaseDir $name
  if (Test-Path $p) {
    $totalBytesSaved += (Get-Item $p).Length
    Remove-Item $p -Force -ErrorAction SilentlyContinue
    Write-Host ("Removed file: {0}" -f $name)
  }
}

Write-Host ""
Write-Host ("Done. Removed {0} plugins, saved {1:N1} MB." -f $totalRemoved, ($totalBytesSaved / 1MB))

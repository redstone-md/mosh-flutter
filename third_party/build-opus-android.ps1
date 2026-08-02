# Builds a static libopus.a for android-arm64 (aarch64-linux-android) from the
# opus source vendored inside audiopus_sys-0.1.8, using the NDK 28 clang.
#
# Why this exists: audiopus_sys-0.1.8's build.rs picks its link-search path
# based on the *host* cfg (x86_64-pc-windows-msvc), so on a Windows host it
# emits a rustc-link-search to the bundled msvc/x64/libopus.lib (Windows COFF),
# which the android ELF linker cannot use. We instead build a real arm64
# libopus.a once and point LIBOPUS_LIB_DIR at it (see
# rust_builder/cargokit/gradle/plugin.gradle). The build.rs honors
# LIBOPUS_LIB_DIR in both the unix and msvc arms and just emits
# `rustc-link-lib=static=opus` + `rustc-link-search=native=$LIBOPUS_LIB_DIR`.
#
# This script reproduces `make -f Makefile.unix lib` exactly (the float build,
# no FIXED_POINT), because GNU make is not available on this host. The
# translation-unit list and flags below mirror Makefile.unix + its *.mk files.
#
# Usage (from anywhere, run once):
#   pwsh -File build-opus-android.ps1
# It writes libopus.a + the four public headers to ../opus-android-arm64/.

[CmdletBinding()]
param(
    [string]$Api = '24',
    [string]$Ndk = 'D:\android-sdk\ndk\28.2.13676358'
)

$ErrorActionPreference = 'Stop'

$src = 'C:\Users\nevermore\.cargo\registry\src\index.crates.io-1949cf8c6b5b557f\audiopus_sys-0.1.8\opus'
if (-not (Test-Path $src)) {
    throw "Vendored opus source not found at: $src (run cargo fetch for audiopus_sys 0.1.8 first)."
}
$out = Join-Path $PSScriptRoot 'opus-android-arm64'
$work = Join-Path $env:TEMP 'opus-build-arm64'

Remove-Item $work -Recurse -Force -ErrorAction SilentlyContinue
Copy-Item $src $work -Recurse

$ndkBin = Join-Path $Ndk 'toolchains\llvm\prebuilt\windows-x86_64\bin'
$cc  = Join-Path $ndkBin "aarch64-linux-android${Api}-clang.cmd"
$ar  = Join-Path $ndkBin 'llvm-ar.exe'
$ran = Join-Path $ndkBin 'llvm-ranlib.exe'
foreach ($t in @($cc, $ar, $ran)) {
    if (-not (Test-Path $t)) { throw "NDK tool not found: $t" }
}

# Makefile.unix's `package_version` target runs ./update_version if present,
# else writes PACKAGE_VERSION="unknown". We use the documented fallback.
Set-Content (Join-Path $work 'package_version') 'PACKAGE_VERSION="unknown"' -NoNewline
$pkgVer = 'unknown'

# --- Flags, mirroring Makefile.unix ---------------------------------------
# CFLAGS := -DUSE_ALLOCA $(CFLAGS)            (top of Makefile.unix)
# CFLAGS += -O2 -g $(WARNINGS) -DOPUS_BUILD   (float branch, not FIXED_POINT)
# CINCLUDES = include silk celt ; float build adds silk/float
# We add -DHAVE_LRINTF (the playbook's CFLAGS) and -fPIC (static lib in a .so).
$defines  = '-DOPUS_BUILD', '-DUSE_ALLOCA', '-DHAVE_LRINTF'
$includes = '-Iinclude', '-Isilk', '-Icelt', '-Isilk/float'
$warn     = '-Wall', '-W', '-Wstrict-prototypes', '-Wextra', '-Wcast-align', '-Wnested-externs', '-Wshadow'
$baseCflags = @('-O2', '-g') + $warn + $defines + $includes + '-fPIC', '-target', "aarch64-linux-android${Api}"

# --- Source list: SRCS_C = SILK_SOURCES + SILK_SOURCES_FLOAT + CELT_SOURCES + OPUS_SOURCES + OPUS_SOURCES_FLOAT
$silk = @(
    'silk/CNG.c','silk/code_signs.c','silk/init_decoder.c','silk/decode_core.c','silk/decode_frame.c',
    'silk/decode_parameters.c','silk/decode_indices.c','silk/decode_pulses.c','silk/decoder_set_fs.c',
    'silk/dec_API.c','silk/enc_API.c','silk/encode_indices.c','silk/encode_pulses.c','silk/gain_quant.c',
    'silk/interpolate.c','silk/LP_variable_cutoff.c','silk/NLSF_decode.c','silk/NSQ.c','silk/NSQ_del_dec.c',
    'silk/PLC.c','silk/shell_coder.c','silk/tables_gain.c','silk/tables_LTP.c','silk/tables_NLSF_CB_NB_MB.c',
    'silk/tables_NLSF_CB_WB.c','silk/tables_other.c','silk/tables_pitch_lag.c','silk/tables_pulses_per_block.c',
    'silk/VAD.c','silk/control_audio_bandwidth.c','silk/quant_LTP_gains.c','silk/VQ_WMat_EC.c',
    'silk/HP_variable_cutoff.c','silk/NLSF_encode.c','silk/NLSF_VQ.c','silk/NLSF_unpack.c','silk/NLSF_del_dec_quant.c',
    'silk/process_NLSFs.c','silk/stereo_LR_to_MS.c','silk/stereo_MS_to_LR.c','silk/check_control_input.c',
    'silk/control_SNR.c','silk/init_encoder.c','silk/control_codec.c','silk/A2NLSF.c','silk/ana_filt_bank_1.c',
    'silk/biquad_alt.c','silk/bwexpander_32.c','silk/bwexpander.c','silk/debug.c','silk/decode_pitch.c',
    'silk/inner_prod_aligned.c','silk/lin2log.c','silk/log2lin.c','silk/LPC_analysis_filter.c',
    'silk/LPC_inv_pred_gain.c','silk/table_LSF_cos.c','silk/NLSF2A.c','silk/NLSF_stabilize.c',
    'silk/NLSF_VQ_weights_laroia.c','silk/pitch_est_tables.c','silk/resampler.c','silk/resampler_down2_3.c',
    'silk/resampler_down2.c','silk/resampler_private_AR2.c','silk/resampler_private_down_FIR.c',
    'silk/resampler_private_IIR_FIR.c','silk/resampler_private_up2_HQ.c','silk/resampler_rom.c',
    'silk/sigm_Q15.c','silk/sort.c','silk/sum_sqr_shift.c','silk/stereo_decode_pred.c','silk/stereo_encode_pred.c',
    'silk/stereo_find_predictor.c','silk/stereo_quant_pred.c','silk/LPC_fit.c',
    # SILK_SOURCES_FLOAT
    'silk/float/apply_sine_window_FLP.c','silk/float/corrMatrix_FLP.c','silk/float/encode_frame_FLP.c',
    'silk/float/find_LPC_FLP.c','silk/float/find_LTP_FLP.c','silk/float/find_pitch_lags_FLP.c',
    'silk/float/find_pred_coefs_FLP.c','silk/float/LPC_analysis_filter_FLP.c','silk/float/LTP_analysis_filter_FLP.c',
    'silk/float/LTP_scale_ctrl_FLP.c','silk/float/noise_shape_analysis_FLP.c','silk/float/process_gains_FLP.c',
    'silk/float/regularize_correlations_FLP.c','silk/float/residual_energy_FLP.c',
    'silk/float/warped_autocorrelation_FLP.c','silk/float/wrappers_FLP.c','silk/float/autocorrelation_FLP.c',
    'silk/float/burg_modified_FLP.c','silk/float/bwexpander_FLP.c','silk/float/energy_FLP.c',
    'silk/float/inner_product_FLP.c','silk/float/k2a_FLP.c','silk/float/LPC_inv_pred_gain_FLP.c',
    'silk/float/pitch_analysis_core_FLP.c','silk/float/scale_copy_vector_FLP.c','silk/float/scale_vector_FLP.c',
    'silk/float/schur_FLP.c','silk/float/sort_FLP.c'
)
$celt = @(
    'celt/bands.c','celt/celt.c','celt/celt_encoder.c','celt/celt_decoder.c','celt/cwrs.c','celt/entcode.c',
    'celt/entdec.c','celt/entenc.c','celt/kiss_fft.c','celt/laplace.c','celt/mathops.c','celt/mdct.c',
    'celt/modes.c','celt/pitch.c','celt/celt_lpc.c','celt/quant_bands.c','celt/rate.c','celt/vq.c'
)
$opusSrc = @(
    'src/opus.c','src/opus_decoder.c','src/opus_encoder.c','src/opus_multistream.c',
    'src/opus_multistream_encoder.c','src/opus_multistream_decoder.c','src/repacketizer.c',
    'src/opus_projection_encoder.c','src/opus_projection_decoder.c','src/mapping_matrix.c',
    # OPUS_SOURCES_FLOAT
    'src/analysis.c','src/mlp.c','src/mlp_data.c'
)
$all = $silk + $celt + $opusSrc

Write-Host "Compiling $($all.Count) translation units for aarch64-linux-android (API $Api)..."
# Makefile.unix uses relative paths (include, silk, celt, src) and expects to
# run from the opus root. The NDK .cmd wrappers resolve -I relative to cwd, so
# we compile from $work with relative src/obj paths -- exactly as `make` would.
$objs = New-Object System.Collections.Generic.List[string]
$i = 0
Push-Location $work
try {
foreach ($s in $all) {
    $i++
    $obj = [System.IO.Path]::ChangeExtension($s, '.o')
    New-Item -ItemType Directory -Force -Path (Split-Path $obj -Parent) | Out-Null
    # Makefile gives celt/celt.o a -DPACKAGE_VERSION='"..."' (package_version target).
    # The macro must expand to a C string literal so `return "libopus " PACKAGE_VERSION`
    # in celt/celt.c concatenates. The NDK clang .cmd wrapper strips raw double
    # quotes, so we backslash-escape them: clang receives PACKAGE_VERSION="unknown".
    if ($s -eq 'celt/celt.c') {
        $cflags = @("-DPACKAGE_VERSION=\`"$pkgVer\`"") + $baseCflags
    } else {
        $cflags = $baseCflags
    }
    & $cc -c @cflags -o $obj $s
    if ($LASTEXITCODE -ne 0) { throw "Compilation failed for: $s" }
    $objs.Add((Join-Path $work $obj))
    if ($i % 25 -eq 0) { Write-Host "  ...$i / $($all.Count)" }
}
} finally { Pop-Location }

Write-Host "Archiving $($objs.Count) objects -> libopus.a"
$libPath = Join-Path $work 'libopus.a'
Remove-Item $libPath -Force -ErrorAction SilentlyContinue
& $ar rcs $libPath @objs
if ($LASTEXITCODE -ne 0) { throw 'ar failed' }
& $ran $libPath
if ($LASTEXITCODE -ne 0) { throw 'ranlib failed' }

New-Item -ItemType Directory -Force -Path $out | Out-Null
Copy-Item $libPath (Join-Path $out 'libopus.a') -Force
New-Item -ItemType Directory -Force -Path (Join-Path $out 'include') | Out-Null
foreach ($h in 'opus.h','opus_defines.h','opus_types.h','opus_multistream.h') {
    Copy-Item (Join-Path $src "include\$h") (Join-Path $out 'include') -Force
}

Write-Host '=== objdump sanity (expect: archive file, aarch64 ELF members) ==='
& (Join-Path $ndkBin 'llvm-objdump.exe') -a (Join-Path $out 'libopus.a') 2>&1 | Select-Object -First 8
Write-Host ("=== libopus.a size: {0:N0} bytes ===" -f (Get-Item (Join-Path $out 'libopus.a')).Length)
Write-Host "Wrote: $out"

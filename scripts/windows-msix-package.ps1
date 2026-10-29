# Packs the release build (flutter build windows --release) into the
# Microsoft Store package, build/msix-dist/mosh-<version>-x64.msix.
#
# The Store package is left unsigned: Partner Center signs what it
# certifies and rejects a package signed by anyone else. For installing it
# locally before an upload, the same package also goes to build/msix-test
# signed with a throwaway certificate (subject = the Partner Center
# publisher) next to that certificate's .cer. Trust the .cer under Local
# Machine > Trusted People, then open the .msix.
$ErrorActionPreference = 'Stop'

function Invoke-Tool([string] $tool) {
  & $tool @args
  if ($LASTEXITCODE -ne 0) { throw "$(Split-Path $tool -Leaf) failed with exit code $LASTEXITCODE" }
}

$release = 'build/windows/x64/runner/Release'
$work = 'build/msix'
$layout = "$work/layout"
$dist = 'build/msix-dist'
$test = 'build/msix-test'
Remove-Item -Recurse -Force $work, $dist, $test -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Force $layout, "$work/pri", $dist, $test | Out-Null

$version = (Select-String -Path pubspec.yaml -Pattern '^version:\s*(.+)$').Matches[0].Groups[1].Value.Trim()
$name = "mosh-$version-x64"
$sdk = Get-ChildItem 'C:\Program Files (x86)\Windows Kits\10\bin\*\x64\makeappx.exe' |
  Sort-Object { [version]$_.Directory.Parent.Name } | Select-Object -Last 1
if (-not $sdk) { throw 'Windows SDK makeappx.exe not found' }
$bin = $sdk.DirectoryName

Copy-Item "$release/*" $layout -Recurse
Copy-Item windows/msix/Assets $layout -Recurse
Invoke-Tool node scripts/msix-manifest.mjs "$layout/AppxManifest.xml"

# Index only the logos: makepri over the whole layout would also index
# every Flutter asset as a package resource.
Copy-Item windows/msix/Assets "$work/pri" -Recurse
Copy-Item "$layout/AppxManifest.xml" "$work/pri"
Invoke-Tool "$bin/makepri.exe" createconfig /cf "$work/priconfig.xml" /dq en-US /pv 10.0.0 /o
Invoke-Tool "$bin/makepri.exe" new /pr "$work/pri" /cf "$work/priconfig.xml" /mn "$work/pri/AppxManifest.xml" /of "$layout/resources.pri" /o

$msix = "$dist/$name.msix"
Invoke-Tool "$bin/makeappx.exe" pack /d $layout /p $msix /h SHA256 /o
$hash = (Get-FileHash $msix -Algorithm SHA256).Hash.ToLower()
"$hash  $name.msix" | Out-File -Encoding ascii -NoNewline "$msix.sha256"
Write-Host "$hash  $name.msix"

$publisher = (Get-Content windows/msix/identity.json -Raw | ConvertFrom-Json).publisher
$cert = New-SelfSignedCertificate -Type Custom -Subject $publisher -KeyUsage DigitalSignature `
  -FriendlyName 'Mosh MSIX local test' -CertStoreLocation Cert:\CurrentUser\My `
  -TextExtension @('2.5.29.37={text}1.3.6.1.5.5.7.3.3', '2.5.29.19={text}')
try {
  $password = [guid]::NewGuid().ToString()
  Export-PfxCertificate -Cert $cert -FilePath "$work/test.pfx" `
    -Password (ConvertTo-SecureString $password -AsPlainText -Force) | Out-Null
  Export-Certificate -Cert $cert -FilePath "$test/mosh-msix-test.cer" | Out-Null
  Copy-Item $msix "$test/$name-test.msix"
  Invoke-Tool "$bin/signtool.exe" sign /fd SHA256 /f "$work/test.pfx" /p $password "$test/$name-test.msix"
} finally {
  Remove-Item "Cert:\CurrentUser\My\$($cert.Thumbprint)"
  Remove-Item "$work/test.pfx" -ErrorAction SilentlyContinue
}

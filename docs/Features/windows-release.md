# Windows release builds

Every release tag publishes two Windows packages, both built by
`build-windows.yml` from the same sources. The `distribution-channel` input
picks the package:

| Channel | Package | Who installs it |
| --- | --- | --- |
| `github` | `mosh-<version>-setup.exe` (Inno Setup, `windows/installer/mosh.iss`) | People downloading from GitHub. Unsigned: SmartScreen warns (see `CODE_SIGNING.md`). Updates itself from the release feed (ADR 0045). |
| `msstore` | `mosh-<version>-x64.msix` | Uploaded to Microsoft Store as *Mosh Messenger* (Store ID `9N46QDWX8XPK`). The Store signs and updates it; About shows only the version. |

CI builds both on every PR, so a package that stops building fails before a
release does. Each build records its `plus-build.json`. The Store build's copy
is named `plus-build-msstore.json`, so the two do not overwrite each other in
the release.

## Store package

`scripts/windows-msix-package.ps1` copies the release build into a package
layout, adds the logos from `windows/msix/Assets`, and writes
`AppxManifest.xml` with `scripts/msix-manifest.mjs`. It then indexes the logos
with `makepri` and packs the package with `makeappx` from the runner's Windows SDK.

- **Identity.** `windows/msix/identity.json` holds the values Partner Center
  assigned: Package/Identity/Name, Package/Identity/Publisher,
  PublisherDisplayName, and the reserved display name. Change that file, not
  the manifest, if Partner Center changes them.
- **Version.** The version comes from `pubspec.yaml` with a zero revision
  (`0.25.1` becomes `0.25.1.0`); the Store requires revision 0. A pre-release
  suffix is dropped.
- **Integration.** The manifest declares what the installer writes to the
  registry at startup: the `mosh://` scheme (a packaged app's registry writes
  stay private to it), and the COM activator that notification clicks start.
  The activator id must be the guid in `notifications_provider.dart`; a
  script test checks this.
- **Dependencies.** The package depends on `Microsoft.VCLibs.140.00.UWPDesktop`
  for the C++ runtime. The Store installs it with the app.
- **Logos.** `dart run scripts/generate_app_icons.dart` generates the logos
  from the brand mark, together with the other platform icons.

## Uploading to the Store

The release `.msix` is unsigned on purpose. Partner Center signs what it
certifies and rejects a package signed by another publisher. Upload it under
Packages in a new submission. The next version must be higher than the last
upload.

## Checking the package locally

The build also uploads the Actions artifact `mosh-windows-msix-test`. It is
never published, and it holds the same package signed with a throwaway
certificate whose subject is the Partner Center publisher.

1. Download `mosh-windows-msix-test` from the workflow run.
2. In an administrator PowerShell, run
   `Import-Certificate mosh-msix-test.cer -CertStoreLocation Cert:\LocalMachine\TrustedPeople`.
3. Open `mosh-<version>-x64-test.msix` and install it.

Every build signs with a new certificate, so import the `.cer` again for each
build you test. Remove the package from Settings → Apps before installing the
Store version.

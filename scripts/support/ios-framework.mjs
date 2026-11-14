// A dynamic library as the iOS app embeds it: `<name>.framework/<name>`
// with the Info.plist App Store validation requires of an embedded
// framework (a bundle id, the platform and a minimum OS version).
import { mkdir, rename, rm, writeFile } from "node:fs/promises";
import path from "node:path";

/** Matches the Runner target's IPHONEOS_DEPLOYMENT_TARGET. */
export const MIN_IOS = "15.0";

/** The install name a framework's library must carry, for `-install_name`. */
export const frameworkInstallName = (name) => `@rpath/${name}.framework/${name}`;

/**
 * Makes `directory/<name>.framework` from `library` (moved into it) and
 * returns the framework's path. The library must already carry
 * `frameworkInstallName(name)`.
 */
export async function writeFramework({ directory, name, bundleId, library }) {
  const framework = path.join(directory, `${name}.framework`);
  await rm(framework, { recursive: true, force: true });
  await mkdir(framework, { recursive: true });
  await rename(library, path.join(framework, name));
  await writeFile(path.join(framework, "Info.plist"), infoPlist(name, bundleId));
  return framework;
}

function infoPlist(name, bundleId) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${name}</string>
	<key>CFBundleIdentifier</key>
	<string>${bundleId}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${name}</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>1.0</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>iPhoneOS</string>
	</array>
	<key>CFBundleVersion</key>
	<string>1</string>
	<key>MinimumOSVersion</key>
	<string>${MIN_IOS}</string>
</dict>
</plist>
`;
}

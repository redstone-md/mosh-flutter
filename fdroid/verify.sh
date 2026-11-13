#!/usr/bin/env bash
# Runs fdroid/app.mosh.mosh.yml at one commit of Mosh the way fdroiddata's CI
# runs a submitted recipe (its "fdroid build" job): `fdroid build` with the
# scanner, `fdroid lint`, `fdroid rewritemeta` and the Gradle audit. The fdroid workflow runs it in the
# fdroidserver buildserver image with this checkout at /repo.
#
#   COMMIT=<sha> VERSION=<versionName> CODE=<versionCode> fdroid/verify.sh
set -euo pipefail
: "${COMMIT:?the commit of Mosh to build}" "${VERSION:?its version}" "${CODE:?its versionCode}"
appid=app.mosh.mosh
repo=/repo
work=/work
export ANDROID_HOME=/opt/android-sdk
source /etc/profile.d/bsenv.sh

git clone --depth 1 https://gitlab.com/fdroid/fdroiddata.git "$work/fdroiddata"
git clone --depth 1 https://gitlab.com/fdroid/fdroidserver.git "$work/fdroidserver"
export PATH="$work/fdroidserver:$PATH" PYTHONPATH="$work/fdroidserver:$work/fdroidserver/examples"
export PYTHONUNBUFFERED=true serverwebroot=/tmp

# The recipe as submitted, at the commit under test.
sed -e "s/^    commit: .*/    commit: $COMMIT/" \
  -e "s/^  - versionName: .*/  - versionName: $VERSION/" -e "s/^    versionCode: .*/    versionCode: $CODE/" \
  -e "s/^CurrentVersion: .*/CurrentVersion: $VERSION/" -e "s/^CurrentVersionCode: .*/CurrentVersionCode: $CODE/" \
  "$repo/fdroid/$appid.yml" > "$work/fdroiddata/metadata/$appid.yml"

cd "$work/fdroiddata"
fdroid lint "$appid"
# The recipe is in the canonical format fdroiddata keeps.
cp "metadata/$appid.yml" "$work/recipe.yml"
fdroid rewritemeta "$appid"
diff -u "$work/recipe.yml" "metadata/$appid.yml"
sysctl fs.inotify.max_user_watches=524288 || true
# What fdroiddata's buildserver sets up before a build.
sdkmanager "platform-tools" "build-tools;31.0.0"
for directory in logs tmp unsigned "$home_vagrant/.android" "$home_vagrant/.gradle" "$home_vagrant/metadata"; do
  mkdir -p "$directory"
  chown -R vagrant "$directory"
done
ln -s "$PWD/tmp" "$home_vagrant/tmp"
ln -s "$PWD/srclibs" "$home_vagrant/srclibs"
cp "metadata/$appid.yml" "$home_vagrant/metadata/"
apt-get update
apt-get install -y sudo openjdk-21-jdk-headless
chown -R vagrant "$home_vagrant" "$PWD"
fdroid="sudo --preserve-env --user vagrant env PATH=$PATH PYTHONPATH=$PYTHONPATH PYTHONUNBUFFERED=true HOME=$home_vagrant GRADLE_USER_HOME=$home_vagrant/.gradle fdroid"
cd "$home_vagrant"
ln -s "$work/fdroiddata" fdroiddata
$fdroid fetchsrclibs "$appid:$CODE" --verbose
rm fdroiddata
(unset CI; $fdroid build --verbose --test --refresh-scanner --on-server --no-tarball "$appid:$CODE")
cd "$work/fdroiddata"
./tools/audit-gradle.py "$appid"

mkdir -p "$repo/build/fdroid"
cp "$work/fdroiddata/tmp/${appid}_${CODE}.apk" "$repo/build/fdroid/"

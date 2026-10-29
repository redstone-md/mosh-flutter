# Store listings

Mosh uses one set of texts and screenshots for its pages in Microsoft Store,
F-Droid and RuStore, in English and Russian. They live in
`fastlane/metadata`, where F-Droid reads them. RuStore and Partner Center are
filled in by hand from the same files.

```text
fastlane/metadata/
├── android/<locale>/        # F-Droid reads this; RuStore copies it
│   ├── title.txt
│   ├── short_description.txt
│   ├── full_description.txt
│   ├── changelogs/<versionCode>.txt
│   └── images/phoneScreenshots/1-4.png    # 1080 × 1920
└── msstore/<locale>/        # pasted into Partner Center
    ├── description.txt
    ├── short_description.txt
    ├── features.txt         # one Product feature per line
    └── screenshots/1-4.png  # 1920 × 1080
```

Locales are `en-US` and `ru-RU`. The screenshots show, in order, the chat
list, a conversation, a call and the Sound & Video settings.

## What the texts may promise

Every store describes the same features. The Microsoft Store description is the
Android description without its feature list and links: Partner Center shows
`features.txt` as its own list and takes links in separate fields. Each line of
`features.txt` is a bullet of the Android description.

Mosh+ appears only as an optional supporter badge, with no price and no
invitation to buy. RuStore builds do not sell it (see
[Production Mosh+](plus-mainnet.md)), so no text may suggest a purchase.

`node --test scripts/store-listing.test.mjs` checks the store limits, that the
Microsoft Store text repeats the Android one, that no text names a price, and
the screenshot sizes. CI runs it.

| Field | Limit |
| --- | --- |
| Title (RuStore) | 30 characters (F-Droid allows 50) |
| Short description (F-Droid, RuStore) | 80 characters |
| Full description (F-Droid, RuStore) | 4,000 characters |
| Changelog (F-Droid) | 500 characters |
| Description (Microsoft Store) | 10,000 characters, no links |
| Short description (Microsoft Store) | 270 characters are always visible |
| Product features (Microsoft Store) | 20 lines of up to 200 characters |

Partner Center no longer has a search-terms field, so there are no keywords.

## Links for the store forms

| Field | English | Russian |
| --- | --- | --- |
| Website | https://mosh.run | https://mosh.run/ru |
| Privacy policy | https://mosh.run/privacy | https://mosh.run/ru/privacy |
| Mosh+ terms | https://mosh.run/plus/terms | https://mosh.run/ru/plus/terms |
| Support | https://github.com/redstone-md/mosh-flutter/issues | same |
| Source code | https://github.com/redstone-md/mosh-flutter | same |

## Each release

Add `changelogs/<versionCode>.txt` in both Android locales, with the
user-facing lines from `CHANGELOG.md`. The versionCode is
`major × 1000000 + minor × 1000 + patch` (`0.26.0` is `26000`), as the Android
release build computes it. Paste the same lines into "What's new" in Partner
Center and RuStore.

## Screenshots

`scripts/capture_store.dart` renders the real app with fictional data from the
test doubles: no Rust runtime, network or personal data. A phone is 360 × 640
logical pixels at 3×, a desktop 1280 × 720 at 1.5×. On the phone the call
uses the Android call surface; the desktop shows the in-app call strip.

```sh
flutter test scripts/capture_store.dart --dart-define=SETUP_PREVIEW=true
```

Look at every image before committing it.

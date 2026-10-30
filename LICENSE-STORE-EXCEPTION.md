# Additional permission for application stores

Mosh is licensed under the [GNU General Public License version 3](LICENSE)
(GPL-3.0). The Mosh copyright holders, ForeverInLaw and Rxflex, add the
following permission under section 7 of that license. It is modelled on the
App Store permission that Signal attaches to its GPL-3.0 apps. Unlike Signal's,
it is not limited to Apple's store and keeps the GPL-3.0 instead of switching
the store build to the Mozilla Public License.

> **Additional permission under GNU GPL version 3 section 7.**
> Provided that you are otherwise in compliance with the GPL-3.0 for each
> covered work you convey (including without limitation making the
> Corresponding Source available in compliance with section 6 of the GPL-3.0),
> the Mosh copyright holders also grant you the additional permission to convey
> non-source executable versions of the Program through an application store,
> such as the Apple App Store, Google Play, Microsoft Store or RuStore, even if
> the terms of that store place restrictions on the recipients that the GPL-3.0
> would not otherwise allow.
>
> This permission applies only to the parts of the Program whose copyright
> belongs to the Mosh copyright holders. Third-party components keep their own
> licenses and are not covered by it.
>
> If you modify the Program, you may extend this permission to your version,
> but you are not obliged to do so. If you do not wish to, delete this
> permission from your version.

The permission does not replace the GPL-3.0. Everyone who receives Mosh from a
store can still get its complete source code from
[this repository](https://github.com/redstone-md/mosh-flutter) under the
GPL-3.0.

## What it does not cover

The call engine in `mosh-media/engine` links Signal's RingRTC, which is
licensed under the AGPL-3.0 without a store permission. For that reason the
engine itself is AGPL-3.0, and the permission above does not reach RingRTC.
A store build that includes calls also needs Signal's permission or a call
engine without RingRTC.

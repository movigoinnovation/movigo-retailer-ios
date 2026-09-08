# Retailer app — iOS vs Android audit

Date: 2026-09-08
iOS source: `Retailer_app_ios/` (extracted from `movigo-retailer-FULL_afc9309.zip`, repo `movigoinnovation/movigo-retailer-ios`, branch `main`, HEAD `afc9309`)
Android source: `Retailer_app_android/`

## 1. Divergence baseline

The iOS repo was seeded at `0cf6e37` "Import Play Store build 55 as new base", then 14 iOS commits were applied.

Comparing `Retailer_app_android/lib` against `Retailer_app_ios/lib` ignoring line endings (the Mac
round-trip converted every file to LF — that is why a naive `diff -rq` reports ~50 files):

- 135 Dart files on both sides. **No file added, removed or renamed.**
- Exactly **11** Dart files genuinely differ, and they are precisely the 11 the iOS commits touched.

So **Android has not drifted since build 55.** All divergence is intentional iOS work. There is no
missed Android feature to forward-port.

### The 11 divergent files, by intent

| Area | Files | Change |
|---|---|---|
| Guest browsing (App Store 5.1.1(v)) | `login_screen.dart`, `new_confirm_screen.dart`, `retailer_confirm_screen.dart`, `common_api_helper.dart` | "Continue as Guest" button; booking gated on token; silent 401 for guests |
| Camera disabled (App Store 2.1(a)) | `account_screen/profile_screen.dart`, `retailer_account_screen/profile_screen.dart` | Camera option greyed out, "Adding soon" |
| App Store update links | `app_constant.dart`, `splash_screen.dart`, `force_update_screen.dart`, `SoftUpdatePopup.dart` | `appAppStoreUrl` + `app_store_url` plumbed through; `Platform.isIOS` branch |
| font_awesome_flutter 10 to 11 | `noticeboard_screen.dart` | `FaIconData` split from `IconData`; `FaIcon` used for brand glyphs |

Native/config deltas: `ios/Podfile` (plus RazorpayStandard simulator strip), `Podfile.lock`,
`project.pbxproj` (CocoaPods integration only), `AppDelegate.swift` (iOS Maps key),
`macos/Podfile`, `codemagic.yaml`, `analysis_options.yaml`, `pubspec.yaml` (1.3.2+56 to 1.3.2+57).

Versions today: **iOS 1.3.2 (57)** vs **Android 1.3.0 (55)** (`android/local.properties`).
Bundle IDs: iOS `com.app.movigoinnovations.retailer`, Android `com.app.movigocustomer`.

---

## 2. Findings

### BLOCKER — Push notifications cannot work on iOS: no `aps-environment` entitlement

`ios/Runner/` contains no `.entitlements` file, and `project.pbxproj` has no
`CODE_SIGN_ENTITLEMENTS` and no Push Notifications capability.

Without `aps-environment`, `registerForRemoteNotifications` fails, so
`FirebaseMessaging.getAPNSToken()` (`lib/main.dart:152`) returns null forever and
`getToken()` throws `apns-token-not-set`. `FcmTokenService._getTokenWithRetry` swallows the
`PlatformException` and gives up, so `player_id` is never sent to the backend — **every push
the retailer gets on Android silently never arrives on iOS**: booking accepted, driver
arrived, delivered, noticeboard, coin milestones.

The Dart side is already iOS-correct (`DarwinInitializationSettings`, `getAPNSToken`,
per-platform `requestPermission`) — only the native capability is missing.

Fix:
1. Add `ios/Runner/Runner.entitlements` with `aps-environment` = `development`, and set
   `CODE_SIGN_ENTITLEMENTS = Runner/Runner.entitlements` for all three configurations.
2. Enable the Push Notifications capability on the App ID in the Developer Portal. The
   Codemagic `ios_signing` profile must be regenerated afterwards, or it will not carry the
   entitlement.
3. Upload the APNs auth key (.p8) to Firebase console, project settings, Cloud Messaging,
   for bundle id `com.app.movigoinnovations.retailer`.

Also worth hardening: `getAPNSToken()` is called once with no retry. APNs registration is
async and commonly returns null on the first call even when configured correctly. Poll it
(e.g. 10 x 500ms) before `FcmTokenService.generateAndStoreToken()`.

### HIGH — The version gate is platform-blind; iOS users can be hard-blocked with no upgrade path

`Backend/src/controllers/app/miscController.js:266` (`GET /app_version_check`) keys only off
`app_type` (`driver|retailer|individual`). There is one `retailer_min_version_code` /
`retailer_latest_version_code` shared by both stores, and the iOS and Android release trains
have already diverged (iOS build 57, Android build 55).

Consequence: the moment Android ships build 58 and `retailer_min_version_code` is raised to 58,
`57 < 58` is true for every iOS user too — `force_update` fires and `ForceUpdateScreen`
hard-blocks the app, sending them to an App Store where 57 is the newest build. The app is
bricked for all iOS retailers until the setting is rolled back.

The reverse also happens: iOS at 57 while the gate tracks Android means iOS builds are never
flagged for update.

Fix: add a `platform=ios|android` query parameter and per-platform settings keys
(`retailer_ios_min_version_code`, `retailer_ios_latest_version_code`,
`retailer_ios_latest_version`, `retailer_app_store_url`), defaulting to the existing Android
keys when `platform` is absent so old installs keep working. Send `platform` from the app
alongside `version_code`.

### HIGH — Backend never returns `app_store_url`, so the plumbing added for it is dead

`splash_screen.dart:364,389` reads `data['app_store_url']` and passes it to `ForceUpdateScreen`
and `SoftUpdatePopup`, but `checkAppVersion` only ever returns `play_store_url` — there is no
`app_store_url` key in either the success or the error response, and no
`retailer_app_store_url` in `SystemSettings.js`.

Today this degrades gracefully: both screens fall back to the hardcoded
`AppConstant.appAppStoreUrl` (`https://apps.apple.com/app/id6793887251`). But the App Store ID
is now baked into the binary — it cannot be corrected without shipping a new build, which is
exactly the situation a force-update screen has to survive. Add the field to the backend
alongside the platform work above.

Related: the in-app notification text at `miscController.js:310` says *"available on the Play
Store"* and is sent to iOS users too.

### MEDIUM — `permission_handler` compiles every iOS permission handler; missing purpose strings risk ITMS-90683

`ios/Podfile` sets no `PERMISSION_*` preprocessor macros, so permission_handler builds handlers
for microphone, calendar, reminders, motion, Bluetooth, speech, media library and Face ID —
none of which the app uses. Apple's static analysis flags the API references and rejects for a
missing `NS*UsageDescription`. `Info.plist` only declares location, camera, photo library and
contacts.

The app was already rejected once under 2.1(a); this is a common cause of a second rejection.

Fix — in the `post_install` block, disable everything the app does not use:

```ruby
config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= ['$(inherited)']
config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] += [
  'PERMISSION_EVENTS=0', 'PERMISSION_REMINDERS=0', 'PERMISSION_MICROPHONE=0',
  'PERMISSION_SPEECH_RECOGNIZER=0', 'PERMISSION_MEDIA_LIBRARY=0',
  'PERMISSION_SENSORS=0', 'PERMISSION_BLUETOOTH=0', 'PERMISSION_APP_TRACKING_TRANSPARENCY=0',
  'PERMISSION_CRITICAL_ALERTS=0', 'PERMISSION_ASSISTANT=0',
  # keep: PERMISSION_LOCATION, PERMISSION_NOTIFICATIONS, PERMISSION_CONTACTS,
  #       PERMISSION_PHOTOS, PERMISSION_CAMERA
]
```

`NSCameraUsageDescription` should stay in `Info.plist` — image_picker still links the camera
API even with the UI disabled.

### MEDIUM — Guest mode is gated at booking only; account actions fail silently

`AppConstant.token.isEmpty` is checked in exactly two places (`new_confirm_screen.dart:192`,
`retailer_confirm_screen.dart:410`). Everything else a guest can reach in the retailer bottom
nav — Bookings tab, Account then Profile / Delete Account / referral / coins — calls the API with
no token, gets a 401, and `_handleStatusCode` now returns `null` **without any toast**
(`common_api_helper.dart:91`).

Returning `null` matches the existing convention for 400/500 so callers are null-safe — this
is not a crash. But the guest gets a spinner that resolves to a blank screen with no explanation,
most visibly on "Delete Account", which appears to do nothing at all.

The retailer nav happens to exclude the Wallet tab (`app_footer.dart:60`), so there is no
Razorpay-without-an-account path. That is luck, not design — it breaks the day the wallet
tab is re-enabled for retailers.

Fix: add a shared `requireLogin(context)` helper and call it from the Account tab's
profile/delete/referral entry points, and from the Bookings tab's empty state ("Log in to see
your bookings"), instead of relying on a silent null.

### LOW — Camera removal also lands on Android when these files merge back

Both `profile_screen.dart` changes are unconditional — no `Platform.isIOS` guard. If the iOS
branch is ever merged back into the Android app (which the shared-`lib/` model invites),
Android retailers lose profile-photo capture too, for an App Store reason that does not apply
to them. Either wrap the disabled state in `if (Platform.isIOS)`, or track it as a known
one-way divergence.

### LOW — `tel:` URI built with a space

`lib/helper/MapImage_screen.dart:1458` builds `Uri.parse('tel:+91 $phoneNumber')` and then gates
on `canLaunchUrl`. The literal space makes the URI malformed; iOS is stricter than Android here,
so the driver-call button is more likely to silently no-op on iOS. Other call sites
(`help_and_support_screen.dart:36`, `booking_tab_detail_screen.dart:119`, etc.) correctly use
`tel:$phoneNumber` with no space. Strip non-digits before interpolating.

### LOW — CI config left with a placeholder and hardcoded release notes

`codemagic.yaml`:
- `publishing.email.recipients` is still `your-email@example.com` (the `CHANGE_ME` comment is
  intact) — nobody is notified of build success or failure.
- `--whats-new "Bug fixes and performance improvements."` is hardcoded, so every App Store
  submission ships the same generic text despite commit `3aafe79` being titled "Provide 'What's
  New' release notes". Read it from a file (e.g. `release_notes/en-US.txt`) instead.
- No `flutter analyze` or `flutter test` step before `build ipa`.

### NOTE — Info.plist / manifest parity

Reviewed and consistent, with these observations:

- `UISupportedInterfaceOrientations` permits landscape on iPhone. Harmless if
  `SystemChrome.setPreferredOrientations` locks portrait at runtime, but the plist should match
  intent.
- `LSApplicationQueriesSchemes` is absent. Only `tel:` and `https:` are used with
  `canLaunchUrl`; both are system-exempt, so no change is needed today. If a WhatsApp or UPI
  deep link is ever added, the scheme must be declared or `canLaunchUrl` returns false.
- iOS Maps key is hardcoded in `AppDelegate.swift:13` and Android's in `AndroidManifest.xml:33` —
  the same pattern on both platforms, distinct keys. Confirm the iOS key is bundle-ID-restricted
  in the Google Cloud console.
- `ios/Runner/GoogleService-Info.plist` is committed to git. Same posture as Android's
  `google-services.json`; fine for a private repo, worth confirming the repo is private.
- Deployment target is 15.0 in both `Podfile` and `project.pbxproj` — consistent.
- `ios/Pods/` is correctly untracked.

---

## 3. Suggested order of work

1. Push entitlement + APNs key (blocker — the app ships today with no notifications at all).
2. Per-platform version gate + `app_store_url` in the backend (prevents a future mass hard-block).
3. permission_handler macros in the Podfile (prevents the next rejection).
4. Guest-mode login prompts on account screens.
5. Codemagic email + release notes, `tel:` fix.

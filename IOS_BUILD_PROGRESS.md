# iOS Build Progress — Retailer App

Last updated: 2026-07-28

## Status: DONE — submission-ready `.ipa` AND working iOS Simulator debug build

`build/ios/ipa/movigo.ipa` (66.4MB) built successfully with correct signing,
display name, and app icon — ready for App Store Connect upload. Separately,
`flutter run` on the iOS Simulator (for local testing, e.g. the OTP login
flow) now also works after fixing a Razorpay/simulator-architecture issue
(see "iOS Simulator debug build" section below). Remaining work is App Store
Connect upload + the pre-existing rebrand gaps below (both optional/deferred
by user choice).

## IMPORTANT: this Mac's CPU is Intel (x86_64), not Apple Silicon

Confirmed via `uname -m` → `x86_64`. This matters a lot for iOS Simulator
work: Simulator apps run natively on the HOST's CPU architecture (unlike a
real device), so Simulator builds on this Mac must target **x86_64**, not
arm64. The existing `EXCLUDED_ARCHS[sdk=iphonesimulator*] = 'arm64'` in
`ios/Podfile` (forcing x86_64) is CORRECT for this machine — do not "fix"
it to exclude x86_64 instead. Getting this backwards costs hours (it did,
in the 2026-07-28 session — see below).

## What was blocking it (now resolved)

### 1. Device registration / signing (resolved before 2026-07-27 session end)
Apple Developer team `6AK2Q3YT9Q` had zero registered devices, and Xcode's
Automatic signing requires a device-capable profile to complete the archive
step even for an App Store build. This got resolved on Apple's side (device
registered, valid Development cert confirmed) — the Mac restarted
unexpectedly on 2026-07-27 mid-session, but on resume the archive completed
cleanly with no "Communication with Apple failed" / "no devices" error.
Nothing needed to be redone for this part.

### 2. CocoaPods Firebase module error (new blocker hit 2026-07-27, fixed same day)
After the device blocker cleared, archiving failed with:
```
Lexical or Preprocessor Issue (Xcode): Include of non-modular header inside
framework module 'firebase_database.FLTFirebaseDatabaseObserveStreamHandler':
'.../ios/Pods/Headers/Public/Firebase/Firebase.h'
```
(also for `firebase_messaging`). Root cause: `ios/Podfile` had both
`use_frameworks!` and `use_modular_headers!`, and `firebase_database` /
`firebase_messaging` directly `#import <Firebase/Firebase.h>` (a
non-modular umbrella header from `Firebase/CoreOnly`), which Xcode's module
validation rejects.

Things that did NOT fix it (tried first, ruled out):
- Adding `CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES = 'YES'` to
  all Pods targets in `post_install` — applied correctly (verified in the
  generated `Pods.xcodeproj`), archive still failed identically.
- Removing `use_modular_headers!` alone — `use_frameworks!` already makes
  pods framework-modules regardless, so this changed nothing.

What actually fixed it: in `ios/Podfile`'s `post_install` block, added a
**targeted** `DEFINES_MODULE = 'NO'` for just the `firebase_database` and
`firebase_messaging` pod targets (kept `CLANG_ALLOW_NON_MODULAR_INCLUDES...`
too, harmless). These two pods are pure Objective-C plugin glue — nothing
needs to `import` them as a Swift module — so disabling module generation
just for them sidesteps the non-modular-header check entirely without
affecting anything else. Current `ios/Podfile` post_install:
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      if ['firebase_database', 'firebase_messaging'].include?(target.name)
        config.build_settings['DEFINES_MODULE'] = 'NO'
      end
    end
  end
end
```
After `pod install` + rebuild, archive + export succeeded.

### 3. Display name and app icon (fixed 2026-07-28, same session as blocker #2)
Xcode's export validation flagged the app as still showing placeholder
branding:
- `ios/Runner/Info.plist` `CFBundleDisplayName` was "Movigo" → changed to
  **"Movigo Retailer"** (user's choice among options offered).
- `ios/Runner/Assets.xcassets/AppIcon.appiconset/` still had the default
  Flutter placeholder icon → regenerated all 15 required sizes (20x20
  through 1024x1024, iPhone + iPad + ios-marketing) via `sips` from a
  1024x1024, no-alpha PNG the user provided
  (`~/Downloads/movigo_appstore_icon_1024.png` — the Movigo logo with
  "Apna Saman, Apni Company" tagline).
  - Note: this logo has heavy white padding around a relatively small
    centered logo, which may read poorly at small icon sizes (20-40px) —
    **user explicitly chose to ship with this icon as-is** and deferred
    icon design polish to a future update. Don't re-raise this unless asked.

Rebuilt after these two fixes — final `flutter build ipa` succeeded, same
`.ipa` path, 66.4MB.

## Environment set up on this Mac (unchanged, still valid as of 2026-07-28)

- **Xcode**: 16.4, at `/Applications/Xcode.app`.
- **Flutter SDK**: cloned into `~/development/flutter` (Flutter 3.44.7).
  PATH via `~/.zshrc`.
- **Ruby**: 3.3.12 via `rbenv` (not Homebrew — Homebrew dirs aren't owned by
  this user, left unfixed by design, don't suggest `brew install`).
- **CocoaPods**: 1.17.0, installed under rbenv Ruby.
- **WWDR G3 intermediate cert**: imported into login keychain (was
  required for "Apple Development" cert trust chain).
- **iOS platform SDK**: 18.5, installed via
  `xcodebuild -downloadPlatform iOS`.

To pick up this environment in a fresh shell:
```
export PATH="$HOME/development/flutter/bin:$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
```

Certificates in keychain (`security find-identity -v -p codesigning`):
- `Apple Development: Mokshit Sharma (335RFBLVG2)` — personal team, unused
  for this project (×2, harmless duplicate)
- `Developer ID Application: Mokshit Sharma (6AK2Q3YT9Q)` — macOS only, not
  used for this iOS build
- `Apple Distribution: Mokshit Sharma (6AK2Q3YT9Q)` — the one that matters
  for App Store submission

Signing settings in `ios/Runner.xcodeproj/project.pbxproj` (Debug/Release/
Profile, Runner target): `CODE_SIGN_STYLE = Automatic`,
`DEVELOPMENT_TEAM = 6AK2Q3YT9Q`.

## Next steps for next session

1. **Upload to App Store Connect.** Not yet done. Either:
   - Drag `build/ios/ipa/movigo.ipa` into the Apple Transporter macOS app, or
   - `xcrun altool --upload-app --type ios -f build/ios/ipa/movigo.ipa --apiKey <key> --apiIssuer <issuer>`
   - Note: if `pod install` or `flutter build ipa` gets re-run before this,
     the `.ipa` will be regenerated — re-check it still exists at that path
     first.
2. If any further code changes are made before upload, re-run:
   ```
   export PATH="$HOME/development/flutter/bin:$HOME/.rbenv/shims:$HOME/.rbenv/bin:$PATH"
   cd /Users/user/Downloads/Retailer_app
   flutter build ipa
   ```
   Archive step reliably takes ~11-13 minutes (650-780s observed across 5
   runs) — this is normal, not a hang.

## iOS Simulator debug build (`flutter run`) — fixed 2026-07-28

Goal: run the app on the iOS Simulator (not archive/device) to test the OTP
login bypass (`+91 9999999999` / OTP `1234`) and take screenshots. Used
iPhone 16 Pro Max simulator (closest available to "iPhone 15 Pro Max /
6.5-inch"; no iPhone 15 Pro Max in this Xcode's simulator list).

**The actual root cause (after a lot of wrong turns — see below):**
`RazorpayStandard.xcframework` (part of `razorpay-pod`, a dependency of
`razorpay_flutter`) ships only `ios-arm64` and `ios-arm64-simulator` slices
— no x86_64 simulator slice. Since this Mac is x86_64, Simulator builds
need x86_64, and RazorpayStandard simply cannot be linked or embedded for
that architecture on this machine. Confirmed via `otool -L` that
`Razorpay.framework` (which the plugin's Swift code actually
`import`s and uses — `RazorpayCheckout`, etc.) only hard-depends on
`RazorpayCore.framework`, never `RazorpayStandard` — and neither
`SwiftRazorpayFlutterPlugin.swift` nor `RazorpayDelegate.swift` (in
`~/.pub-cache/hosted/pub.dev/razorpay_flutter-1.4.1/ios/Classes/`)
reference it either. So it's safe to drop entirely for simulator builds —
device/archive builds are completely unaffected.

**Wrong turns that ate most of the session (recorded so they aren't
repeated):**
1. Assumed this Mac was Apple Silicon and "fixed" the original
   `EXCLUDED_ARCHS[sdk=iphonesimulator*] = 'arm64'` by flipping it to
   exclude `x86_64` instead. This is backwards — see the CPU section above.
   This cascaded into a second real bug it exposed along the way (see next
   point), which was a legitimate fix but became moot once the arch
   direction was reverted.
2. While chasing arm64, hit a genuine Xcode bug: Runner's own build
   settings had no arch exclusion while Pods targets did (opposite
   direction), and Xcode's implicit-dependency-graph resolution silently
   drops a dependency when the consumer and producer's resolved `ARCHS`
   don't match for a given SDK — `xcodebuild ... -dry-run` showed
   `Target dependency graph (1 target)` (just `Runner`, no Pods!) for
   `-sdk iphonesimulator` while showing all 97 targets correctly for
   `-sdk iphoneos`. This is a real, reproducible Xcode quirk worth knowing
   about generally, even though the specific fix (matching exclusions on
   both sides) got reverted once the arm64/x86_64 direction was corrected.
3. Also hit an unrelated, real stale-state issue: a stray Xcode.app GUI
   process (left running in the background, unclear how it got opened)
   had the project loaded and can silently overwrite `pod install`'s
   integration when it saves/quits. `pkill`/`osascript -e 'quit app
   "Xcode"'` before any `pod install` + rebuild cycle avoids this.
4. CoreSimulator can wedge: `simctl install` hung indefinitely (22+ min at
   0% CPU) after repeated boot/shutdown/kill cycling during debugging.
   Fixed with `xcrun simctl erase <UDID>` (full reset) then re-boot.

**The fix, once the actual cause was found** — three separate places all
reference `RazorpayStandard` and all three needed patching (Xcode
regenerates all of these on every `pod install`, so the fix lives in
`ios/Podfile`'s `post_install` hook, not hand-edited generated files):
1. **Linking**: `Pods-Runner.{debug,profile}.xcconfig` AND
   `razorpay_flutter.{debug,profile}.xcconfig` (a separate, second file —
   `razorpay_flutter` compiles as its own intermediate framework target
   with its own `OTHER_LDFLAGS`, independent of the aggregated
   `Pods-Runner` one) both had unconditioned
   `-framework "RazorpayStandard"`. Fixed by adding a same-named
   `OTHER_LDFLAGS[sdk=iphonesimulator*]` override (SDK-conditioned keys
   take precedence) built from the base flags with that one framework
   flag stripped out. Gotcha: don't just copy the base line verbatim minus
   the framework — it starts with literal `$(inherited)`, and leaving that
   in place makes the override re-inherit the *original* unfiltered value,
   silently undoing the fix. Strip the leading `$(inherited)` too.
2. **Embedding**: `Pods-Runner-frameworks.sh` (the generated "Embed Pods
   Frameworks" script) unconditionally calls
   `install_framework ".../razorpay-pod/RazorpayStandard.framework"` three
   times (once per Debug/Profile/Release block). Since that path is never
   populated for x86_64 simulator, the script's `install_framework`
   function falls through without setting its local `source` variable, and
   `set -u` turns the next reference to `$source` into a hard crash
   ("unbound variable"). Fixed by wrapping each call in
   `if [[ "$PLATFORM_NAME" != *simulator ]]; then ... fi` via a `gsub` in
   the same Podfile `post_install` hook.

Current `ios/Podfile` `post_install` block (in full, for reference):
```ruby
post_install do |installer|
  installer.pods_project.targets.each do |target|
    flutter_additional_ios_build_settings(target)
    target.build_configurations.each do |config|
      config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '13.0'
      config.build_settings['EXCLUDED_ARCHS[sdk=iphonesimulator*]'] = 'arm64'
      config.build_settings['CLANG_ALLOW_NON_MODULAR_INCLUDES_IN_FRAMEWORK_MODULES'] = 'YES'
      if ['firebase_database', 'firebase_messaging'].include?(target.name)
        config.build_settings['DEFINES_MODULE'] = 'NO'
      end
    end
  end

  support_files_dir = File.join(installer.sandbox.root, 'Target Support Files')
  Dir.glob(File.join(support_files_dir, '*', '*.{debug,profile}.xcconfig')).each do |xcconfig_path|
    lines = File.readlines(xcconfig_path)
    other_ldflags_line = lines.find { |l| l.start_with?('OTHER_LDFLAGS = ') }
    next unless other_ldflags_line && other_ldflags_line.include?('RazorpayStandard')

    simulator_flags = other_ldflags_line.sub('OTHER_LDFLAGS = ', '').strip
    simulator_flags = simulator_flags.sub(/^\$\(inherited\)\s*/, '')
    simulator_flags = simulator_flags.gsub(/-framework "RazorpayStandard"\s*/, '')
    File.open(xcconfig_path, 'a') do |f|
      f.puts "OTHER_LDFLAGS[sdk=iphonesimulator*] = #{simulator_flags}"
    end
  end

  ['Pods-Runner', 'Pods-RunnerTests'].each do |target_name|
    frameworks_script = File.join(support_files_dir, target_name, "#{target_name}-frameworks.sh")
    next unless File.exist?(frameworks_script)

    content = File.read(frameworks_script)
    patched = content.gsub(
      /^(\s*)install_framework "(\$\{PODS_XCFRAMEWORKS_BUILD_DIR\}\/razorpay-pod\/RazorpayStandard\.framework)"$/,
      "\\1if [[ \"$PLATFORM_NAME\" != *simulator ]]; then\n\\1  install_framework \"\\2\"\n\\1fi"
    )
    File.write(frameworks_script, patched) if patched != content
  end
end
```

Confirmed working end-to-end: `flutter run -d <simulator-UDID>` builds,
installs, and launches; login screen renders correctly (Movigo logo,
"+91 Mobile Number" field, "Send OTP" button) with the app icon and
display name fixes from the App Store build also visible. A harmless
"Firebase not ready" / background-init platform-channel warning appears on
launch — expected on Simulator (no APNs), not blocking.

**If `pod install` or `flutter run` on Simulator ever needs redoing**: this
Podfile logic re-applies itself automatically every `pod install`, so
nothing manual is needed — just don't revert the `EXCLUDED_ARCHS` direction
(point 1 above) again.

## Separate, deferred issues (not blocking iOS, still unaddressed)

Same as before — this checkout was cloned from the published **Movigo
Customer app** (`/Users/user/Downloads/Retailer_app-2`,
`com.app.movigocustomer`) and only partially rebranded:

- **Android** `applicationId`/`namespace` in `android/app/build.gradle`
  still `com.app.movigocustomer`.
- **`android/app/google-services.json`** still the Customer app's Firebase
  config.
- **`pubspec.yaml`** name/description still say `movigo` / "Movigo Customer
  App" (cosmetic — doesn't affect the iOS build, which reads bundle
  ID/display name from `Info.plist` directly).
- **`android/key.properties`** points to a Windows-only path, unusable on
  this Mac — Android release signing not set up here.
- App icon design polish (see note under fix #3 above) and the iOS launch
  image (still Flutter's default placeholder, Xcode warns but doesn't
  block the build) — both explicitly deferred by user to "refine in a
  future update."

None of these block iOS submission. They matter if/when an Android release
build or full rebrand pass is wanted from this machine.

# Elychron iOS port

## Supported behavior

| Feature | iOS behavior |
| --- | --- |
| Tasks, calendar, focus, existing widgets | Existing Flutter and WidgetKit implementations; compile and launch on iOS 27 simulator |
| Share to Elychron | Share Extension saves text, image, or file in an App Group inbox. Separate shares are processed one at a time and retained until handled. Open Elychron after saving to choose a new or existing task. Runtime transfer still needs a signed App Group test. |
| Task reminders | Follows the latest upstream notification-only policy with local notification actions. The removed in-app alarm page and its theme settings stay removed. Task details retain the separate native alarm action. |
| Manual native alarm | iOS 26+ creates an independent one-time Elychron alarm. It is not added to Apple Clock and does not follow task edits. |
| Background scholarly refresh | Existing BGAppRefresh/Workmanager integration; iOS decides whether and when to run it. The 15-minute interval is only an earliest request. |
| Shortcuts quick add | Use Shortcuts’ “Open URLs” action with `elychron://todo/create`. The simulator recognizes the URL and displays Elychron as its target; opening the task editor still needs an unlocked simulator confirmation. |
| iPad layout | At iOS window widths of 900 logical pixels or more, the five main sections move to a sidebar and the page content is centered within 920 pixels. Narrow windows retain bottom tabs. Shared choice/report sheets become centered cards up to 560 pixels wide; sheet actions stay above the keyboard even when a window narrows. Task create/edit forms are centered within 720 pixels. |

## Build and signing

- Minimum iOS version: 15.0. Use Xcode 27 and the repository's Flutter SDK/dependencies.
- App IDs: `top.celechron.celechron` (Release) and `top.celechron.celechron.debug` (Debug/Profile), with corresponding widget and share extensions. App Groups are `group.top.celechron.celechron` and `group.top.celechron.celechron.debug`. Flutter Keychain options use the same groups, including the debug group in Profile builds.
- Xcode signing is Automatic. In Xcode, sign in to your Apple account and select the same team for Runner, WidgetExtensions, and ShareExtension. Keep App Groups enabled for all three targets. This upstream submission preserves the original Runner/WidgetExtensions signing settings; maintainers must provision the new ShareExtension for their own team.
- For a compile-only simulator check: `flutter build ios --simulator --no-codesign`. This package can launch, but does not include the simulator entitlements needed for shared Keychain access; login can fail with `-34018` before any network request.
- For simulator login and App Group runtime checks, build/run Runner from `ios/Runner.xcworkspace` in Xcode. Command-line builds must enable signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES CODE_SIGNING_REQUIRED=YES`) so Xcode embeds simulator entitlements. This uses an ad hoc simulator signature; it does not produce a device provisioning profile or signed IPA.
- For a compile-only device build: `flutter build ios --release --no-codesign`. This produces an **unsigned** `build/ios/iphoneos/Runner.app`; it is not an installable IPA.
- A signed IPA can be exported only after Xcode has a valid team, development certificate, provisioning profile, and target device. A free Personal Team can test on its own registered device for a limited period; broad distribution needs the paid Apple Developer Program. Never share an Apple password or verification code in chat.

## Merge strategy

The iOS native implementations live in `ios/ShareSupport`, `ios/ShareExtension`, and `ios/Runner/AppDelegate.swift`. The iPad layout is isolated in `lib/design/adaptive_window.dart`, `adaptive_sheet_frame.dart`, `adaptive_form_body.dart`, and `lib/page/tablet/adaptive_home_body.dart`, with small call sites in the existing pages. The iOS Xcode project changes to embed ShareExtension while preserving upstream Bundle IDs and App Groups. This branch merges upstream `1c02baf`, retaining its removal of the in-app alarm page and theme settings. Merge future upstream changes normally and inspect any conflicts before submitting. Expect to inspect `ios/Runner.xcodeproj/project.pbxproj` if future Elychron releases add Xcode targets.

## Verification

- Reminder update (2026-10-06): task cards and countdowns use the actual reminder target, fixing reminders that stayed pending until the hidden end time. iOS/iPadOS task forms now offer notification or native alarm per task, committed only when saving and stored in optionsBox without adapter changes. Sync requests are serialized and retain the newest state; recurring tasks inherit the choice; native rejection falls back to a notification. Compact iPad time panels scroll. Automated regression coverage includes state boundaries, save/cancel, delayed authorization, repeat inheritance, and window resizing. Device acceptance of these reminder updates is pending.
- Share resume fix (2026-10-06): the share stream observes `UIScene.didActivateNotification`, because the legacy AppDelegate foreground callback is not invoked by scene-based apps. The native regression test reproduces the missing warm-resume event before the fix and covers delivery, deduplication, cancel, and reconnect after it. A signed device build was installed, and the user confirmed that sharing a fresh photo and returning to the running app opens the new/existing task chooser.
- Login fix (2026-10-05): 828 Flutter tests pass, with zero static-analysis errors (existing warnings/info remain). The user confirmed real-account login on the fork's iPhone 18 Pro simulator; real-account login on the merged upstream version has not been repeated.
- Keychain permission checks: Debug, Profile, and Release entitlement configurations each successfully write, read, and delete a synthetic record on iPhone 18 Pro and iPad Pro simulators. The tests use this branch's `group.top.celechron.celechron` groups and do not access user credentials. Device provisioning and signed IPA login still need device acceptance.
- `test_native/keychain_smoke/main.swift` tests OS Keychain permissions without user credentials. Compile for `arm64-apple-ios15.0-simulator`, linking `Security` and embedding the generated simulator entitlement plist with `-Xlinker -sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker <Runner.app-Simulated.xcent>`. Run with `xcrun simctl spawn <device-id> <binary> group.top.celechron.celechron.debug`; all status codes must be `0` and `matches=true`.
- The Flutter suite includes iPad navigation state, sheet sizing/scrolling/keyboard avoidance across window resizing, task form resizing, and CAS rejection-message redaction tests.
- `swiftc -module-cache-path /private/tmp/elychron-swift-module-cache ios/ShareSupport/ShareInbox.swift test_native/share_inbox/main.swift -o /private/tmp/elychron-share-inbox-test && /private/tmp/elychron-share-inbox-test`: passes.
- Earlier port checks: iOS 27 simulator build and launch passed. Share delivery and AlarmKit authorization were not exercised end to end.
- `elychron://todo/create`: recognized by iOS in an earlier simulator check; the task-editor flow has not been fully accepted.
- Current merged-upstream builds (2026-10-05): Debug iOS simulator, Profile iOS device, and Release iOS device all compile successfully without device signing. Simulator login must use the signing-enabled workflow above.
- iOS 27 simulator build after iPad changes: passes. The unsigned app installed and launched on iPad mini (A17 Pro), iPad Pro 13-inch (M5), and iPhone 18 Pro. An iPad Pro portrait screenshot shows the five-section sidebar and centered content.
- Interactive checks of all five tabs, task create/edit, sheet actions, landscape rotation, and hardware keyboard remain unverified. Widget tests cover responsive layouts and keyboard inset, but do not replace device interactions.

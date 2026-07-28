Customer app RC1 updates:
- fixed booking_status socket notifyListeners issue
- upgraded webview_flutter to ^4.10.0 and migrated ContentScreen to WebViewWidget API
- added android/key.properties.example
- admin notes are separate

Manual still required:
- replace rzp_live_REPLACE_ME with real live key
- add android/key.properties with real keystore values
- run flutter pub get and release build tests

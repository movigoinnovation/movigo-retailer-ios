import 'dart:math';

/// Generates a Google Places `sessiontoken` — a per-search-session id that
/// bundles an Autocomplete typing sequence + its terminating Details call
/// into one billed unit instead of billing every keystroke request
/// separately. Not a real UUID (no `uuid` package dependency needed) — Google
/// only requires the token be a random, sufficiently unique string per
/// session; a 32-char hex string satisfies that.
class PlacesSessionToken {
  static final Random _rand = Random.secure();

  static String generate() {
    const chars = '0123456789abcdef';
    return List.generate(32, (_) => chars[_rand.nextInt(16)]).join();
  }
}

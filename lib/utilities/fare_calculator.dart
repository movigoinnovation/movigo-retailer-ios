/// fare_calculator.dart — MOVIGO PRICING ENGINE (Dart)
///
/// Emergency local fallback ONLY — used when backend API is unreachable.
/// Backend /booking/price_estimate is always the source of truth.
/// These slabs MUST stay in sync with pricing.js FINAL_PRICING_SLABS.
///
/// LAST UPDATED: 2026-05-26
/// R_2W:       base=35,  p2to5=8,  a5=10
/// R_SCOOTER:  base=40,  p2to5=8,  a5=12
/// R_MINI_3W:  base=100, p2to5=10, a5=13
/// R_E_LOADER: base=160, p2to5=16, a5=20
/// R_3W:       base=210, p2to5=14, a5=18
/// R_TATA_ACE: base=320, p2to5=22, a5=28

class FareResult {
  final int    totalFare;
  final int    platformFee;
  final int    totalPayable;
  final int    ceiledDistanceKm;
  final double rawDistanceKm;
  final int    baseFare;
  final int    distanceCharge;

  const FareResult({
    required this.totalFare,
    required this.platformFee,
    required this.totalPayable,
    required this.ceiledDistanceKm,
    required this.rawDistanceKm,
    required this.baseFare,
    required this.distanceCharge,
  });

  @override
  String toString() =>
      'FareResult(delivery: ₹$totalFare, platformFee: ₹$platformFee, total: ₹$totalPayable, km: $ceiledDistanceKm)';
}

class PlatformFee {
  static const Map<String, int> _byTag = {
    'C_2W': 3, 'R_2W': 3, 'R_SCOOTER': 3,
    'C_3W': 5, 'R_3W': 5, 'R_E_LOADER': 5, 'R_MINI_3W': 5,
    'C_4W': 10, 'R_TATA_ACE': 10,
  };
  static const Map<int, int> _byWheel = {2: 3, 3: 5, 4: 10};

  static int forTag(String? tag, {int wheelCount = 2}) {
    if (tag != null && _byTag.containsKey(tag)) return _byTag[tag]!;
    return _byWheel[wheelCount] ?? 0;
  }
}

class FareCalculator {
  // ── Slabs — keep in sync with server/src/utils/pricing.js ────────────────
  static const Map<String, _VehiclePricing> _byTag = {
    'C_2W':       _VehiclePricing(baseFare: 35,  perKm2to5: 8,  after5PerKm: 10),
    'R_2W':       _VehiclePricing(baseFare: 35,  perKm2to5: 8,  after5PerKm: 10),
    'R_SCOOTER':  _VehiclePricing(baseFare: 40,  perKm2to5: 8,  after5PerKm: 12),
    'C_3W':       _VehiclePricing(baseFare: 210, perKm2to5: 14, after5PerKm: 18),
    'R_3W':       _VehiclePricing(baseFare: 210, perKm2to5: 14, after5PerKm: 18),
    'R_E_LOADER': _VehiclePricing(baseFare: 160, perKm2to5: 16, after5PerKm: 20),
    'R_MINI_3W':  _VehiclePricing(baseFare: 100, perKm2to5: 10, after5PerKm: 13),
    'C_4W':       _VehiclePricing(baseFare: 320, perKm2to5: 22, after5PerKm: 28),
    'R_TATA_ACE': _VehiclePricing(baseFare: 320, perKm2to5: 22, after5PerKm: 28),
  };

  static const Map<int, _VehiclePricing> _byWheel = {
    2: _VehiclePricing(baseFare: 35,  perKm2to5: 8,  after5PerKm: 10),
    3: _VehiclePricing(baseFare: 210, perKm2to5: 14, after5PerKm: 18),
    4: _VehiclePricing(baseFare: 320, perKm2to5: 22, after5PerKm: 28),
  };

  static FareResult calculate({
    required int    wheelCount,
    required double rawDistanceKm,
    double   modifier    = 1.0,
    String?  requiredTag,
  }) {
    final String tag = (requiredTag ?? '').trim().toUpperCase();
    final p = _byTag[tag] ?? _byWheel[wheelCount];
    if (p == null) {
      throw ArgumentError('Invalid wheelCount: $wheelCount. Must be 2, 3, or 4.');
    }

    final int km = rawDistanceKm.ceil();
    int fare;

    final int after8 = p.after_8_per_km ?? p.after5PerKm;
    final int after11 = p.after_11_per_km ?? 0;
    final bool useFallback = (after11 == 0 || after11 == after8);

    if (km <= 2) {
      fare = p.baseFare;
    } else if (km <= 5) {
      fare = p.baseFare + (km - 2) * p.perKm2to5;
    } else if (km <= 8) {
      fare = p.baseFare + 3 * p.perKm2to5 + (km - 5) * p.after5PerKm;
    } else if (km <= 11 || useFallback) {
      fare = p.baseFare + 3 * p.perKm2to5 + 3 * p.after5PerKm + (km - 8) * after8;
    } else {
      fare = p.baseFare + 3 * p.perKm2to5 + 3 * p.after5PerKm + 3 * after8 + (km - 11) * after11;
    }

    final int baseFareForBreakup = fare < p.baseFare ? fare : p.baseFare;
    final int distanceCharge     = fare - baseFareForBreakup;
    final int pFee               = PlatformFee.forTag(tag, wheelCount: wheelCount);

    return FareResult(
      totalFare:        fare,
      platformFee:      pFee,
      totalPayable:     fare + pFee,
      ceiledDistanceKm: km,
      rawDistanceKm:    rawDistanceKm,
      baseFare:         baseFareForBreakup,
      distanceCharge:   distanceCharge,
    );
  }
}

class _VehiclePricing {
  final int baseFare;
  final int perKm2to5;
  final int after5PerKm;
  final int? after_8_per_km;
  final int? after_11_per_km;

  const _VehiclePricing({
    required this.baseFare,
    required this.perKm2to5,
    required this.after5PerKm,
    this.after_8_per_km,
    this.after_11_per_km,
  });
}

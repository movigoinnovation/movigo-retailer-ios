import 'package:flutter_test/flutter_test.dart';
import 'package:movigo/utilities/fare_calculator.dart';

void main() {
  group('Retailer App FareCalculator Tests', () {
    test('Test 1 - Under 2km base fare', () {
      final res = FareCalculator.calculate(
        wheelCount: 2,
        rawDistanceKm: 1.5,
        requiredTag: 'R_2W',
      );
      expect(res.totalFare, equals(35));
      expect(res.platformFee, equals(3));
      expect(res.totalPayable, equals(38));
    });

    test('Test 2 - Under 5km slab calculation', () {
      final res = FareCalculator.calculate(
        wheelCount: 2,
        rawDistanceKm: 4.2, // 5km ceiled
        requiredTag: 'R_2W',
      );
      // base(35) + (5 - 2) * 8 = 35 + 24 = 59
      expect(res.totalFare, equals(59));
      expect(res.platformFee, equals(3));
    });

    test('Test 3 - Under 8km slab calculation', () {
      final res = FareCalculator.calculate(
        wheelCount: 2,
        rawDistanceKm: 6.8, // 7km ceiled
        requiredTag: 'R_2W',
      );
      // base(35) + 3 * 8 + (7 - 5) * 10 = 35 + 24 + 20 = 79
      expect(res.totalFare, equals(79));
    });

    test('Test 4 - 9km R_2W ride with new sub-tier 8-11km', () {
      // For R_2W, after5PerKm is 10, after_8_per_km is not defined (defaults to after5PerKm = 10)
      // distance ceiled is 9.
      // base(35) + 3 * 8 + 3 * 10 + (9 - 8) * 10 = 35 + 24 + 30 + 10 = 99
      final res = FareCalculator.calculate(
        wheelCount: 2,
        rawDistanceKm: 9.0,
        requiredTag: 'R_2W',
      );
      expect(res.totalFare, equals(99));
    });

    test('Test 5 - 12km R_2W ride with new sub-tier > 11km fallback', () {
      // For R_2W, after_11_per_km is not defined (defaults to 0, which falls back to after_8_per_km = 10)
      // distance ceiled is 12.
      // base(35) + 3 * 8 + 3 * 10 + (12 - 8) * 10 = 35 + 24 + 30 + 40 = 129
      final res = FareCalculator.calculate(
        wheelCount: 2,
        rawDistanceKm: 12.0,
        requiredTag: 'R_2W',
      );
      expect(res.totalFare, equals(129));
    });
  });
}

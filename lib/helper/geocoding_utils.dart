/// Shared reverse-geocoding helper used by all location pickers.
///
/// Google's Geocoding API returns multiple results for a lat/lng, sorted by
/// type specificity. The naive approach of taking `results.first['formatted_address']`
/// often returns a postal-code-level result like "123, Indore, MP 453331, India"
/// when there is no named street at the tapped point.
///
/// This utility instead:
///   1. Picks the most specific result (street_address > premise > establishment
///      > route > sublocality > anything).
///   2. Builds the display string from individual address_components rather than
///      from formatted_address, so we can drop uninformative parts (bare numbers,
///      country, state).
///
/// Result format: "Establishment / Street, Sublocality, City"
/// Example:        "Vijay Nagar Square, Vijay Nagar, Indore"

// Result-type priority (higher index = more specific, preferred)
const _typePriority = [
  'postal_code',
  'administrative_area_level_2',
  'locality',
  'sublocality',
  'sublocality_level_2',
  'sublocality_level_1',
  'neighborhood',
  'route',
  'intersection',
  'subpremise',
  'premise',
  'street_address',
  'establishment',
  'point_of_interest',
];

int _resultScore(Map result) {
  final types = List<String>.from(result['types'] ?? []);
  int best = -1;
  for (final t in types) {
    final idx = _typePriority.indexOf(t);
    if (idx > best) best = idx;
  }
  return best;
}

/// Pick the highest-scoring result and build a clean address string from its
/// address_components.  Falls back to `formatted_address` only as a last resort.
String bestAddressFromGeoResults(List results) {
  if (results.isEmpty) return '';

  // Sort a copy by score descending (most specific first)
  final sorted = List.of(results)
    ..sort((a, b) => _resultScore(b as Map).compareTo(_resultScore(a as Map)));

  // Try each result from most → least specific until we get something useful
  for (final r in sorted) {
    final addr = _buildFromComponents(r as Map);
    if (addr.isNotEmpty) return addr;
  }

  // Last resort: formatted_address of the most specific result
  return (sorted.first as Map)['formatted_address']?.toString().trim() ?? '';
}

String _buildFromComponents(Map result) {
  final raw = result['address_components'] as List? ?? [];

  String establishment = '';
  String premise = '';
  String streetNumber = '';
  String route = '';
  String sublocality1 = '';
  String sublocality = '';
  String neighborhood = '';
  String locality = '';

  for (final comp in raw) {
    final types = List<String>.from(comp['types'] ?? []);
    final name = (comp['long_name'] ?? '').toString().trim();
    if (name.isEmpty) continue;

    if (types.contains('point_of_interest') || types.contains('establishment')) {
      establishment = name;
    } else if (types.contains('premise')) {
      premise = name;
    } else if (types.contains('street_number')) {
      streetNumber = name;
    } else if (types.contains('route')) {
      route = name;
    } else if (types.contains('sublocality_level_1')) {
      sublocality1 = name;
    } else if (types.contains('sublocality') && sublocality.isEmpty) {
      sublocality = name;
    } else if (types.contains('neighborhood') && neighborhood.isEmpty) {
      neighborhood = name;
    } else if (types.contains('locality')) {
      locality = name;
    }
  }

  final parts = <String>[];

  // Named place / premise
  if (establishment.isNotEmpty) {
    parts.add(establishment);
  } else if (premise.isNotEmpty) {
    parts.add(premise);
  }

  // Street: only include route if it has a real name (not a bare number)
  final routeIsNamed = route.isNotEmpty && !RegExp(r'^\d+$').hasMatch(route);
  if (routeIsNamed) {
    final street = streetNumber.isNotEmpty ? '$streetNumber, $route' : route;
    // Avoid duplicating the premise name if it equals the route
    if (parts.isEmpty || parts.last.toLowerCase() != street.toLowerCase()) {
      parts.add(street);
    }
  }

  // Area / neighbourhood
  final area = sublocality1.isNotEmpty
      ? sublocality1
      : sublocality.isNotEmpty
          ? sublocality
          : neighborhood;
  if (area.isNotEmpty &&
      !parts.any((p) => p.toLowerCase() == area.toLowerCase())) {
    parts.add(area);
  }

  // City
  if (locality.isNotEmpty &&
      !parts.any((p) => p.toLowerCase() == locality.toLowerCase())) {
    parts.add(locality);
  }

  // We need at least two meaningful parts to call this useful
  if (parts.length >= 2) return parts.join(', ');
  if (parts.length == 1 && locality.isNotEmpty) return parts.join(', ');
  if (parts.isNotEmpty) return parts.join(', ');

  // Fall through to formatted_address for this specific result
  return '';
}

// Shared Google Maps style for all live-tracking maps — a flat light-grey
// base (Porter-style) with everything muted so the white roads read as the
// dominant, "thick" element and the driver route/markers pop.
const String kPorterMapStyle = '''
[
  {"elementType":"geometry","stylers":[{"color":"#e9e9e9"}]},
  {"elementType":"labels.icon","stylers":[{"visibility":"off"}]},
  {"elementType":"labels.text.fill","stylers":[{"color":"#8f8f8f"}]},
  {"elementType":"labels.text.stroke","stylers":[{"color":"#f2f2f2"}]},
  {"featureType":"administrative","elementType":"geometry","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.land_parcel","stylers":[{"visibility":"off"}]},
  {"featureType":"administrative.neighborhood","stylers":[{"visibility":"off"}]},
  {"featureType":"poi","stylers":[{"visibility":"off"}]},
  {"featureType":"transit","stylers":[{"visibility":"off"}]},
  {"featureType":"landscape","elementType":"geometry","stylers":[{"color":"#e3e3e3"}]},
  {"featureType":"landscape.man_made","elementType":"geometry","stylers":[{"color":"#e0e0e0"}]},
  {"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road","elementType":"geometry.stroke","stylers":[{"color":"#d4d4d4"}]},
  {"featureType":"road","elementType":"labels","stylers":[{"visibility":"off"}]},
  {"featureType":"road.highway","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.highway","elementType":"geometry.stroke","stylers":[{"color":"#c4c4c4"}]},
  {"featureType":"road.arterial","elementType":"geometry.fill","stylers":[{"color":"#ffffff"}]},
  {"featureType":"road.arterial","elementType":"geometry.stroke","stylers":[{"color":"#d0d0d0"}]},
  {"featureType":"water","elementType":"geometry","stylers":[{"color":"#cdd4d8"}]}
]
''';

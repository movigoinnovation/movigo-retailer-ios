import 'package:flutter/material.dart';
import 'package:movigo/helper/MapImage_screen.dart';

/// RTrackDriverScreen now redirects to the live MapImageScreen.
class RTrackDriverScreen extends StatelessWidget {
  final String? userId;
  final String? driverId;
  final String? bookingId;
  final String? vehicleName;
  final String? vehicleImage;
  final double? targetLat;
  final double? targetLng;
  final double? pickupLat;
  final double? pickupLng;
  final double? dropLat;
  final double? dropLng;
  final String? bookingStatus;

  const RTrackDriverScreen({
    super.key,
    this.userId,
    this.driverId,
    this.bookingId,
    this.vehicleName,
    this.vehicleImage,
    this.targetLat,
    this.targetLng,
    this.pickupLat,
    this.pickupLng,
    this.dropLat,
    this.dropLng,
    this.bookingStatus,
  });

  @override
  Widget build(BuildContext context) {
    return MapImageScreen(
      userId: userId ?? '',
      bookingId: bookingId ?? '',
      driverId: driverId ?? '',
      vehicleName: vehicleName,
      vehicleImage: vehicleImage,
      targetLat: targetLat ?? dropLat,
      targetLng: targetLng ?? dropLng,
      pickupLat: pickupLat,
      pickupLng: pickupLng,
      dropLat: dropLat,
      dropLng: dropLng,
      bookingStatus: bookingStatus,
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class AppShimmers {
  /// Circle Shimmer (Profile image, icons)
  static Widget circle({
    required double size,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: size,
        width: size,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  ///Rectangle Shimmer (text fields, containers)
  static Widget rect({
    required double height,
    required double width,
    double radius = 12,
  }) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      ),
    );
  }

  /// Line Shimmer (small text)
  static Widget line({double width = 120, double height = 12}) {
    return rect(height: height, width: width, radius: 8);
  }

  /// Square Shimmer (icons, small boxes)
  static Widget square({required double size}) {
    return rect(height: size, width: size, radius: 10);
  }
}

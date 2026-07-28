import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';

class CircleShimmer extends StatelessWidget {
  final double size;

  const CircleShimmer({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Shimmer.fromColors(
      baseColor: Colors.grey[300]!,
      highlightColor: Colors.grey[100]!,
      child: Container(
        height: size,
        width: size,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:movigo/utilities/app_color.dart';

class WalletTabShimmer extends StatelessWidget {
  const WalletTabShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: 6,
      itemBuilder: (context, index) {
        return Shimmer.fromColors(
          baseColor: AppColor.greyColor.withOpacity(0.25),
          highlightColor: Colors.white,
          child: Container(
            margin: const EdgeInsets.only(bottom: 14),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                /// LEFT SIDE
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _box(width: 140, height: 12),
                    const SizedBox(height: 8),
                    _box(width: 180, height: 14),
                    const SizedBox(height: 8),
                    _box(width: 120, height: 12),
                  ],
                ),

                /// AMOUNT
                _box(width: 60, height: 14),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _box({required double width, required double height}) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
      ),
    );
  }
}

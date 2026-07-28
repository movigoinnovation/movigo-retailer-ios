import 'package:flutter/material.dart';

class RetailerHomeShimmer extends StatelessWidget {
  const RetailerHomeShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    Widget box({double? h, double? w, BorderRadius? r}) => Container(
          height: h,
          width: w,
          decoration: BoxDecoration(
            color: Colors.grey.shade300,
            borderRadius: r ?? BorderRadius.circular(12),
          ),
        );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
      child: Column(
        children: [
          // Stats cards shimmer
          Row(
            children: [
              Expanded(child: box(h: size.height * 0.18, r: BorderRadius.circular(20))),
              SizedBox(width: size.width * 0.04),
              Expanded(
                child: Column(
                  children: [
                    box(h: size.height * 0.08, r: BorderRadius.circular(16)),
                    SizedBox(height: size.height * 0.02),
                    box(h: size.height * 0.08, r: BorderRadius.circular(16)),
                  ],
                ),
              ),
            ],
          ),
          SizedBox(height: size.height * 0.03),

          // Booking card shimmer
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                box(h: 48, w: 48, r: BorderRadius.circular(24)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      box(h: 12, w: size.width * 0.4),
                      const SizedBox(height: 8),
                      box(h: 10, w: size.width * 0.6),
                      const SizedBox(height: 8),
                      box(h: 10, w: size.width * 0.5),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

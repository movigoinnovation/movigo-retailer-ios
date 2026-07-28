import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:movigo/utilities/app_color.dart';

class NotificationShimmerScreen extends StatelessWidget {
  static String routeName = './NotificationShimmerScreen';

  const NotificationShimmerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: AppColor.secondaryColor,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.05),
          child: Column(
            children: [
              SizedBox(height: size.height * 0.02),

              /// ===== AppBar Shimmer =====
              Shimmer.fromColors(
                baseColor: Colors.grey.shade300,
                highlightColor: Colors.grey.shade100,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        _box(size.width * 0.08, size.width * 0.08, radius: 10),
                        SizedBox(width: size.width * 0.03),
                        _box(20, size.width * 0.35),
                      ],
                    ),
                    _box(14, size.width * 0.18),
                  ],
                ),
              ),

              SizedBox(height: size.height * 0.03),

              /// ===== Notification List =====
              Expanded(
                child: ListView.builder(
                  itemCount: 6,
                  itemBuilder: (context, index) {
                    return _notificationShimmerCard(size);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ===== Notification Card =====
  Widget _notificationShimmerCard(Size size) {
    return Padding(
      padding: EdgeInsets.only(bottom: size.height * 0.02),
      child: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Container(
          padding: EdgeInsets.all(size.width * 0.04),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              /// Icon shimmer
              _box(size.width * 0.1, size.width * 0.1, radius: 12),

              SizedBox(width: size.width * 0.04),

              /// Content shimmer
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    /// Title
                    _box(14, size.width * 0.55),
                    SizedBox(height: size.height * 0.01),

                    /// Description
                    _box(12, size.width * 0.7),
                    SizedBox(height: size.height * 0.01),

                    /// Time
                    Align(
                      alignment: Alignment.centerRight,
                      child: _box(10, size.width * 0.25),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// ===== Reusable shimmer box =====
  Widget _box(double height, double width, {double radius = 6}) {
    return Container(
      height: height,
      width: width,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

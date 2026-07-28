import 'package:flutter/material.dart';
import 'package:shimmer/shimmer.dart';
import 'package:movigo/utilities/app_color.dart';

class BookingDetailShimmer extends StatelessWidget {
  const BookingDetailShimmer({super.key});

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    Widget box({
      double height = 16,
      double width = double.infinity,
      double radius = 8,
    }) {
      return Container(
        height: height,
        width: width,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(radius),
        ),
      );
    }

    return Scaffold(
      backgroundColor: Colors.white,
      body: Shimmer.fromColors(
        baseColor: Colors.grey.shade300,
        highlightColor: Colors.grey.shade100,
        child: Stack(
          children: [
            /// TOP IMAGE SHIMMER
            Container(
              height: size.height * 0.35,
              width: size.width,
              color: Colors.white,
            ),

            SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(height: size.height * 0.15),

                  /// WHITE CARD
                  Container(
                    width: size.width,
                    padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.05,
                      vertical: size.height * 0.03,
                    ),
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(28),
                        topRight: Radius.circular(28),
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        box(height: 22, width: 150),
                        SizedBox(height: size.height * 0.04),

                        /// BOOKING ID + DATE
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            box(height: 16, width: 120),
                            Column(
                              children: [
                                box(height: 12, width: 70),
                                const SizedBox(height: 6),
                                box(height: 12, width: 60),
                              ],
                            )
                          ],
                        ),

                        SizedBox(height: size.height * 0.04),

                        /// PICKUP / DROP
                        box(height: 14),
                        SizedBox(height: size.height * 0.03),
                        box(height: 14),

                        SizedBox(height: size.height * 0.05),

                        /// DRIVER TITLE
                        box(height: 18, width: 140),
                        SizedBox(height: size.height * 0.02),

                        /// DRIVER ROW
                        Row(
                          children: [
                            box(height: 48, width: 48, radius: 24),
                            SizedBox(width: size.width * 0.03),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  box(height: 14, width: 120),
                                  const SizedBox(height: 8),
                                  box(height: 14, width: 160),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      box(height: 44, width: size.width * 0.3),
                                      SizedBox(width: size.width * 0.03),
                                      box(height: 44, width: size.width * 0.3),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),

                        SizedBox(height: size.height * 0.05),

                        /// NOTE
                        box(height: 16, width: 180),
                        SizedBox(height: 8),
                        box(height: 12),

                        SizedBox(height: size.height * 0.05),

                        /// IMAGES
                        SizedBox(
                          height: size.height * 0.16,
                          child: ListView.separated(
                            scrollDirection: Axis.horizontal,
                            itemCount: 2,
                            separatorBuilder: (_, __) =>
                                SizedBox(width: size.width * 0.03),
                            itemBuilder: (_, __) => box(
                              height: size.height * 0.16,
                              width: size.width * 0.42,
                              radius: 12,
                            ),
                          ),
                        ),

                        SizedBox(height: size.height * 0.05),

                        /// PRICE BOX
                        Container(
                          padding: EdgeInsets.all(size.width * 0.04),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                          ),
                          child: Column(
                            children: List.generate(
                              4,
                              (index) => Padding(
                                padding: const EdgeInsets.symmetric(vertical: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    box(height: 14, width: 120),
                                    box(height: 14, width: 60),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),

                        SizedBox(height: size.height * 0.05),

                        /// BUTTON
                        box(
                          height: 52,
                          width: size.width,
                          radius: 12,
                        ),

                        SizedBox(height: size.height * 0.1),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

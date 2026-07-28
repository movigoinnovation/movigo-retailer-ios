import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';

class CommonAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onMoreTap;

  const CommonAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.onMoreTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return SafeArea(
      bottom: false,
      child: Container(
        color: Colors.white, // Status bar background white
        padding: EdgeInsets.symmetric(
          // horizontal: size.width * 0.01,
          vertical: size.height * 0.03, // 0.8% screen height
        ),

        child: Row(
          children: [
            /// Back Button
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: Image.asset(
                AppImage.backimage,
                height: 40,
                width: 40,
              ),
            ),

            SizedBox(width: size.width * 0.04),

            /// Title
            Text(
              title,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: AppFont.fontFamily,
                color: AppColor.blackColor,
              ),
            ),

            const Spacer(),

            /// More Button (optional)
            if (onMoreTap != null)
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: onMoreTap,
                child: Image.asset(
                  AppImage.threedot,
                  height: 40,
                  width: 40,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

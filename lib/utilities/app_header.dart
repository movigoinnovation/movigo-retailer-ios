import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';

class CommonAppBar extends StatelessWidget {
  final String title;
  final VoidCallback? onBack;
  final VoidCallback? onMoreTap;
  final Color backgroundColor;

  const CommonAppBar({
    super.key,
    required this.title,
    this.onBack,
    this.onMoreTap,
    this.backgroundColor = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    // Edge-to-edge: the coloured slab flows all the way behind the status
    // bar (SafeArea only pads the row's content, it doesn't clip the
    // background), so there's no hard seam between the status bar and the
    // header on any screen size. Height is fixed in logical pixels rather
    // than a percentage of screen height, which used to blow up on iPad's
    // much taller viewport and crowd/clip the title.
    return Container(
      width: double.infinity,
      color: backgroundColor,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 14),
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
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),
              ),

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
      ),
    );
  }
}

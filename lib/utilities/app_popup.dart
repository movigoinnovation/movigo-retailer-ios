import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';

import 'app_color.dart';

class AppPopup extends StatelessWidget {
  final String icon;
  final String title;
  final String subTitle;
  final Widget child;
  final VoidCallback? onIconTap;

  const AppPopup({
    super.key,
    required this.icon,
    required this.title,
    required this.subTitle,
    required this.child,
    this.onIconTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return AlertDialog(
      insetPadding: const EdgeInsets.all(0),
      elevation: 0,
      backgroundColor: Colors.transparent,
      contentPadding: EdgeInsets.zero,
      content: Container(
          width: size.width * 90 / 100,
          padding: EdgeInsets.all(size.width * 5 / 100)
              .copyWith(top: 0)
              .copyWith(bottom: size.width * 7 / 100),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            color: AppColor.secondaryColor,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Transform.translate(
                offset: const Offset(0, 15),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      // child: Image.asset(
                      //   AppImage.crossIconBold,
                      //   width: size.width * 4 / 100,
                      //   height: size.height * 4 / 100,
                      // ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: EdgeInsets.all(size.width * 2 / 100),
                decoration: const BoxDecoration(
                    color: AppColor.backgroundColor, shape: BoxShape.circle),
                child: CircleAvatar(
                  backgroundColor: AppColor.themeColor,
                  radius: size.width * 7 / 100,
                  // child: Image.asset(
                  //   icon,
                  //   color: AppColor.secondaryColor,
                  //   width: size.width * 8 / 100,
                  //   height: size.width * 8 / 100,
                  // ),
                  child: GestureDetector(
                    onTap: onIconTap,
                    child: Image.asset(
                      icon,
                      color: AppColor.secondaryColor,
                      width: size.width * 8 / 100,
                      height: size.width * 8 / 100,
                    ),
                  ),
                ),
              ),
              SizedBox(
                height: size.height * 1 / 100,
              ),
              SizedBox(
                width: size.width * 70 / 100,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w600,
                      // fontFamily: AppFont.fontFamily,
                      color: AppColor.primaryColor),
                ),
              ),
              SizedBox(
                height: size.height * 1 / 100,
              ),
              Text(
                subTitle,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w400,
                    // fontFamily: AppFont.fontFamily,
                    color: AppColor.primaryColor),
              ),
              child
            ],
          )),
    );
  }
}

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:movigo/utilities/app_image.dart';
import 'app_color.dart';
import 'app_font.dart';

class AppHeader extends StatelessWidget {
  final String text;
  final Function onPress;
  const AppHeader({
    super.key,
    required this.text,
    required this.onPress,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 90 / 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              onPress();
            },
            child: Container(
              height: MediaQuery.of(context).size.width * 12 / 100,
              width: MediaQuery.of(context).size.width * 12 / 100,
              color: AppColor.transparentColor,
              padding: const EdgeInsets.only(left: 14),
              alignment: Alignment.center,
              child: Image.asset(
                AppImage.backimage,
                fit: BoxFit.cover,
                height: MediaQuery.of(context).size.width * 6 / 100,
                width: MediaQuery.of(context).size.width * 6 / 100,
              ),
            ),
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 65 / 100,
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColor.primaryColor,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFont.fontFamily)),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.width * 12 / 100,
            width: MediaQuery.of(context).size.width * 5 / 100,
          ),
        ],
      ),
    );
  }
}

class AppHeaderSecondary extends StatelessWidget {
  final String text;
  final Function onPress;

  const AppHeaderSecondary(
      {super.key, required this.text, required this.onPress});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: MediaQuery.of(context).size.width * 100 / 100,
      height: MediaQuery.of(context).size.height * 7 / 100,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          GestureDetector(
            onTap: () {
              onPress();
            },
            child: Container(
              height: MediaQuery.of(context).size.width * 12 / 100,
              width: MediaQuery.of(context).size.width * 12 / 100,
              color: AppColor.transparentColor,
              //  padding: const EdgeInsets.only(left: 18),
              alignment: Alignment.center,
              child: Image.asset(
                AppImage.backimage,
                fit: BoxFit.cover,
                height: MediaQuery.of(context).size.width * 5 / 100,
                width: MediaQuery.of(context).size.width * 5 / 100,
              ),
            ),
          ),
          SizedBox(
            width: MediaQuery.of(context).size.width * 70 / 100,
            child: Text(text,
                textAlign: TextAlign.center,
                style: const TextStyle(
                    color: AppColor.secondaryColor,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    fontFamily: AppFont.fontFamily)),
          ),
          SizedBox(
            height: MediaQuery.of(context).size.width * 12 / 100,
            width: MediaQuery.of(context).size.width * 12 / 100,
          ),
        ],
      ),
    );
  }
}

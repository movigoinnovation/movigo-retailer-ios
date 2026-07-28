import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

import 'app_color.dart';
import 'app_font.dart';

class AppButton extends StatelessWidget {
  final String text;
  final Function onPress;
  final double? width;
  final Color? bgColor;
  final Color? borderColor;
  final Color? textColor;
  final bool? isLoading;

  const AppButton({
    Key? key,
    required this.text,
    required this.onPress,
    this.width,
    this.bgColor,
    this.borderColor,
    this.textColor,
    this.isLoading,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      onTap: () {
        onPress();
      },
      child: Container(
          width: width ?? size.width * 90 / 100,
          height: size.height * 6 / 100,
          decoration: BoxDecoration(
            color: bgColor ?? AppColor.themeColor,
            border: Border.all(color: borderColor ?? AppColor.themeColor),
            borderRadius: const BorderRadius.all(Radius.circular(16)),
          ),
          alignment: Alignment.center,
          child: Text(
            text,
            style: TextStyle(
                color: textColor ?? AppColor.secondaryColor,
                fontWeight: FontWeight.w500,
                fontSize: 18),
          )),
    );
  }
}

class CircleContainerButton extends StatelessWidget {
  const CircleContainerButton({
    super.key,
    this.onTap,
    this.padding,
    required this.icon,
    this.iconSize,
  });

  final Function()? onTap;
  final EdgeInsetsGeometry? padding;
  final String icon;
  final double? iconSize;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size.width * 12 / 100,
        padding: padding ?? EdgeInsets.all(size.width * 3 / 100),
        decoration: BoxDecoration(
          color: AppColor.secondaryColor,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              offset: const Offset(0, 2),
              blurRadius: 8,
              spreadRadius: 1.5,
              color: AppColor.themeColor.withOpacity(
                0.1,
              ),
            ),
          ],
        ),
        child: Image.asset(
          icon,
          width: iconSize ?? size.width * 5 / 100,
          height: iconSize ?? size.width * 5 / 100,
        ),
      ),
    );
  }
}

class CustomTextButton extends StatelessWidget {
  final String text;
  final TextStyle? textStyle;
  final Function()? onTap;

  const CustomTextButton({
    super.key,
    required this.text,
    this.onTap,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: AppColor.themeColor,
          decorationColor: AppColor.themeColor,
          decoration: TextDecoration.underline,
          fontFamily: AppFont.fontFamily,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'app_image.dart';

class CommonTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final TextInputType keyboardType;
  final int? maxLength;
  final double height;
  final FormFieldValidator<String>? validator;
  final bool readOnly;
  final VoidCallback? onTap;
  final Widget? suffixIcon;
  final bool isMultiline;
  final bool showBorder;
  final Color? backgroundColor;


  const CommonTextField({
    super.key,
    required this.controller,
    required this.hintText,
    this.keyboardType = TextInputType.text,
    this.maxLength,
    this.height = 0.065,
    this.validator,
    this.readOnly = false,
    this.onTap,
    this.suffixIcon,
    this.isMultiline = false,          //
    this.showBorder = false,           //
    this.backgroundColor,              //
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Container(
      width: size.width,
      height: size.height * height,
      decoration: BoxDecoration(
        color: backgroundColor ?? AppColor.textFiledColor,
        borderRadius: BorderRadius.circular(13),
        border: showBorder
            ? Border.all(
          color: AppColor.hintTextColor.withOpacity(0.2),
        )
            : null,
      ),
      child: TextFormField(
        controller: controller,
        keyboardType:
        isMultiline ? TextInputType.multiline : keyboardType,
        maxLines: isMultiline ? null : 1,
        readOnly: readOnly,
        onTap: onTap,
        style: const TextStyle(
          fontSize: 16,
          fontFamily: AppFont.fontFamily,
        ),
        decoration: InputDecoration(
          border: InputBorder.none,
          hintText: hintText,
          suffixIcon: suffixIcon,
          contentPadding: const EdgeInsets.all(14),
          hintStyle: TextStyle(
            color: AppColor.hintTextColor,
            fontSize: 14,
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w400,

          ),
        ),
      ),
    );
  }
}

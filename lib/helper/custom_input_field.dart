import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/phone_number_formatter.dart';

class CustomInputField extends StatelessWidget {
  final TextEditingController controller;
  final String? hintText;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? prefixText;
  final TextInputType keyboardType;
  final bool readOnly;
  final VoidCallback? onTap;
  final int? maxLength;
  final bool obscureText;
  final VoidCallback? onSuffixTap;

  const CustomInputField({
    super.key,
    required this.controller,
    this.hintText,
    this.prefixIcon,
    this.suffixIcon,
    this.prefixText,
    this.keyboardType = TextInputType.text,
    this.readOnly = false,
    this.onTap,
    this.maxLength,
    this.obscureText = false,
    this.onSuffixTap,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return SizedBox(
      width: size.width,
      // height: size.height * 0.065,
      child: TextFormField(
        controller: controller,
        keyboardType: keyboardType,
        readOnly: readOnly,
        maxLength: maxLength,
        obscureText: obscureText,
        onTap: onTap,
        inputFormatters: keyboardType == TextInputType.phone
            ? [PhoneNumberFormatter()]
            : null,
        style: const TextStyle(
          fontFamily: AppFont.fontFamily,
          fontSize: 16,
          fontWeight: FontWeight.w400,
          color: AppColor.primaryColor,
        ),
        decoration: InputDecoration(
          counterText: "",
          hintText: hintText,
          hintStyle: const TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w400,
            fontSize: 16,
            color: AppColor.hinttextColor,
          ),
          filled: true,
          fillColor: const Color(0xFFF3F3F3),
          prefixIcon: prefixText != null
              ? Padding(
                  padding: const EdgeInsets.only(left: 16, right: 8),
                  child: Text(
                    prefixText!,
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: AppColor.primaryColor,
                    ),
                  ),
                )
              : prefixIcon,
          prefixIconConstraints: const BoxConstraints(
            minWidth: 0,
            minHeight: 0,
          ),
          suffixIcon: suffixIcon != null
              ? GestureDetector(
                  onTap: onSuffixTap,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: suffixIcon,
                  ),
                )
              : null,
          contentPadding: EdgeInsets.symmetric(
            vertical: size.height * 0.018,
             horizontal: size.height * 0.018,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(13),
            borderSide: BorderSide.none,
          ),
        ),
      ),
    );
  }
}

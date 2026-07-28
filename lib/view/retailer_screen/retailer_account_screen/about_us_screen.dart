import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/movigo_legal_content.dart';

class RAboutUsScreen extends StatefulWidget {
  const RAboutUsScreen({super.key});

  @override
  State<RAboutUsScreen> createState() => _RAboutUsScreenState();
}

class _RAboutUsScreenState extends State<RAboutUsScreen> {
  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColor.themeColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: const Text(
          'About Us',
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: const SingleChildScrollView(
        padding: EdgeInsets.all(16),
        child: Text(
          MovigoLegalContent.aboutUs,
          textAlign: TextAlign.justify,
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 14,
            height: 1.55,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }
}

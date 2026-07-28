import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'onboardingone_screen.dart';

class LanguageSelectionScreen extends StatefulWidget {
  const LanguageSelectionScreen({super.key});
  @override
  State<LanguageSelectionScreen> createState() => _LanguageSelectionScreenState();
}

class _LanguageSelectionScreenState extends State<LanguageSelectionScreen> {
  int _selected = 0;

  Future<void> _confirm() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_language', _selected);
    language = _selected;
    Get.offAll(() => OnboardingScreen());
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: size.width * 0.07),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: size.height * 0.08),
              Image.asset(AppImage.applogo, height: 80),
              SizedBox(height: size.height * 0.05),
              const Text('Choose Language / भाषा चुनें',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: AppFont.fontFamily, color: Color(0xff0A3D91)),
              ),
              SizedBox(height: size.height * 0.06),
              _tile('English', 'Continue in English', 0, '🇬🇧'),
              SizedBox(height: size.height * 0.02),
              _tile('हिंदी', 'हिंदी में जारी रखें', 1, '🇮🇳'),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xff0A3D91),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(_selected == 0 ? 'Continue' : 'जारी रखें',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: Colors.white)),
                ),
              ),
              SizedBox(height: size.height * 0.04),
            ],
          ),
        ),
      ),
    );
  }

  Widget _tile(String title, String subtitle, int value, String flag) {
    final bool sel = _selected == value;
    return GestureDetector(
      onTap: () => setState(() => _selected = value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
        decoration: BoxDecoration(
          color: sel ? const Color(0xff0A3D91).withOpacity(0.08) : Colors.white,
          border: Border.all(color: sel ? const Color(0xff0A3D91) : Colors.grey.shade300, width: sel ? 2 : 1),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(children: [
          Text(flag, style: const TextStyle(fontSize: 30)),
          const SizedBox(width: 16),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: sel ? const Color(0xff0A3D91) : Colors.black, fontFamily: AppFont.fontFamily)),
            Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.grey)),
          ])),
          Icon(sel ? Icons.radio_button_checked : Icons.radio_button_off, color: sel ? const Color(0xff0A3D91) : Colors.grey),
        ]),
      ),
    );
  }
}

import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:movigo/utilities/movigo_legal_content.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_header_content.dart';
import 'package:movigo/utilities/app_image.dart';

class Content extends StatelessWidget {
  static String routeName = './Content';
  const Content({super.key});

  @override
  Widget build(BuildContext context) {
    ContentClass? object;
    object = ModalRoute.of(context)!.settings.arguments as ContentClass;
    return Scaffold(
      body: ContentScreen(
        header: object.header,
        contenttype: object.contenttype,
      ),
    );
  }
}

class ContentScreen extends StatefulWidget {
  final String header;
  final String contenttype;

  const ContentScreen(
      {super.key, required this.header, required this.contenttype});

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen>
    with SingleTickerProviderStateMixin {
  String? get _localContent => MovigoLegalContent.byHeader(widget.header);

  bool isApiCalling = true;
  late final WebViewController _webViewController;
  late AnimationController _animationController;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    final localContent = _localContent;
    if (localContent != null) {
      isApiCalling = false;
    }
    _webViewController = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(AppColor.secondaryColor)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (_) {
            if (mounted) setState(() => isApiCalling = true);
          },
          onPageFinished: (_) {
            Future.delayed(
              const Duration(milliseconds: 600),
              () {
                if (mounted) setState(() => isApiCalling = false);
              },
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(localContent != null ? 'about:blank' : widget.contenttype));
    log("${widget.contenttype}");
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: AppColor.secondaryColor,
      body: SafeArea(
        child: Directionality(
          textDirection: language == 1 ? TextDirection.rtl : TextDirection.ltr,
          child: Container(
            height: screenHeight,
            width: screenWidth,
            color: AppColor.secondaryColor,
            child: Column(
              children: [
                // AppHeader(
                //   text: widget.header,
                //   onPress: () {
                //     Navigator.pop(context);
                //   },
                // ),
                SizedBox(
                  width: MediaQuery.of(context).size.width * 1 / 100,
                ),

                Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  children: [
                    GestureDetector(
                      onTap: () {
                        Navigator.pop(context);
                      },
                      child: Container(
                        height: MediaQuery.of(context).size.width * 13 / 100,
                        width: MediaQuery.of(context).size.width * 13 / 100,
                        color: AppColor.transparentColor,
                        padding: const EdgeInsets.only(left: 14),
                        alignment: Alignment.center,
                        child: Image.asset(
                          AppImage.backimage,
                          fit: BoxFit.cover,
                          height: MediaQuery.of(context).size.width * 8 / 100,
                          width: MediaQuery.of(context).size.width * 8 / 100,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: MediaQuery.of(context).size.width * 5 / 100,
                    ),
                    Text(
                      widget.header,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: AppColor.primaryColor,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        fontFamily: AppFont.fontFamily,
                      ),
                    ),
                  ],
                ),
                Expanded(
                  child: Container(
                    width: screenWidth * 0.95,
                    child: Stack(
                      children: [
                        if (_localContent != null)
                          SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              _localContent!,
                              textAlign: TextAlign.justify,
                              style: const TextStyle(
                                color: AppColor.blackColor,
                                fontSize: 14,
                                height: 1.55,
                                fontWeight: FontWeight.w400,
                                fontFamily: AppFont.fontFamily,
                              ),
                            ),
                          )
                        else
                          WebViewWidget(controller: _webViewController),
                        if (isApiCalling && _localContent == null)
                          Center(
                            child: RotationTransition(
                              turns: _animationController,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.5,
                                valueColor: AlwaysStoppedAnimation(
                                  AppColor.themeColor,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

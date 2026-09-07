import 'dart:developer';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:movigo/utilities/movigo_legal_content.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';

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

  /// Language-independent key ('terms_conditions' | 'privacy_policy' |
  /// 'about_us' | 'data_security_policy') identifying which built-in legal
  /// text to show. Pass this explicitly instead of relying on [header] —
  /// [header] is the localized display title (e.g. Hindi in Hindi mode) and
  /// can't reliably be matched against the English-only content lookup.
  final String? legalKey;

  const ContentScreen(
      {super.key, required this.header, required this.contenttype, this.legalKey});

  @override
  State<ContentScreen> createState() => _ContentScreenState();
}

class _ContentScreenState extends State<ContentScreen>
    with SingleTickerProviderStateMixin {
  // Prefer the explicit key; fall back to matching the header text (only
  // reliable in English) for any call site that hasn't been updated yet.
  String? get _localContent =>
      (widget.legalKey != null ? MovigoLegalContent.byType(widget.legalKey!) : null) ??
      MovigoLegalContent.byHeader(widget.header);

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
    log("${widget.contenttype}");
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
              () { if (mounted) setState(() => isApiCalling = false); },
            );
          },
        ),
      )
      ..loadRequest(Uri.parse(
          localContent != null || widget.contenttype.isEmpty
              ? 'about:blank'
              : widget.contenttype.startsWith('http')
                  ? widget.contenttype
                  : 'https://${widget.contenttype}',
        ));
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  IconData get _headerIcon {
    switch (widget.legalKey) {
      case 'privacy_policy':
        return Icons.shield_outlined;
      case 'about_us':
        return Icons.info_outline_rounded;
      case 'data_security_policy':
        return Icons.lock_outline_rounded;
      case 'terms_conditions':
      default:
        return Icons.gavel_rounded;
    }
  }

  // Pulled straight from the document text so it always matches whichever
  // policy is actually showing, instead of a single shared date.
  String? get _effectiveDateLine {
    final content = _localContent;
    if (content == null) return null;
    final match = RegExp(r'Effective Date:\s*(.+)').firstMatch(content);
    return match?.group(1)?.trim();
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        // Hindi (Devanagari) is written left-to-right, same as English —
        // this was previously forced to RTL for Hindi, which flipped every
        // `start`-aligned element (back button, headings, bullets) to the
        // right edge of the screen. Always LTR.
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Column(
            children: [
              // ── Header: icon-badged title + effective-date chip ──
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(12, 10, 20, 18),
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(bottom: Radius.circular(24)),
                  boxShadow: [
                    BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3)),
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        GestureDetector(
                          onTap: () => Navigator.pop(context),
                          child: Container(
                            padding: const EdgeInsets.all(8),
                            child: const Icon(Icons.arrow_back_rounded, color: AppColor.blackColor, size: 22),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: AppColor.themeColor.withOpacity(0.10),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(_headerIcon, color: AppColor.themeColor, size: 18),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            widget.header,
                            style: const TextStyle(
                              color: AppColor.primaryColor,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                              fontFamily: AppFont.fontFamily,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_effectiveDateLine != null) ...[
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.only(left: 52),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F4F9),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.event_available_rounded, size: 12, color: AppColor.hintTextColor),
                              const SizedBox(width: 5),
                              Text(
                                'Effective $_effectiveDateLine',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  fontFamily: AppFont.fontFamily,
                                  color: AppColor.hintTextColor,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              Expanded(
                child: Stack(
                  children: [
                    if (_localContent != null)
                      SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(color: const Color(0xFFEAEDF2)),
                          ),
                          child: _LegalContentBody(text: _localContent!),
                        ),
                      )
                    else
                      SizedBox(
                        width: screenWidth,
                        child: WebViewWidget(controller: _webViewController),
                      ),
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
            ],
          ),
        ),
      ),
    );
  }
}

/// Renders the plain-text legal copy with lightweight structure — section
/// headings ("1. Nature of Platform"), bullet lines, and the "━━━" divider
/// lines used throughout `movigo_legal_content.dart` — instead of one dense
/// unbroken paragraph.
class _LegalContentBody extends StatelessWidget {
  final String text;
  const _LegalContentBody({required this.text});

  bool _isDivider(String line) =>
      line.trim().isNotEmpty && line.trim().split('').every((c) => c == '━');

  bool _isHeading(String line) => RegExp(r'^\d{1,2}\.\s+\S').hasMatch(line.trim());

  bool _isBullet(String line) {
    final t = line.trim();
    return t.startsWith('•') || t.startsWith('✔') || t.startsWith('🔒');
  }

  @override
  Widget build(BuildContext context) {
    final lines = text.split('\n');
    final widgets = <Widget>[];
    bool firstLineConsumed = false;

    for (int i = 0; i < lines.length; i++) {
      final raw = lines[i];
      final line = raw.trimRight();

      if (!firstLineConsumed && line.trim().isNotEmpty) {
        // First non-empty line is the all-caps document title.
        widgets.add(Text(
          line.trim(),
          style: const TextStyle(
            fontSize: 18,
            fontWeight: FontWeight.w800,
            fontFamily: AppFont.fontFamily,
            color: AppColor.blackColor,
            height: 1.3,
          ),
        ));
        widgets.add(const SizedBox(height: 10));
        firstLineConsumed = true;
        continue;
      }

      if (line.trim().isEmpty) {
        widgets.add(const SizedBox(height: 10));
        continue;
      }

      if (_isDivider(line)) {
        widgets.add(const Padding(
          padding: EdgeInsets.symmetric(vertical: 6),
          child: Divider(height: 1, color: Color(0xFFE7EAF0)),
        ));
        continue;
      }

      if (_isHeading(line)) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(top: 4, bottom: 6),
          child: Text(
            line.trim(),
            style: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w700,
              fontFamily: AppFont.fontFamily,
              color: AppColor.themeColor,
            ),
          ),
        ));
        continue;
      }

      if (_isBullet(line)) {
        final bulletText = line.trim().substring(1).trim();
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 5),
                child: Icon(Icons.circle, size: 5, color: AppColor.themeColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  bulletText,
                  style: const TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.blackColor,
                  ),
                ),
              ),
            ],
          ),
        ));
        continue;
      }

      widgets.add(Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(
          line.trim(),
          textAlign: TextAlign.justify,
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.55,
            fontFamily: AppFont.fontFamily,
            color: AppColor.blackColor,
          ),
        ),
      ));
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: widgets);
  }
}

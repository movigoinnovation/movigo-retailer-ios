import 'package:flutter/material.dart';
import 'package:movigo/helper/contentScreen.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

/// Thin wrapper kept for existing call sites (signup flow) — delegates to the
/// shared, redesigned [ContentScreen] instead of maintaining a second, static
/// legal-text renderer that would drift out of sync with it.
class PolicyContentScreen extends StatelessWidget {
  final String policyType;
  final String title;

  const PolicyContentScreen({
    super.key,
    required this.policyType,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return ContentScreen(
      header: title,
      contenttype: '',
      legalKey: policyType,
    );
  }
}

// Policy Agreement Checkbox Widget
class PolicyAgreementWidget extends StatefulWidget {
  final bool isAgreed;
  final ValueChanged<bool?>? onChanged;

  const PolicyAgreementWidget({
    super.key,
    required this.isAgreed,
    required this.onChanged,
  });

  @override
  State<PolicyAgreementWidget> createState() => _PolicyAgreementWidgetState();
}

class _PolicyAgreementWidgetState extends State<PolicyAgreementWidget> {
  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Checkbox(
          value: widget.isAgreed,
          onChanged: widget.onChanged,
          activeColor: AppColor.themeColor,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 12),
            child: RichText(
              text: TextSpan(
                style: const TextStyle(
                  fontFamily: AppFont.fontFamily,
                  fontSize: 14,
                  color: Colors.black87,
                ),
                children: [
                  const TextSpan(text: 'I agree to the '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PolicyContentScreen(
                              policyType: 'terms_conditions',
                              title: 'Terms and Conditions',
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Terms and Conditions',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 14,
                          color: AppColor.themeColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                  const TextSpan(text: ' and '),
                  WidgetSpan(
                    child: GestureDetector(
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const PolicyContentScreen(
                              policyType: 'privacy_policy',
                              title: 'Privacy Policy',
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Privacy Policy',
                        style: TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 14,
                          color: AppColor.themeColor,
                          decoration: TextDecoration.underline,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

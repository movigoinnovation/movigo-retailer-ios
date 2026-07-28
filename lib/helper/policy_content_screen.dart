import 'package:flutter/material.dart';
import 'package:movigo/utilities/movigo_legal_content.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

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
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: AppColor.themeColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          title,
          style: const TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              _getPolicyContent(policyType),
              style: const TextStyle(
                fontFamily: AppFont.fontFamily,
                fontSize: 14,
                height: 1.5,
                color: Colors.black87,
              ),
            ),
            const SizedBox(height: 32),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColor.themeColor.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColor.themeColor.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Contact Information',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: AppColor.themeColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Movigo Innovations Pvt. Ltd.\nIndore, Madhya Pradesh, India\n\nEmail: Support.movigo@gmail.com\nSupport: Support.movigo@gmail.com',
                    style: const TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 14,
                      color: Colors.black87,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getPolicyContent(String type) {
    return MovigoLegalContent.byType(type) ?? 'Policy content not available.';
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

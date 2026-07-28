import 'package:dotted_border/dotted_border.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:get/get.dart';

import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_header.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/app_button.dart';
import 'package:movigo/utilities/common_text_field.dart';

class TermsAndConditionsScreen extends StatefulWidget {
  const TermsAndConditionsScreen({super.key});

  @override
  State<TermsAndConditionsScreen> createState() =>
      _TermsAndConditionsScreenState();
}

class _TermsAndConditionsScreenState extends State<TermsAndConditionsScreen> {
  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: Colors.white,
      // appBar: CommonAppBar(
      //   title: AppLanguage.termsConditionText[language],
      //   onBack: () => Get.back(),

      // ),
      // appBar: CommonAppBar(
      //   title: AppLanguage.termsConditionText[language],
      //   onBack: () => Navigator.of(context).maybePop(),
      // ),

      body: Column(
        children: [
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
            child: CommonAppBar(
              title: AppLanguage.termsConditionText[language],
              onBack: () => Navigator.of(context).maybePop(),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(height: size.height * 0.01),
                    Text(
                      "This Mobile Application End User Terms and conditions and Privacy Policy is a binding agreement between us. This Agreement governs your use of the APP on the MOBILE PLATFORMS and MOBILE DEVICES. The Application will be used by you. YOU ACKNOWLEDGE THAT YOU HAVE READ AND UNDERSTAND THIS Terms and conditions and Privacy Policy; You REPRESENT THAT YOU ARE OF LEGAL AGE TO ENTER INTO A BINDING AGREEMENT, AND ACCEPT THIS AGREEMENT AND AGREE THAT YOU ARE LEGALLY BOUND BY ITS TERMS AND CONDITIONS and PRIVACY POLICY. IF YOU DO NOT AGREE TO THESE TERMS AND CONDITION and PRIVACY POLICY, DO NOT DOWNLOAD/ INSTALL/USE THE APPLICATION AND DELETE IT FROM YOUR MOBILE DEVICE. License Grant. Subject to the terms of this Agreement, We grant you a limited, non-exclusive, and non-transferable license to download, install and use the Application for your personal, non-commercial use on a mobile device owned or otherwise controlled by you (Mobile Device) strictly in accordance with the Application's documentation access, stream, download and use on such Mobile Device the Content and Services made available in or otherwise accessible through the Application, strictly in accordance with this Agreement and the Terms of Use applicable to such Content and Services as set forth in. License Restrictions. Licensee shall not: copy the Application, except as expressly permitted by this license; modify, translate, adapt or otherwise create derivative works or improvements, whether or not patentable, of the Application; reverse engineer disassemble, decompile, decode or otherwise attempt to derive or gain access to the source code of the Application or any part thereof; remove, delete, alter or obscure any trademarks or any copyright, trademark, patent or other intellectual property or proprietary rights notices from the Application, including any copy thereof; rent, lease, lend, sell, sublicense, assign, distribute, publish, transfer or otherwise make available the Application or any features or functionality of the Application, to any third party for any reason, including by making the Application available on a network where it is capable of being accessed by more than one device at any time; remove, disable, circumvent or otherwise create or implement any workaround to any copy protection, rights management or security features in or protecting the Application; or  use the Application in, or in association with, the design, construction, maintenance or operation of any hazardous environments or systems, including any power generation systems; aircraft navigation or communication systems, air traffic control systems or any other transport management systems; safety-critical applications, including medical or life-support systems, vehicle operation applications or any police, fire or other safety response systems; and military or aerospace applications, weapons systems or environments. Reservation of Rights. You acknowledge and agree that the Application is provided under license, and will be used by you. You do not acquire any ownership interest in the Application under this Agreement, or any other rights thereto other than to use the Application in accordance with the license granted, and subject to all terms, conditions, and restrictions, under this Agreement. Company and its licensors and service providers reserve and shall retain their entire right, title, and interest in and to the Application, including all copyrights, trademarks, and other intellectual property rights therein or relating thereto, except as expressly granted to you in this Agreement. Collection and Use of Your Information. You acknowledge that when you download, install or use the Application, By downloading, installing, using, and providing information to or through this Application, you consent to all actions taken by us with respect to your information in compliance with the Privacy Policy. Content and Services. Your access to and use of such Content and Services may require you to acknowledge your acceptance of such Terms of Use and Privacy Policy and/or to register with the App and your failure to do so may restrict you from accessing or using certain of the Application's features and functionality. Any violation of such Terms of Use will also be deemed a violation of this Agreement. Geographic Restrictions. You acknowledge that you may not be able to access all or some of the Content and Services from certain countries and that access thereto may not be legal by certain persons or in certain countries. If you access the Content and Services, you are responsible for compliance with local laws. Updates. Company may from time to time in its sole discretion develop and provide Application updates, which may include upgrades, bug fixes, patches, and other error corrections and/or new features (collectively, including related documentation, Update). Updates may also modify or delete in their entirety certain features and functionality. You agree that the Company has no obligation to provide any Updates or to continue to provide or enable any particular features or functionality. Based on your Mobile Device settings, when your Mobile Device is connected to the internet either: the application will automatically download and install all available Updates, or you may receive notice of or be prompted to download and install available Updates. You shall promptly download and install all Updates and acknowledge and agree that the Application or portions thereof may not properly operate should you fail to do so. You further agree that all Updates will be deemed part of the Application and be subject to all terms and conditions of this Agreement.Term and Termination. You may terminate this Agreement by deleting the Application and all copies thereof from your Mobile Device. Company may terminate this Agreement at any time without notice if it ceases to support the Application, which Company may do in its sole discretion or in the for OTHER TERMINATION EVENTS. In addition, this Agreement will terminate immediately and automatically without any notice if you violate any of the terms and conditions of this Agreement. Upon termination: all rights granted to you under this Agreement will also terminate, and you must cease all use of the Application and delete all copies of the Application from your Mobile Device and account. Termination will not limit any of the Company's rights or remedies at law or in equity. Disclaimer of Warranties. THE APPLICATION IS PROVIDED TO THE LICENSEE  AND WITH ALL FAULTS AND DEFECTS WITHOUT WARRANTY OF ANY KIND. TO THE MAXIMUM EXTENT PERMITTED UNDER APPLICABLE LAW, THE COMPANY, ON ITS OWN BEHALF AND ON BEHALF OF ITS AFFILIATES AND ITS AND THEIR RESPECTIVE LICENSORS AND SERVICE PROVIDERS, EXPRESSLY DISCLAIMS ALL WARRANTIES, WHETHER EXPRESS, IMPLIED, STATUTORY, OR OTHERWISE, WITH RESPECT TO THE APPLICATION, INCLUDING ALL IMPLIED WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, TITLE AND NON-INFRINGEMENT, AND WARRANTIES THAT MAY ARISE OUT OF COURSE OF DEALING, COURSE OF PERFORMANCE, USAGE OR TRADE PRACTICE. WITHOUT LIMITATION TO THE FOREGOING, COMPANY PROVIDES NO WARRANTY OR UNDERTAKING AND MAKES NO REPRESENTATION OF ANY KIND THAT THE APPLICATION WILL MEET YOUR REQUIREMENTS, ACHIEVE ANY INTENDED RESULTS, BE COMPATIBLE OR WORK WITH ANY OTHER SOFTWARE, APPLICATIONS, SYSTEMS, OR SERVICES, OPERATE WITHOUT INTERRUPTION, MEET ANY PERFORMANCE OR RELIABILITY STANDARDS OR BE ERROR FREE OR THAT ANY ERRORS OR DEFECTS CAN OR WILL BE CORRECTED. SOME JURISDICTIONS DO NOT ALLOW THE EXCLUSION OF OR LIMITATIONS ON IMPLIED WARRANTIES OR THE LIMITATIONS ON THE APPLICABLE STATUTORY RIGHTS OF A CONSUMER, SO SOME OR ALL OF THE ABOVE EXCLUSIONS AND LIMITATIONS MAY NOT APPLY TO YOU.Limitation of Liability. TO THE FULLEST EXTENT PERMITTED BY APPLICABLE LAW, IN NO EVENT WILL COMPANY OR ITS AFFILIATES, OR ANY OF ITS OR THEIR RESPECTIVE LICENSORS OR SERVICE PROVIDERS, HAVE ANY LIABILITY ARISING FROM OR RELATED TO YOUR USE OF OR INABILITY TO USE THE APPLICATION OR THE CONTENT AND SERVICES FOR: (a) PERSONAL INJURY, PROPERTY DAMAGE, LOST PROFITS, COST OF SUBSTITUTE GOODS OR SERVICES, LOSS OF DATA, LOSS OF GOODWILL, BUSINESS INTERRUPTION, COMPUTER FAILURE OR MALFUNCTION OR ANY OTHER CONSEQUENTIAL, INCIDENTAL, INDIRECT, EXEMPLARY, SPECIAL OR PUNITIVE DAMAGES  (b) DIRECT DAMAGES IN AMOUNTS THAT IN THE AGGREGATE EXCEED THE AMOUNT ACTUALLY PAID BY YOU FOR THE APPLICATION.  THE FOREGOING LIMITATIONS WILL APPLY WHETHER SUCH DAMAGES ARISE OUT OF BREACH OF CONTRACT, TORT (INCLUDING NEGLIGENCE), OR OTHERWISE AND REGARDLESS OF WHETHER SUCH DAMAGES WERE FORESEEABLE OR THE COMPANY WAS ADVISED OF THE POSSIBILITY OF SUCH DAMAGES. SOME JURISDICTIONS DO NOT ALLOW CERTAIN LIMITATIONS OF LIABILITY SO SOME OR ALL OF THE ABOVE LIMITATIONS OF LIABILITY MAY NOT APPLY TO YOU. Indemnification. You agree to indemnify, defend and hold harmless the Company and its officers, directors, employees, agents, affiliates, successors, and assigns from and against any and all losses, damages, liabilities, deficiencies, claims, actions, judgments, settlements, interest, awards, penalties, fines, costs, or expenses of whatever kind, including reasonable attorneys' fees, arising from or relating to your use or misuse of the Application or your breach of this Agreement. Furthermore, you agree that the Company assumes no responsibility for the content you submit or make available through this Application. Export Regulation. The Application may be subject to export control laws. You shall not, directly or indirectly, export, re-export, or release the Application to, or make the Application accessible from, any jurisdiction or country to which export, re-export, or release is prohibited by law, rule, or regulation. Severability. If any provision of this Agreement is illegal or unenforceable under applicable law, the remainder of the provision will be amended to achieve as closely as possible the effect of the original term, and all other provisions of this Agreement will continue in full force and effect. Governing Law. This Agreement is governed by and construed in accordance with the internal laws without giving effect to any choice or conflict of law provision or rule. Any legal suit, action, or proceeding arising out of or related to this Agreement or the Application shall be instituted exclusively in the courts of England. You waive any and all objections to the exercise of jurisdiction over you by such courts and to the venue in such courts.  Limitation of Time to File Claims. ANY CAUSE OF ACTION OR CLAIM YOU MAY HAVE ARISING OUT OF OR RELATING TO THIS AGREEMENT OR THE APPLICATION MUST BE COMMENCED WITHIN ONE (1) YEAR AFTER THE CAUSE OF ACTION ACCRUES, OTHERWISE, SUCH CAUSE OF ACTION OR CLAIM IS PERMANENTLY BARRED. Entire Agreement. This Terms and Conditions and  Privacy Policy constitute the entire agreement between you and Company with respect to the Application and supersede all prior or contemporaneous understandings and agreements, whether written or oral, with respect to the Application. Waiver. No failure to exercise and no delay in exercising, on the part of either party, any right or any power hereunder shall operate as a waiver thereof, nor shall any single or partial exercise of any right or power hereunder preclude further exercise of that or any other right hereunder. In the event of a conflict between this terms and conditions and the Privacy Policy and any applicable purchase or other terms, the terms of this Agreement and Privacy Policy shall govern.  Contact Information. If You have any questions regarding this terms and conditions and Privacy Policy, please contact us.", // "Terms & Conditions"
                      textAlign: TextAlign.justify,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        fontWeight: FontWeight.w400,
                        fontFamily: AppFont.fontFamily,
                        color: AppColor.blackColor,
                      ),
                    ),
                    SizedBox(height: size.height * 0.06),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

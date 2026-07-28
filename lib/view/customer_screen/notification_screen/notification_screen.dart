import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Controller/Notification/notification_provider.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/helper/shimmer/notification_shimmer.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'package:movigo/utilities/notification_redirect_helper.dart';

class NotificationScreen extends StatefulWidget {
  static String routeName = './NotificationScreen';
  const NotificationScreen({super.key});

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      context
          .read<NotificationController>()
          .getAllNotifications(context, isRefresh: true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: AppColor.transparentColor,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    return Scaffold(
      backgroundColor: AppColor.secondaryColor,
      body: SafeArea(
        child: Consumer<NotificationController>(
          builder: (context, controller, _) {
            return Column(
              children: [
                SizedBox(height: size.height * 0.02),

                /// ================= HEADER =================
                _header(size, controller),

                SizedBox(height: size.height * 0.02),

                /// ================= LIST =================
                Expanded(
                  child: controller.isLoading
                      ? NotificationShimmerScreen()
                      : controller.notifications.isEmpty
                          ? _emptyView()
                          : RefreshIndicator(
                              onRefresh: () => controller.getAllNotifications(
                                context,
                                isRefresh: true,
                              ),
                              child: ListView.builder(
                                padding: EdgeInsets.symmetric(
                                    horizontal: size.width * 0.03),
                                itemCount: controller.notifications.length,
                                itemBuilder: (context, index) {
                                  final item = controller.notifications[index];

                                  return Dismissible(
                                    key: ValueKey(item.notificationId),
                                    direction: DismissDirection.endToStart,
                                    background: _swipeDeleteBg(size),
                                    onDismissed: (_) {
                                      controller.deleteSingleNotification(
                                        context,
                                        item.notificationId,
                                      );
                                    },
                                    child: _notificationCard(size, item),
                                  );
                                },
                              ),
                            ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  void _onNotificationTap(NotificationItem item) {
    final Map<String, dynamic> payload =
        NotificationRedirectHelper.payloadFromNotificationItem(
      action: item.action,
      bookingId: item.bookingId,
      actionJson: item.actionJson,
    );

    NotificationRedirectHelper.routeFromNotificationData(
      context: context,
      navigator: Navigator.of(context),
      data: payload,
    );
  }

  /// ================= HEADER =================
  Widget _header(Size size, NotificationController controller) {
    return SizedBox(
      width: size.width * 0.9,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Image.asset(
                  AppImage.backimage,
                  height: size.width * 0.08,
                ),
              ),
              SizedBox(width: size.width * 0.03),
              Text(
                AppLanguage.notificationText[language],
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  fontFamily: AppFont.fontFamily,
                ),
              ),
            ],
          ),
          GestureDetector(
            onTap: () async {
              await controller.clearAllNotifications(context);
            },
            child: Text(
              AppLanguage.clearText[language],
              style: const TextStyle(
                fontSize: 14,
                decoration: TextDecoration.underline,
                color: AppColor.grey6EColor,
                fontFamily: AppFont.fontFamily,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// ================= CARD =================
  Widget _notificationCard(Size size, item) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => _onNotificationTap(item),
      child: Container(
        margin: EdgeInsets.only(bottom: size.height * 0.02),
        padding: EdgeInsets.all(size.width * 0.04),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Image.asset(
              AppImage.notigreen,
              height: size.width * 0.06,
            ),
            SizedBox(width: size.width * 0.03),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.message,
                    style: const TextStyle(
                      fontSize: 13.6,
                      fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily,
                    ),
                  ),
                  SizedBox(height: size.height * 0.004),
                  Text(
                    NotificationTimeHelper.format(item.createTime),
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xffAAA7A7),
                      fontFamily: AppFont.fontFamily,
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

  /// ================= DELETE BG =================
  Widget _swipeDeleteBg(Size size) {
    return Container(
      alignment: Alignment.centerRight,
      padding: EdgeInsets.only(right: size.width * 0.04),
      child: Image.asset(
        AppImage.deletered,
        height: size.width * 0.09,
      ),
    );
  }

  /// ================= EMPTY =================
  Widget _emptyView() {
    return const Center(
      child: Text(
        "No notifications found",
        style: TextStyle(fontSize: 14),
      ),
    );
  }
}

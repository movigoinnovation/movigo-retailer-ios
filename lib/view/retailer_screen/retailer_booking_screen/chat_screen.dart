// chat_screen.dart — Feature 16: Live Chat During Booking
// Retailer / Individual app version.
// Mirrors the driver's ChatScreen — uses SocketProvider.joinChat / sendMessage
// which now route through HTTP + Pusher (not broken socket.io).
//
// Callers must pass bookingId, userId, otherUserId.
// If the caller previously used RChatScreen() with no params, update the
// Get.to call to: Get.to(() => RChatScreen(bookingId: ..., userId: ..., otherUserId: ...))

import 'dart:developer';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get_core/src/get_main.dart';
import 'package:get/get_navigation/get_navigation.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';

class RChatScreen extends StatefulWidget {
  final String bookingId;
  final String userId;
  final String otherUserId;
  final String? bookingCode;
  final String? userName;

  const RChatScreen({
    super.key,
    required this.bookingId,
    required this.userId,
    required this.otherUserId,
    this.bookingCode,
    this.userName,
  });

  @override
  State<RChatScreen> createState() => _RChatScreenState();
}

class _RChatScreenState extends State<RChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _messageController = TextEditingController();
  late SocketProvider _socketProvider;
  int _lastMessageCount = 0;
  String _myUserId = '';

  int get language => AppLanguage.language;

  @override
  void initState() {
    super.initState();

    final uc = Provider.of<UserController>(context, listen: false);
    _myUserId = uc.getUserId.isNotEmpty ? uc.getUserId : widget.userId;

    log('🟢 RChatScreen opened | bookingId=${widget.bookingId} userId=$_myUserId otherUserId=${widget.otherUserId}');

    _socketProvider = context.read<SocketProvider>();
    _socketProvider.joinChat(
      userId: _myUserId,
      bookingId: widget.bookingId,
      otherUserId: widget.otherUserId,
    );

    _scrollController.addListener(() {
      if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 50) {
        _socketProvider.loadMoreMessages(
          userId: _myUserId,
          bookingId: widget.bookingId,
        );
      }
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) _scrollController.jumpTo(0);
    });
  }

  @override
  void dispose() {
    log('🔴 RChatScreen disposed');
    _socketProvider.leaveChat(userId: _myUserId, bookingId: widget.bookingId);
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  String _msgTime(Map<String, dynamic> msg) {
    if (msg['time'] != null && msg['time'].toString().isNotEmpty) return msg['time'].toString();
    if (msg['createdAt'] != null) {
      final dt = DateTime.tryParse(msg['createdAt'].toString());
      if (dt != null) return "${dt.hour.toString().padLeft(2,'0')}:${dt.minute.toString().padLeft(2,'0')}";
    }
    return '';
  }

  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    _socketProvider.sendMessage(
      senderId: _myUserId,
      receiverId: widget.otherUserId,
      bookingId: widget.bookingId,
      message: text,
    );
    _messageController.clear();
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.dark,
    ));

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.white,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        titleSpacing: 0,
        toolbarHeight: 90,
        title: Padding(
          padding: EdgeInsets.only(top: size.height * 0.015, left: size.width * 0.035),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: () => Get.back(),
                child: Image.asset(AppImage.backimage, height: 40, width: 40),
              ),
              Column(
                children: [
                  Text(
                    widget.userName ?? 'Driver',
                    style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.w600,
                      fontFamily: AppFont.fontFamily, color: AppColor.blackColor,
                    ),
                  ),
                  Text(
                    widget.bookingCode != null ? '#${widget.bookingCode}' : '',
                    style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500,
                      fontFamily: AppFont.fontFamily, color: AppColor.fourTextColor,
                    ),
                  ),
                ],
              ),
              Image.asset(AppImage.backimage, height: 40, width: 40, color: AppColor.transparentColor),
            ],
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Consumer<SocketProvider>(
              builder: (ctx, sp, _) {
                final messages = sp.messages;
                if (messages.length != _lastMessageCount) {
                  _lastMessageCount = messages.length;
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (_scrollController.hasClients) _scrollController.jumpTo(0);
                  });
                }
                if (messages.isEmpty) {
                  return const Center(
                    child: Text('No messages yet', style: TextStyle(color: Colors.grey)),
                  );
                }
                return ListView.builder(
                  controller: _scrollController,
                  reverse: true,
                  padding: EdgeInsets.symmetric(
                      horizontal: size.width * 0.05, vertical: size.height * 0.015),
                  itemCount: messages.length,
                  itemBuilder: (_, i) {
                    final msg = messages[i];
                    final isMe = msg['sender_id'] == _myUserId;
                    final text = msg['message']?.toString() ?? '';
                    final time = _msgTime(msg);
                    final isSeen = msg['is_seen'] ?? msg['is_read'] ?? false;
                    return isMe
                        ? _sentBubble(context, text: text, time: time, isSeen: isSeen)
                        : _receivedBubble(context, text: text, time: time);
                  },
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(
              left: size.width * 0.04,
              right: size.width * 0.04,
              bottom: size.height * 0.02,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    height: 52,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(30),
                      boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: TextField(
                      controller: _messageController,
                      onSubmitted: (_) => _sendMessage(),
                      decoration: InputDecoration(
                        hintText: AppLanguage.typeHereText[language],
                        hintStyle: const TextStyle(fontSize: 14, fontFamily: AppFont.fontFamily, color: AppColor.selectTpeColor),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: size.width * 0.03),
                InkWell(
                  onTap: _sendMessage,
                  child: Image.asset(AppImage.share, height: 64, width: 60),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _sentBubble(BuildContext context, {required String text, required String time, required bool isSeen}) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.centerRight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: size.width * 0.7),
            padding: const EdgeInsets.fromLTRB(14, 10, 32, 22),
            decoration: const BoxDecoration(
              color: AppColor.primaryColor,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomLeft: Radius.circular(14), bottomRight: Radius.circular(4),
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Padding(padding: const EdgeInsets.only(right: 10),
                    child: Text(text, style: const TextStyle(fontSize: 13, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, color: Colors.white))),
                Positioned(bottom: -15, right: -20,
                    child: Icon(isSeen ? Icons.done_all : Icons.done, size: 20, color: Colors.white)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Text(time, style: const TextStyle(fontSize: 10, fontFamily: AppFont.fontFamily, color: AppColor.selectTpeColor)),
          const SizedBox(height: 14),
        ],
      ),
    );
  }

  Widget _receivedBubble(BuildContext context, {required String text, required String time}) {
    final size = MediaQuery.of(context).size;
    return Align(
      alignment: Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            constraints: BoxConstraints(maxWidth: size.width * 0.7),
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 14),
            decoration: const BoxDecoration(
              color: Color(0xffF2F2F2),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(14), topRight: Radius.circular(14),
                bottomRight: Radius.circular(14), bottomLeft: Radius.circular(4),
              ),
            ),
            child: Text(text, style: const TextStyle(fontSize: 13, fontFamily: AppFont.fontFamily, fontWeight: FontWeight.w500, color: AppColor.blackColor)),
          ),
          const SizedBox(height: 4),
          Text(time, style: const TextStyle(fontSize: 10, fontFamily: AppFont.fontFamily, color: AppColor.selectTpeColor)),
          const SizedBox(height: 14),
        ],
      ),
    );
  }
}

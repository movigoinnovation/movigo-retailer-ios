import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:movigo/Model/notice_model.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_font.dart';

class NoticeboardScreen extends StatefulWidget {
  const NoticeboardScreen({super.key});

  @override
  State<NoticeboardScreen> createState() => _NoticeboardScreenState();
}

class _NoticeboardScreenState extends State<NoticeboardScreen> {
  bool _loading = true;
  List<NoticeModel> _notices = [];

  @override
  void initState() {
    super.initState();
    _loadNotices();
  }

  Future<void> _loadNotices() async {
    final provider = Provider.of<PostApiProvider>(context, listen: false);
    final res = await provider.getNoticesApi(context);
    final list = (res?['data'] as List?) ?? [];
    if (mounted) {
      setState(() {
        _notices = list
            .whereType<Map>()
            .map((e) => NoticeModel.fromJson(Map<String, dynamic>.from(e)))
            .toList();
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    await _loadNotices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        backgroundColor: AppColor.themeColor,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Noticeboard',
          style: TextStyle(
            color: Colors.white,
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 18,
          ),
        ),
        actions: const [
          _SocialIconButton(
            icon: FontAwesomeIcons.instagram,
            url: 'https://www.instagram.com/movigo_innovations/',
          ),
          _SocialIconButton(
            icon: FontAwesomeIcons.linkedinIn,
            url: 'https://www.linkedin.com/company/movigo-innovation-private-limited/?viewAsMember=true',
          ),
          _SocialIconButton(
            icon: FontAwesomeIcons.facebookF,
            url: 'https://facebook.com/',
          ),
          SizedBox(width: 6),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: AppColor.themeColor))
          : _notices.isEmpty
              ? RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColor.themeColor,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      _EmptyNoticeboard(),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _refresh,
                  color: AppColor.themeColor,
                  child: ListView.builder(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    itemCount: _notices.length,
                    itemBuilder: (context, index) {
                      return _NoticeCard(notice: _notices[index]);
                    },
                  ),
                ),
    );
  }
}

class _SocialIconButton extends StatelessWidget {
  final FaIconData icon;
  final String url;

  const _SocialIconButton({required this.icon, required this.url});

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: _open,
      icon: FaIcon(icon, color: Colors.white, size: 20),
      splashRadius: 20,
      padding: const EdgeInsets.symmetric(horizontal: 2),
      constraints: const BoxConstraints(),
    );
  }
}

class _EmptyNoticeboard extends StatelessWidget {
  const _EmptyNoticeboard();

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(Icons.campaign_outlined, size: 56, color: AppColor.greyColor),
        const SizedBox(height: 12),
        const Text(
          'No notices right now',
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontWeight: FontWeight.w600,
            fontSize: 15,
            color: AppColor.greyestherColor,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'Check back later for announcements and updates',
          style: TextStyle(
            fontFamily: AppFont.fontFamily,
            fontSize: 12.5,
            color: AppColor.hinttextColor,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _NoticeCard extends StatelessWidget {
  final NoticeModel notice;
  const _NoticeCard({required this.notice});

  Color get _accentColor {
    if (notice.themeColor.isNotEmpty) {
      try {
        final hex = notice.themeColor.replaceAll('#', '');
        final value = int.parse(
            hex.length == 6 ? 'FF$hex' : hex, radix: 16);
        return Color(value);
      } catch (_) {}
    }
    return AppColor.themeColor;
  }

  String get _defaultEmoji {
    switch (notice.noticeType) {
      case 'update':
        return '🆕';
      case 'festival':
        return '🎉';
      case 'maintenance':
        return '🛠️';
      case 'social':
        return '📣';
      default:
        return '📣';
    }
  }

  Widget _buildLeadingIcon() {
    if (notice.noticeType == 'social') {
      return CircleAvatar(
        radius: 20,
        backgroundColor: _accentColor.withOpacity(0.12),
        child: _socialIcon(notice.socialIcon, _accentColor, 20),
      );
    }
    final emoji = notice.icon.isNotEmpty ? notice.icon : _defaultEmoji;
    return CircleAvatar(
      radius: 20,
      backgroundColor: _accentColor.withOpacity(0.12),
      child: Text(emoji, style: const TextStyle(fontSize: 18)),
    );
  }

  // font_awesome_flutter 11 made FaIconData a separate type from IconData, so
  // brand glyphs must go through FaIcon and the Material fallbacks through Icon.
  Widget _socialIcon(String key, Color color, double size) {
    switch (key.toLowerCase()) {
      case 'instagram':
        return FaIcon(FontAwesomeIcons.instagram, color: color, size: size);
      case 'facebook':
        return FaIcon(FontAwesomeIcons.facebookF, color: color, size: size);
      case 'whatsapp':
        return FaIcon(FontAwesomeIcons.whatsapp, color: color, size: size);
      case 'youtube':
        return FaIcon(FontAwesomeIcons.youtube, color: color, size: size);
      case 'twitter':
        return FaIcon(FontAwesomeIcons.xTwitter, color: color, size: size);
      case 'linkedin':
        return FaIcon(FontAwesomeIcons.linkedinIn, color: color, size: size);
      case 'telegram':
        return FaIcon(FontAwesomeIcons.telegram, color: color, size: size);
      case 'website':
        return Icon(Icons.language, color: color, size: size);
      default:
        return Icon(Icons.share_outlined, color: color, size: size);
    }
  }

  Future<void> _openLink() async {
    if (notice.linkUrl.isEmpty) return;
    final uri = Uri.tryParse(notice.linkUrl);
    if (uri == null) return;
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: notice.isPinned
            ? Border.all(color: _accentColor.withOpacity(0.5), width: 1.3)
            : Border.all(color: Colors.transparent),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (notice.isPinned)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(Icons.push_pin_rounded, size: 13, color: _accentColor),
                  const SizedBox(width: 4),
                  Text(
                    'PINNED',
                    style: TextStyle(
                      fontFamily: AppFont.fontFamily,
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      color: _accentColor,
                      letterSpacing: 0.4,
                    ),
                  ),
                ],
              ),
            ),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildLeadingIcon(),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      notice.title,
                      style: const TextStyle(
                        fontFamily: AppFont.fontFamily,
                        fontWeight: FontWeight.w700,
                        fontSize: 14.5,
                        color: AppColor.fontColor,
                      ),
                    ),
                    if (notice.body.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        notice.body,
                        style: const TextStyle(
                          fontFamily: AppFont.fontFamily,
                          fontSize: 13,
                          color: AppColor.greyestherColor,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (notice.linkUrl.isNotEmpty) ...[
                      const SizedBox(height: 10),
                      GestureDetector(
                        onTap: _openLink,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 7),
                          decoration: BoxDecoration(
                            color: _accentColor,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                notice.linkLabel.isNotEmpty
                                    ? notice.linkLabel
                                    : 'Open',
                                style: const TextStyle(
                                  fontFamily: AppFont.fontFamily,
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.arrow_outward_rounded,
                                  size: 14, color: Colors.white),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

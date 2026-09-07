class NoticeModel {
  final String id;
  final String title;
  final String body;
  final String noticeType; // announcement | update | festival | social | maintenance
  final String icon;
  final String socialIcon;
  final String linkUrl;
  final String linkLabel;
  final String imageUrl;
  final String audience;
  final String themeColor;
  final bool isPinned;
  final bool isActive;
  final String? startsAt;
  final String? endsAt;
  final String createdAt;

  NoticeModel({
    required this.id,
    required this.title,
    required this.body,
    required this.noticeType,
    required this.icon,
    required this.socialIcon,
    required this.linkUrl,
    required this.linkLabel,
    required this.imageUrl,
    required this.audience,
    required this.themeColor,
    required this.isPinned,
    required this.isActive,
    this.startsAt,
    this.endsAt,
    required this.createdAt,
  });

  factory NoticeModel.fromJson(Map<String, dynamic> json) {
    return NoticeModel(
      id: json['_id']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
      noticeType: json['notice_type']?.toString() ?? 'announcement',
      icon: json['icon']?.toString() ?? '',
      socialIcon: json['social_icon']?.toString() ?? '',
      linkUrl: json['link_url']?.toString() ?? '',
      linkLabel: json['link_label']?.toString() ?? '',
      imageUrl: json['image_url']?.toString() ?? '',
      audience: json['audience']?.toString() ?? '',
      themeColor: json['theme_color']?.toString() ?? '',
      isPinned: json['is_pinned'] == true,
      isActive: json['is_active'] == true,
      startsAt: json['starts_at']?.toString(),
      endsAt: json['ends_at']?.toString(),
      createdAt: json['createdAt']?.toString() ?? '',
    );
  }
}

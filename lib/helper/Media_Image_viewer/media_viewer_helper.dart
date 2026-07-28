import 'dart:io';
import 'package:flutter/material.dart';
import 'package:movigo/utilities/app_config_provider.dart';

/// =======================
/// MEDIA VIEWER HELPER
/// =======================
class MediaViewerHelper {
  static void openImage({
    required BuildContext context,
    required String imageName,
  }) {
    if (imageName.isEmpty) return;

    final mediaList = [
      {
        "type": 1, // network
        "media": imageName,
      }
    ];

    _openViewer(context, mediaList, 0);
  }

  static void openLocalImages({
    required BuildContext context,
    required List<File> images,
    int startIndex = 0,
  }) {
    if (images.isEmpty) return;

    final mediaList = images
        .map((file) => {
              "type": 2, // local file
              "media": file,
            })
        .toList();

    _openViewer(context, mediaList, startIndex);
  }

  static void _openViewer(
    BuildContext context,
    List<dynamic> mediaList,
    int index,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _MediaViewerScreen(
          mediaList: mediaList,
          initialIndex: index,
        ),
      ),
    );
  }
}

/// =======================
/// MEDIA VIEWER SCREEN
/// =======================
class _MediaViewerScreen extends StatefulWidget {
  final List<dynamic> mediaList;
  final int initialIndex;

  const _MediaViewerScreen({
    required this.mediaList,
    required this.initialIndex,
  });

  @override
  State<_MediaViewerScreen> createState() => _MediaViewerScreenState();
}

class _MediaViewerScreenState extends State<_MediaViewerScreen> {
  late PageController _controller;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _controller = PageController(initialPage: _currentIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: PageView.builder(
        controller: _controller,
        itemCount: widget.mediaList.length,
        onPageChanged: (index) {
          setState(() => _currentIndex = index);
        },
        itemBuilder: (context, index) {
          final item = widget.mediaList[index];
          final type = item['type'];

          return InteractiveViewer(
            minScale: 1,
            maxScale: 4,
            child: Center(
              child: type == 2
                  ? Image.file(
                      item['media'],
                      fit: BoxFit.contain,
                    )
                  : Image.network(
                      "${AppConfigProvider.imgUrl}${item['media']}",
                      fit: BoxFit.contain,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const CircularProgressIndicator(
                          color: Colors.white,
                        );
                      },
                      errorBuilder: (_, __, ___) => const Icon(
                        Icons.broken_image,
                        color: Colors.white,
                        size: 80,
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

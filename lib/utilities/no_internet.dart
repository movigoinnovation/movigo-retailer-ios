import 'dart:async';
import 'package:flutter/material.dart';
import 'app_font.dart';

class NoInternetBanner extends StatefulWidget {
  final ConnectionStatus status;
  final VoidCallback? onRetry;
  final Duration animationDuration;
  final bool showRetryButton;
  final String? customMessage;
  final Duration? retryTimeout;

  const NoInternetBanner({
    super.key,
    required this.status,
    this.onRetry,
    this.animationDuration = const Duration(seconds: 1),
    this.showRetryButton = true,
    this.customMessage,
    this.retryTimeout = const Duration(seconds: 10),
  });

  @override
  State<NoInternetBanner> createState() => _NoInternetBannerState();
}

class _NoInternetBannerState extends State<NoInternetBanner>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isRetrying = false;
  Timer? _retryTimeoutTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: widget.animationDuration,
      vsync: this,
    );

    // FIXED: Changed animation values for top position
    _slideAnimation = Tween<double>(
      begin: -1.0, // Start above the screen
      end: 0.0, // End at top position
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeInOut,
    ));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeIn,
    ));

    // Start animation if needed
    if (_shouldShowBanner()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _controller.forward();
      });
    }
  }

  @override
  void didUpdateWidget(NoInternetBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.status != widget.status) {
      if (_shouldShowBanner()) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  Color _getStatusColor() {
    switch (widget.status) {
      case ConnectionStatus.None:
        return const Color(0xFFEF5350); // Red for no connection
      case ConnectionStatus.Poor:
        return const Color(0xFFFF9800); // Orange for poor connection
      default:
        return const Color(0xFF4CAF50);
    }
  }

  String _getStatusMessage() {
    if (widget.customMessage != null) {
      return widget.customMessage!;
    }

    switch (widget.status) {
      case ConnectionStatus.None:
        return "You're Offline";
      case ConnectionStatus.Poor:
        return 'Poor connection quality';
      default:
        return 'You\'re back';
    }
  }

  IconData _getStatusIcon() {
    switch (widget.status) {
      case ConnectionStatus.None:
        return Icons.wifi_off;
      case ConnectionStatus.Poor:
        return Icons.signal_wifi_bad;
      default:
        return Icons.wifi_off;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _retryTimeoutTimer?.cancel();
    super.dispose();
  }

  bool _shouldShowBanner() {
    return widget.status != ConnectionStatus.WiFi &&
        widget.status != ConnectionStatus.Mobile;
  }

  Future<void> _handleRetry() async {
    if (widget.onRetry == null || _isRetrying) return;

    setState(() {
      _isRetrying = true;
    });

    _retryTimeoutTimer = Timer(widget.retryTimeout!, () {
      if (mounted && _isRetrying) {
        setState(() {
          _isRetrying = false;
        });
      }
    });

    try {
      widget.onRetry!();
    } catch (e) {
      print('Retry failed: $e');
    } finally {
      _retryTimeoutTimer?.cancel();
      if (mounted) {
        setState(() {
          _isRetrying = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_shouldShowBanner()) {
      if (_controller.status == AnimationStatus.dismissed) {
        _controller.forward();
      }
    } else {
      if (_controller.status == AnimationStatus.completed) {
        _controller.reverse();
      }
    }

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        if (_controller.value == 0.0 && !_shouldShowBanner()) {
          return const SizedBox.shrink();
        }

        return Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Transform.translate(
            offset: Offset(
              0,
              _slideAnimation.value * 60,
            ),
            child: Opacity(
              opacity: _fadeAnimation.value,
              child: SafeArea(
                bottom: false,
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Material(
                    elevation: 6,
                    borderRadius: BorderRadius.circular(14),
                    shadowColor: Colors.black26,
                    child: Container(
                      height: 64,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: LinearGradient(
                          colors: [
                            _getStatusColor(),
                            _getStatusColor().withOpacity(0.85),
                          ],
                        ),
                      ),
                      child: Row(
                        children: [
                          /// 🔴 LEFT ACCENT BAR
                          Container(
                            width: 4,
                            height: double.infinity,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.9),
                              borderRadius: const BorderRadius.only(
                                topLeft: Radius.circular(14),
                                bottomLeft: Radius.circular(14),
                              ),
                            ),
                          ),

                          const SizedBox(width: 12),

                          /// 🔵 ICON
                          Container(
                            width: 36,
                            height: 36,
                            decoration: BoxDecoration(
                              color: Colors.white.withOpacity(0.2),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              _getStatusIcon(),
                              color: Colors.white,
                              size: 18,
                            ),
                          ),

                          const SizedBox(width: 12),

                          /// 📝 TEXT
                          Expanded(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  _getStatusMessage(),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                    fontFamily: AppFont.fontFamily,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                if (widget.status == ConnectionStatus.Poor)
                                  Text(
                                    'Some features may not work',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.white.withOpacity(0.85),
                                      fontFamily: AppFont.fontFamily,
                                    ),
                                  ),
                              ],
                            ),
                          ),

                          /// 🔁 RETRY BUTTON
                          if (widget.showRetryButton &&
                              widget.onRetry != null) ...[
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _isRetrying ? null : _handleRetry,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.18),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Row(
                                  children: [
                                    if (_isRetrying)
                                      const SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          valueColor:
                                              AlwaysStoppedAnimation<Color>(
                                            Colors.white,
                                          ),
                                        ),
                                      )
                                    else
                                      const Icon(
                                        Icons.refresh,
                                        size: 14,
                                        color: Colors.white,
                                      ),
                                    const SizedBox(width: 4),
                                    Text(
                                      _isRetrying ? 'Retrying' : 'Retry',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.white,
                                        fontFamily: AppFont.fontFamily,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

enum ConnectionStatus {
  WiFi,
  Mobile,
  None,
  Poor,
}

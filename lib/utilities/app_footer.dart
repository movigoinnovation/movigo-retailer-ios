import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/view/customer_screen/account_screen/account_screen.dart';
import 'package:movigo/view/customer_screen/booking_screen/booking_screen.dart';
import 'package:movigo/view/customer_screen/coins/coin_milestone_animation.dart';
import 'package:movigo/view/customer_screen/coins/coin_tab_screen.dart';
import 'package:movigo/view/customer_screen/new_booking_flow/new_home_screen.dart';
import 'package:movigo/view/customer_screen/wallet_screen/wallet_screen.dart';
import 'app_color.dart';
import 'app_image.dart';
import 'app_language.dart';

class CustomBottomNav extends StatefulWidget {
  final UserType userType;
  final int initialIndex;
  final int bookingTabIndex;
  const CustomBottomNav({
    Key? key,
    required this.userType,
    this.initialIndex = 0,
    this.bookingTabIndex = 0,
  }) : super(key: key);
  @override
  State<CustomBottomNav> createState() => _CustomBottomNavState();
}

class _CustomBottomNavState extends State<CustomBottomNav> {
  late int selectedIndex;
  late final List<Widget> pages;
  String userType = "";
  StreamSubscription? _milestoneSubscription;
  // Built lazily on first visit, then kept alive (never removed from the
  // tree) so switching tabs doesn't dispose/recreate it — that was causing
  // a full reload + blink on every single tap of the Coins tab.
  Widget? _coinTab;

  bool get _isRetailer => widget.userType == UserType.retailer;

  @override
  void initState() {
    super.initState();
    selectedIndex = widget.initialIndex;
    if (selectedIndex == 2) _coinTab = const CoinTabScreen();
    final userController = Provider.of<UserController>(context, listen: false);

    setState(() {
      userType = userController.getUserType;
    });

    _initRetailerPusherChannel(userController);

    // Retailer wallet is non-functional (balance is never credited/debited for
    // retailers — bookings are cash, and the minimum-balance check is a
    // driver-only endpoint), so the tab is dropped for retailers only.
    pages = _isRetailer
        ? [
            const NewHomeScreen(),
            const BookingScreen(),
            AccountScreen(),
          ]
        : [
            const NewHomeScreen(),
            const BookingScreen(),
            WalletScreen(),
            AccountScreen(),
          ];
  }

  void _initRetailerPusherChannel(UserController userController) {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final userId = userController.getUserId;
      if (userId.isEmpty) return;
      final socketProvider = Provider.of<SocketProvider>(context, listen: false);
      await socketProvider.subscribeRetailerChannel(userId);
      _milestoneSubscription = socketProvider.milestoneStream.listen((data) async {
        final int bonusCoins   = (data['bonus_coins']   ?? 0 as num).toInt();
        final int totalBalance = (data['total_balance'] ?? 0 as num).toInt();
        if (mounted) {
          await CoinMilestoneAnimation.showIfNeeded(
            context,
            bonusCoins:   bonusCoins,
            totalBalance: totalBalance,
          );
        }
      });
    });
  }

  @override
  void dispose() {
    _milestoneSubscription?.cancel();
    super.dispose();
  }

  List<IconData> get activeIconData => _isRetailer
      ? [
          Icons.home_rounded,
          Icons.assignment_rounded,
          Icons.stars_rounded,
          Icons.person_rounded,
        ]
      : [
          Icons.home_rounded,
          Icons.assignment_rounded,
          Icons.stars_rounded,
          Icons.account_balance_wallet_rounded,
          Icons.person_rounded,
        ];

  List<IconData> get inactiveIconData => _isRetailer
      ? [
          Icons.home_outlined,
          Icons.assignment_outlined,
          Icons.stars_outlined,
          Icons.person_outline_rounded,
        ]
      : [
          Icons.home_outlined,
          Icons.assignment_outlined,
          Icons.stars_outlined,
          Icons.account_balance_wallet_outlined,
          Icons.person_outline_rounded,
        ];

  List<String> get labels => _isRetailer
      ? ['Home', 'Orders', 'Coins', 'Account']
      : ['Home', 'Orders', 'Coins', 'Payments', 'Account'];

  @override
  Widget build(BuildContext context) {
    final stackIndex = selectedIndex > 2 ? selectedIndex - 1 : selectedIndex;

    return Scaffold(
      backgroundColor: AppColor.secondaryColor,
      body: Stack(
        children: [
          Offstage(
            offstage: selectedIndex == 2,
            child: IndexedStack(
              index: stackIndex,
              children: pages,
            ),
          ),
          if (_coinTab != null)
            Offstage(
              offstage: selectedIndex != 2,
              child: _coinTab!,
            ),
        ],
      ),
      bottomNavigationBar: Builder(
        builder: (ctx) {
          // viewPadding is the raw system inset — always correct even inside
          // a Scaffold that already consumed padding.bottom via edgeToEdge.
          final bottomInset = MediaQuery.of(ctx).viewPadding.bottom;
          return Container(
            height: 72 + bottomInset,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(30),
                topRight: Radius.circular(30),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.08),
                  blurRadius: 12,
                  offset: const Offset(0, -4),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.only(bottom: bottomInset),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: List.generate(labels.length, (index) {
                  final bool isSelected = selectedIndex == index;
                  return Expanded(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => setState(() {
                        if (index == 2) _coinTab ??= const CoinTabScreen();
                        selectedIndex = index;
                      }),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            isSelected ? activeIconData[index] : inactiveIconData[index],
                            size: 24,
                            color: isSelected
                                ? (index == 2
                                    ? const Color(0xFFDAA520)
                                    : const Color(0xff1E4FFF))
                                : Colors.grey,
                          ),
                          const SizedBox(height: 4),
                          Text(
                            labels[index],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                              color: isSelected
                                  ? (index == 2
                                      ? const Color(0xFFDAA520)
                                      : const Color(0xff1E4FFF))
                                  : Colors.grey,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),
          );
        },
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:get/get.dart';
import 'package:provider/provider.dart';

import 'package:movigo/Controller/wallet_history_controller.dart';
import 'package:movigo/Provider/user_controller.dart';
import 'package:movigo/helper/date_time_format/date_time_format.dart';
import 'package:movigo/helper/shimmer/wallet_shimmer.dart';
import 'package:movigo/utilities/app_color.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_font.dart';
import 'package:movigo/utilities/app_footer.dart';
import 'package:movigo/utilities/app_image.dart';
import 'package:movigo/utilities/app_language.dart';
import 'add_money_screen.dart';

class WalletScreen extends StatefulWidget {
  const WalletScreen({super.key});

  @override
  State<WalletScreen> createState() => _WalletScreenState();
}

class _WalletScreenState extends State<WalletScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  String userId = "";

  @override
  void initState() {
    super.initState();
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );
    final userController = Provider.of<UserController>(context, listen: false);
    userId = userController.getUserId;

    _tabController = TabController(length: 2, vsync: this);

    Future.microtask(() {
      Provider.of<WalletHistoryController>(context, listen: false)
          .getWalletHistory(context, type: 'transaction');
    });

    _tabController.addListener(() {
      if (_tabController.indexIsChanging) return;
      Provider.of<WalletHistoryController>(context, listen: false)
          .getWalletHistory(
        context,
        type: _tabController.index == 0 ? 'transaction' : 'credit',
      );
    });
  }

  void _handleBack() {
    Get.offAll(() => const CustomBottomNav(
          userType: UserType.retailer,
          initialIndex: 1, // Booking tab
          bookingTabIndex: 0,
        ));
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return PopScope(
      canPop: false, // we handle pop manually
      onPopInvoked: (didPop) {
        if (didPop) return;
        _handleBack();
      },
      child: Scaffold(
        backgroundColor: Colors.white,

        /// APP BAR
        appBar: AppBar(
          backgroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          surfaceTintColor: Colors.white,
          toolbarHeight: 85,
          automaticallyImplyLeading: false,
          centerTitle: true,
          title: Padding(
            padding: EdgeInsets.only(top: size.height * 0.015),
            child: Text(
              AppLanguage.walletText[language],
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                fontFamily: AppFont.fontFamily,
                color: AppColor.blackColor,
              ),
            ),
          ),
          actions: [
            // if (_tabController.index == 1)
            Padding(
              padding: EdgeInsets.only(
                right: size.width * 0.04,
                top: size.height * 0.015,
              ),
              child: InkWell(
                onTap: () async {
                  final bool? isAdded =
                      await Get.to(() => const AddMoneyScreen());

                  if (isAdded == true && mounted) {
                    Provider.of<WalletHistoryController>(context, listen: false)
                        .getWalletHistory(context, type: 'credit');
                  }
                },
                child: Image.asset(
                  AppImage.pluswallet,
                  height: 40,
                  width: 40,
                ),
              ),
            ),
          ],
        ),

        /// BODY
        body: Column(
          children: [
            SizedBox(height: size.height * 0.02),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: size.width * 0.04),
              child: Container(
                height: size.height * 0.18,
                width: size.width,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  image: const DecorationImage(
                    image: AssetImage(AppImage.walletstar),
                    fit: BoxFit.fill,
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      AppLanguage.availableText[language],
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        fontFamily: AppFont.fontFamily,
                        color: Colors.white,
                      ),
                    ),
                    SizedBox(height: size.height * 0.005),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Image.asset(AppImage.coinwallet, height: 28),
                        SizedBox(width: size.width * 0.03),
                        Consumer<WalletHistoryController>(
                          builder: (context, wallet, _) {
                            return Text(
                              // "₹ ${wallet.walletBalance}",
                              "₹ ${(double.tryParse(wallet.walletBalance.toString()) ?? 0).toStringAsFixed(2)}",
                              style: const TextStyle(
                                fontSize: 30,
                                fontWeight: FontWeight.w700,
                                fontFamily: AppFont.fontFamily,
                                color: Colors.white,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: size.height * 0.03),
            TabBar(
              controller: _tabController,
              indicatorColor: AppColor.primaryColor,
              labelPadding: const EdgeInsets.symmetric(horizontal: 6),
              dividerColor: AppColor.greyColor,
              dividerHeight: 2.5,
              indicatorSize: TabBarIndicatorSize.tab,
              indicator: BoxDecoration(
                color: AppColor.primaryColor.withOpacity(0.05),
                border: const Border(
                  bottom: BorderSide(
                    width: 3,
                    color: AppColor.primaryColor,
                  ),
                ),
              ),
              labelColor: AppColor.primaryColor,
              unselectedLabelColor: AppColor.selectTpeColor,
              labelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                fontFamily: AppFont.fontFamily,
              ),
              unselectedLabelStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: AppFont.fontFamily,
              ),
              tabs: [
                Tab(
                  text: AppLanguage.transactionText[language],
                ),
                Tab(
                  text: AppLanguage.creditText[language],
                ),
              ],
            ),
            SizedBox(height: size.height * 0.01),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _transactionHistory(),
                  _creditHistory(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _transactionHistory() {
    return Consumer<WalletHistoryController>(
      builder: (context, wallet, _) {
        if (wallet.isLoading) {
          return const WalletTabShimmer();
        }

        if (wallet.historyList.isEmpty) {
          return const Center(child: Text("No transactions found"));
        }

        return RefreshIndicator(
          color: AppColor.primaryColor,
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 200));
            await wallet.getWalletHistory(
              context,
              type: 'transaction',
            );
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            itemCount: wallet.historyList.length,
            itemBuilder: (context, index) {
              final item = wallet.historyList[index];

              return _historyCard(
                id: item['transaction_id'],
                title: item['title'] ?? '',
                date: WalletDateTimeHelper.apiToFigmaDateTime(
                  item['created_at'],
                ),
                amount: "₹${item['amount']}",
                isCredit: item['type'] == 'Credit',
              );
            },
          ),
        );
      },
    );
  }

  /// ================= CREDIT HISTORY =================
  Widget _creditHistory() {
    return Consumer<WalletHistoryController>(
      builder: (context, wallet, _) {
        if (wallet.isLoading) {
          return const WalletTabShimmer();
        }

        if (wallet.historyList.isEmpty) {
          return const Center(child: Text("No credit history found"));
        }

        return RefreshIndicator(
          color: AppColor.primaryColor,
          onRefresh: () async {
            await Future.delayed(const Duration(milliseconds: 200));
            await wallet.getWalletHistory(
              context,
              type: 'credit',
            );
          },
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(10),
            itemCount: wallet.historyList.length,
            itemBuilder: (context, index) {
              final item = wallet.historyList[index];

              return _historyCard(
                title: item['title'] ?? '',
                date: WalletDateTimeHelper.apiToFigmaDateTime(
                  item['created_at'],
                ),
                amount: "₹${item['amount']}",
                isCredit: true,
              );
            },
          ),
        );
      },
    );
  }

  /// ================= COMMON CARD =================
  Widget _historyCard({
    String? id,
    required String title,
    required String date,
    required String amount,
    required bool isCredit,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xffFDFDFD),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 8,
            spreadRadius: 0,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          /// LEFT
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (id != null) ...[
                Text(
                  id,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    fontFamily: AppFont.fontFamily,
                    color: AppColor.thirdTextColor,
                  ),
                ),
                SizedBox(height: MediaQuery.of(context).size.height * 0.005),
              ],
              Text(
                title,
                style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    fontFamily: AppFont.fontFamily,
                    color: Color(0xff495057)),
              ),
              SizedBox(height: MediaQuery.of(context).size.height * 0.005),
              Text(
                date,
                style: const TextStyle(
                  fontSize: 12,
                  fontFamily: AppFont.fontFamily,
                  fontWeight: FontWeight.w500,
                  color: Color(0xff7A7A7A),
                ),
              ),
            ],
          ),

          Text(
            isCredit ? "+ $amount" : "- $amount",
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              fontFamily: AppFont.fontFamily,
              color: isCredit ? AppColor.successCOlor : AppColor.redAppColor,
            ),
          ),
        ],
      ),
    );
  }

  final transactionHistory = [
    {
      "id": "#WAL73838769082",
      "title": "Refund - Cancel Booking",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
      "isCredit": true,
    },
    {
      "id": "#WAL73838769082",
      "title": "Booking - Mini Truck",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
      "isCredit": false,
    },
    {
      "id": "#WAL73838769082",
      "title": "Booking - Mini Truck",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
      "isCredit": false,
    },
  ];

  final creditHistory = [
    {
      "title": "Add Amount",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
    },
    {
      "title": "Add Amount",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
    },
    {
      "title": "Add Amount",
      "date": "25 Jan, 2025 • 09:18 AM",
      "amount": "₹500",
    },
  ];
}

import 'package:provider/provider.dart';
import 'theme_provider.dart';
import 'package:provider/single_child_widget.dart';

import 'package:movigo/Controller/Notification/notification_provider.dart';
import 'package:movigo/Controller/NotificationUnreadCountController.dart';
import 'package:movigo/Controller/SlotController.dart';
import 'package:movigo/Controller/accepted_booking_provider.dart';
import 'package:movigo/Controller/check_booking_status_controller.dart';
import 'package:movigo/Controller/get_booking_category_list_provider.dart';
import 'package:movigo/Controller/get_booking_details_provider.dart';
import 'package:movigo/Controller/get_vehicle_list_provider.dart';
import 'package:movigo/Controller/helpline_controller.dart';
import 'package:movigo/Controller/wallet_history_controller.dart';
import 'package:movigo/Controller/retailer_home_cotroller.dart';
import 'package:movigo/Controller/retailer_wallet_minimum_controller.dart';
// Feature 3: Surge multiplier controller
import 'package:movigo/Controller/surge_controller.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'package:movigo/Provider/socket_connection/socket_provider.dart';
import 'package:movigo/Provider/user_controller.dart';

class AppProviders {
  static List<SingleChildWidget> providers = [
    ChangeNotifierProvider(create: (_) => SocketProvider()),
    ChangeNotifierProvider(create: (_) => PostApiProvider()),
    ChangeNotifierProvider(create: (_) => UserController()),

    ChangeNotifierProvider(create: (_) => NotificationUnreadCountController()),
    ChangeNotifierProvider(create: (_) => NotificationController()),
    ChangeNotifierProvider(create: (_) => SlotController()),
    ChangeNotifierProvider(create: (_) => RetailerWalletMinimumController()),

    // Feature 3: Surge multiplier
    ChangeNotifierProvider(create: (_) => SurgeController()),

    ChangeNotifierProvider(create: (_) => VehicleTypeController()),
    ChangeNotifierProvider(create: (_) => BookingCategoryController()),
    ChangeNotifierProvider(create: (_) => CheckBookingStatusController()),
    ChangeNotifierProvider(create: (_) => WalletHistoryController()),
    ChangeNotifierProvider(create: (_) => BookingDetailController()),
    ChangeNotifierProvider(create: (_) => AcceptedBookingController()),
    ChangeNotifierProvider(create: (_) => HelplineController()),
    ChangeNotifierProvider(create: (_) => RetailerHomeController()),

    ChangeNotifierProvider(create: (_) => ThemeProvider()),
    //
  ];
}

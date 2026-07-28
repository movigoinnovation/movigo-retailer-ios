/// ================= DATE HELPERS =================
class BookingDateTimeHelper {
  /// UI: dd-MM-yyyy → Figma UI: 08 Oct, 2025
  static String uiDateToFigma(String? date) {
    if (date == null || date.isEmpty) return '-';

    try {
      final parts = date.split('-'); // dd-MM-yyyy
      final day = int.parse(parts[0]);
      final month = int.parse(parts[1]);
      final year = parts[2];

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];

      return "${day.toString().padLeft(2, '0')} "
          "${months[month - 1]}, $year";
    } catch (e) {
      return '-';
    }
  }

  /// UI: dd-MM-yyyy → API: yyyy-MM-dd
  static String uiToApiDate(String date) {
    final parts = date.split('-');
    return "${parts[2]}-${parts[1]}-${parts[0]}";
  }

  /// UI shift text → API shift enum
  static String apiShift(String shift) {
    if (shift.contains("Morning")) return "Morning";
    if (shift.contains("Afternoon")) return "Afternoon";
    if (shift.contains("Evening")) return "Evening";
    return shift;
  }

  /// Backend `pickup_date` is a Mongoose Date (date-only, always midnight
  /// UTC), so the raw JSON value is an ISO string like
  /// "2026-07-13T00:00:00.000Z" — displaying it unparsed leaks "T00:00:00"
  /// into the UI. This extracts just the calendar date: "13 Jul, 2026".
  static String isoDateToUi(String? isoDate) {
    if (isoDate == null || isoDate.isEmpty) return '-';
    try {
      final d = DateTime.parse(isoDate);
      const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
      return "${d.day.toString().padLeft(2, '0')} ${months[d.month - 1]}, ${d.year}";
    } catch (e) {
      return isoDate;
    }
  }
}

/// ================= TIME HELPERS =================
class BookingTimeHelper {
  /// Converts any slot string to FIGMA time format
  static String toFigma(String? slot) {
    if (slot == null || slot.isEmpty) return '';

    try {
      String value = slot;

      // Extract text inside ()
      final bracketMatch = RegExp(r'\(([^)]+)\)').firstMatch(value);
      if (bracketMatch != null) {
        value = bracketMatch.group(1)!;
      }

      value = value.replaceAll('–', '-');

      final parts = value.split('-');
      if (parts.length != 2) return value.trim();

      final start = _formatSingleTime(parts[0]);
      final end = _formatSingleTime(parts[1]);

      return "$start - $end";
    } catch (e) {
      return slot;
    }
  }

  static String _formatSingleTime(String input) {
    String t = input.trim().toUpperCase();

    final match = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(AM|PM)').firstMatch(t);

    if (match == null) return input.trim();

    final hour = match.group(1)!.padLeft(2, '0');
    final minute = (match.group(2) ?? '00').padLeft(2, '0');
    final meridian = match.group(3)!;

    return "$hour:$minute $meridian";
  }
}

/// ================= API DATETIME → FIGMA FORMAT =================
/// Input  : 2026-01-29T06:46:59.088Z
/// Output : 29 Jan, 2026 • 06:46 AM
class WalletDateTimeHelper {
  static String apiToFigmaDateTime(String? apiDate) {
    if (apiDate == null || apiDate.isEmpty) return '-';

    try {
      final DateTime dateTime = DateTime.parse(apiDate).toLocal();

      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];

      final day = dateTime.day.toString().padLeft(2, '0');
      final month = months[dateTime.month - 1];
      final year = dateTime.year;

      int hour = dateTime.hour;
      final minute = dateTime.minute.toString().padLeft(2, '0');

      final meridian = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;

      final hourStr = hour.toString().padLeft(2, '0');

      return "$day $month, $year • $hourStr:$minute $meridian";
    } catch (e) {
      return '-';
    }
  }
}

/// ================= API CREATED_AT → FIGMA CARD DATE =================
/// Input  : "Feb 02 2026, 03:49 PM"
/// Output : "02 Feb 2026, 03:49pm"
class BookingCreatedAtHelper {
  static String toCardFormat(String? value) {
    if (value == null || value.isEmpty) return '-';

    try {
      // Split date & time
      final parts = value.split(',');
      if (parts.length != 2) return value;

      final datePart = parts[0].trim(); // Feb 02 2026
      final timePart = parts[1].trim(); // 03:49 PM

      final dateTokens = datePart.split(' ');
      if (dateTokens.length != 3) return value;

      final month = dateTokens[0];
      final day = dateTokens[1];
      final year = dateTokens[2];

      // Time
      final timeTokens = timePart.split(' ');
      final time = timeTokens[0]; // 03:49
      final meridian = timeTokens[1].toLowerCase(); // pm / am

      return "$day $month $year, $time$meridian";
    } catch (e) {
      return value;
    }
  }
}

class NotificationTimeHelper {
  /// Input: 2026-02-07T09:47:15:857Z
  /// Output:
  /// - "Just now" (if within 1 minute)
  /// - Else: "07 Feb 2026, 03:17 PM"
  static String format(String? apiTime) {
    if (apiTime == null || apiTime.isEmpty) return '-';

    try {
      DateTime serverTime = DateTime.parse(apiTime).toLocal();
      DateTime now = DateTime.now();

      final diff = now.difference(serverTime);

      // ✅ If within 60 seconds → Just now
      if (diff.inSeconds < 60) {
        return "Just now";
      }

      // Else → Figma style date time
      const months = [
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec'
      ];

      final day = serverTime.day.toString().padLeft(2, '0');
      final month = months[serverTime.month - 1];
      final year = serverTime.year;

      int hour = serverTime.hour;
      final minute = serverTime.minute.toString().padLeft(2, '0');

      final meridian = hour >= 12 ? 'PM' : 'AM';
      hour = hour % 12;
      if (hour == 0) hour = 12;

      final hourStr = hour.toString().padLeft(2, '0');

      return "$day $month $year, $hourStr:$minute $meridian";
    } catch (e) {
      return '-';
    }
  }
}

class BookingCardDateTimeHelper {
  /// Supports:
  /// 1) date = "Feb 11 2026", time = "10AM"
  /// 2) date = "Feb 03 2026, 02:18 PM", time = ""
  /// 3) date = "Feb 03 2026", time = "02:18 PM"
  ///
  /// Output:
  /// "03 Feb 2026, 02:18pm"
  static String format(String? date, String? time) {
    if ((date == null || date.isEmpty) && (time == null || time.isEmpty)) {
      return '-';
    }

    try {
      String rawDate = date ?? '';
      String rawTime = time ?? '';

      // ✅ If date already contains time like: "Feb 03 2026, 02:18 PM"
      if (rawDate.contains(',')) {
        final parts = rawDate.split(',');
        rawDate = parts[0].trim(); // "Feb 03 2026"
        if (parts.length > 1 && rawTime.isEmpty) {
          rawTime = parts[1].trim(); // "02:18 PM"
        }
      }

      // ---- Parse Date ----
      String formattedDate = '';
      if (rawDate.isNotEmpty) {
        final parts = rawDate.split(' '); // ["Feb","03","2026"]
        if (parts.length == 3) {
          final month = parts[0];
          final day = parts[1].padLeft(2, '0');
          final year = parts[2];
          formattedDate = "$day $month $year";
        }
      }

      // ---- Parse Time ----
      String formattedTime = '';
      if (rawTime.isNotEmpty) {
        String t = rawTime.toUpperCase().replaceAll(' ', '');

        final match = RegExp(r'(\d{1,2})(?::(\d{2}))?(AM|PM)').firstMatch(t);
        if (match != null) {
          int hour = int.parse(match.group(1)!);
          final minute = (match.group(2) ?? '00').padLeft(2, '0');
          String meridian = match.group(3)!.toLowerCase(); // am / pm

          final hourStr = hour.toString().padLeft(2, '0');
          formattedTime = "$hourStr:$minute$meridian";
        }
      }

      if (formattedDate.isNotEmpty && formattedTime.isNotEmpty) {
        return "$formattedDate, $formattedTime";
      } else if (formattedDate.isNotEmpty) {
        return formattedDate;
      } else if (formattedTime.isNotEmpty) {
        return formattedTime;
      } else {
        return '-';
      }
    } catch (e) {
      return '-';
    }
  }
}

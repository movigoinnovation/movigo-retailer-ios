// ignore_for_file: avoid_print, use_build_context_synchronously

import 'dart:convert';
import 'dart:developer';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:movigo/utilities/app_config_provider.dart';
import 'package:movigo/utilities/app_constant.dart';
import 'package:movigo/utilities/app_snackbar_toast_message.dart';
import 'package:movigo/view/customer_screen/onboarding/login_screen.dart';
import 'package:movigo/Provider/Post_Provider/post_api_provider.dart';
import 'common_shared_prefrences.dart';

void _log(Object? msg) { if (kDebugMode) debugPrint(msg?.toString()); }

// ------------------ COMMON REQUEST HANDLER ------------------
Future<Map<String, dynamic>?> _handleRequest(
  Future<http.Response> Function(Uri url, Map<String, String> headers)
      requestFn,
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  try {
    final Uri url = Uri.parse("${AppConfigProvider.apiUrl}$endpoint");
    _log('url $url');

    final Map<String, String> mergedHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo',
      ...headers ?? {},
    };

    final response = await requestFn(url, mergedHeaders).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw Exception('Request timed out. Please check your connection.'),
    );
    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    return null;
  }
}

Map<String, dynamic> _safeDecodeBody(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is Map<String, dynamic>) return decoded;
    if (decoded is Map) return Map<String, dynamic>.from(decoded);
    return {'success': false, 'message': decoded?.toString() ?? 'Invalid server response'};
  } catch (_) {
    return {'success': false, 'message': 'Invalid server response. Please try again.'};
  }
}

String _messageAtLanguage(List list) {
  if (list.isEmpty) return 'An error occurred';
  final idx = language >= 0 && language < list.length ? language : 0;
  return list[idx].toString();
}

// ------------------ STATUS CODE HANDLER ------------------
Map<String, dynamic>? _handleStatusCode(
    http.Response response, BuildContext? context) {
  final statusCode = response.statusCode;
  final Map<String, dynamic> body = _safeDecodeBody(response.body);

  // Success
  if (statusCode == 200 || statusCode == 201) {
    return body;
  }

  String errorMessage = _getErrorMessage(body);

  if (statusCode == 400) {
    if (context != null) {
      SnackBarToastMessage.showSnackBar(context, errorMessage);
    }
    return null;
  }

  if (statusCode == 401 || statusCode == 403) {
    // A guest (no token yet) hitting an account-gated endpoint isn't a
    // "session expired" — there was never a session to expire. Let the
    // calling provider's own empty/error fallback handle it quietly
    // instead of yanking a browsing guest back to the login screen.
    if (AppConstant.token.isEmpty) {
      return null;
    }
    if (context != null) {
      // force_logout = true means another device logged in → wipe local session
      // Regular 401 (transient/race-condition) → redirect but keep cache so next app-start works
      final bool isForceLogout = body['force_logout'] == true;
      _redirectToLogin(context, errorMessage, clearCache: isForceLogout);
    }
    return null;
  }
  if (statusCode == 423) {
    if (context != null) {
      _redirectToLogin(context, errorMessage, clearCache: true);
    }
    return null;
  }

  if (statusCode == 500) {
    if (context != null) {
      SnackBarToastMessage.showSnackBar(
          context, "Server error. Please try again later.");
    }
    return null;
  }

  if (context != null) {
    SnackBarToastMessage.showSnackBar(context, errorMessage);
  }
  return null;
}

// ------------------ GET ERROR MESSAGE ------------------
String _getErrorMessage(dynamic body) {
  if (body == null) return "An error occurred";

  final message = body['message'];
  if (message is List) return _messageAtLanguage(message);
  if (message is Map && message[language] != null) return message[language].toString();
  if (message != null) return message.toString();

  return "An error occurred";
}

// ------------------ REDIRECT TO LOGIN ------------------
// clearCache should only be true for intentional logouts (force_logout from another
// device, explicit logout, account deletion). Spurious 401s must NOT wipe the cache
// or the user loses their session on every transient server error.
void _redirectToLogin(BuildContext context, String message, {bool clearCache = false}) {
  SnackBarToastMessage.showSnackBar(context, message);
  if (clearCache) {
    CacheHelper.clearAll();
    AppConstant.token = '';
    AppConstant.selectedFooterIndex = 0;
    AppContentCache().clear();
  }
  Navigator.pushAndRemoveUntil(
    context,
    MaterialPageRoute(builder: (context) => LoginScreen()),
    (route) => false,
  );
}

// ------------------ GET DATA (HEADERS ONLY - WITH TOKEN) ------------------
Future<Map<String, dynamic>?> getData(
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.get(url, headers: h),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ GET DATA WITH PARAMS ------------------
Future<Map<String, dynamic>?> getDataWithParams(
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
  Map<String, dynamic>? params,
}) async {
  try {
    // Build the base URL
    String fullUrl = "${AppConfigProvider.apiUrl}$endpoint";
    log('$fullUrl');

    // Add query parameters if provided
    if (params != null && params.isNotEmpty) {
      final uri = Uri.parse(fullUrl);
      final newUri = uri.replace(
          queryParameters:
              params.map((key, value) => MapEntry(key, value.toString())));
      fullUrl = newUri.toString();
    }

    final Uri url = Uri.parse(fullUrl);
    _log('url $url');

    final Map<String, String> mergedHeaders = {
      'User-Agent': 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo',
      ...headers ?? {},
    };
    final response = await http.get(url, headers: mergedHeaders);
    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    return null;
  }
}

// ------------------ POST DATA (HEADERS ONLY - WITH TOKEN, NO BODY) ------------------
Future<Map<String, dynamic>?> postData(
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.post(url, headers: h),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ POST FORM DATA ------------------
Future<Map<String, dynamic>?> postFormData(
  String endpoint,
  Map<String, String> fields,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  try {
    final Uri url = Uri.parse("${AppConfigProvider.apiUrl}$endpoint");
    _log('url $url');

    var request = http.MultipartRequest('POST', url);
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo';
    if (headers != null) request.headers.addAll(headers);
    request.fields.addAll(fields);

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    return null;
  }
}

// ------------------ POST JSON DATA ------------------
Future<Map<String, dynamic>?> postJsonData(
  String endpoint,
  Map<String, dynamic> jsonData,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.post(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...h,
      },
      body: jsonEncode(jsonData),
    ),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ PUT JSON DATA ------------------
Future<Map<String, dynamic>?> putJsonData(
  String endpoint,
  Map<String, dynamic> jsonData,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.put(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...h,
      },
      body: jsonEncode(jsonData),
    ),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ POST MULTIPART DATA (FOR FILE AND FIELD UPLOAD) ------------------
Future<Map<String, dynamic>?> postMultipartData(
  String endpoint,
  Map<String, String> fields,
  BuildContext? context, {
  Map<String, String>? headers,
  Map<String, XFile>? files,
}) async {
  try {
    final Uri url = Uri.parse("${AppConfigProvider.apiUrl}$endpoint");
    _log('url $url');

    var request = http.MultipartRequest('POST', url);
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo';
    if (headers != null) request.headers.addAll(headers);

    request.fields.addAll(fields);

    if (files != null) {
      for (var entry in files.entries) {
        if (entry.value != null) {
          List<int> imageBytes = await entry.value.readAsBytes();
          http.MultipartFile imageFile = http.MultipartFile.fromBytes(
            entry.key,
            imageBytes,
            filename: '${entry.key}.jpg',
          );
          request.files.add(imageFile);
        }
      }
    }

    _log("request.fields: ${request.fields}");
    _log("request.files: ${request.files}");

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    return null;
  }
}

// ------------------ POST MULTIPART DATA (FOR FILE AND FIELD UPLOAD) ------------------
Future<Map<String, dynamic>?> postImageMultipartData(
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
  Map<String, String>? fields,
  Map<String, XFile>? files,
  Map<String, List<XFile>>? filesList,
}) async {
  try {
    final Uri url = Uri.parse("${AppConfigProvider.apiUrl}$endpoint");
    _log('URL: $url');

    var request = http.MultipartRequest('POST', url);
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo';

    // Add headers
    if (headers != null) request.headers.addAll(headers);

    // Add text fields
    if (fields != null) request.fields.addAll(fields);

    // Add single files
    if (files != null && files.isNotEmpty) {
      for (var entry in files.entries) {
        List<int> imageBytes = await entry.value.readAsBytes();

        String filename =
            entry.value.name.isNotEmpty ? entry.value.name : '${entry.key}.jpg';

        http.MultipartFile imageFile = http.MultipartFile.fromBytes(
          entry.key,
          imageBytes,
          filename: filename,
        );
        request.files.add(imageFile);
      }
    }

    // Add list of files
    if (filesList != null && filesList.isNotEmpty) {
      for (var entry in filesList.entries) {
        for (int i = 0; i < entry.value.length; i++) {
          XFile file = entry.value[i];
          List<int> imageBytes = await file.readAsBytes();

          String filename =
              file.name.isNotEmpty ? file.name : '${entry.key}_$i.jpg';

          http.MultipartFile imageFile = http.MultipartFile.fromBytes(
            entry.key,
            imageBytes,
            filename: filename,
          );
          request.files.add(imageFile);
        }
      }
    }

    _log("Request Fields: ${request.fields}");
    _log(
        "Request Files: ${request.files.map((f) => '${f.field}: ${f.filename}').toList()}");

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    if (context != null && context.mounted) {
      SnackBarToastMessage.showSnackBar(
          context, "Upload failed. Please try again.");
    }
    return null;
  }
}

// ------------------ GET FORM DATA (LEGACY - USE getData INSTEAD) ------------------
Future<Map<String, dynamic>?> getFormData(
  String endpoint,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.get(url, headers: h),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ PUT MULTIPART DATA (FOR FILE AND FIELD UPLOAD) ------------------
Future<Map<String, dynamic>?> putMultipartData(
  String endpoint,
  Map<String, String> fields,
  BuildContext? context, {
  Map<String, String>? headers,
  Map<String, XFile>? files,
}) async {
  try {
    final Uri url = Uri.parse("${AppConfigProvider.apiUrl}$endpoint");
    _log('url $url');

    var request = http.MultipartRequest('PUT', url); // 👈 IMPORTANT
    request.headers['User-Agent'] = 'Mozilla/5.0 (Linux; Android 10; Mobile) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36 movigo';
    if (headers != null) request.headers.addAll(headers);

    request.fields.addAll(fields);

    if (files != null) {
      for (var entry in files.entries) {
        List<int> imageBytes = await entry.value.readAsBytes();
        http.MultipartFile imageFile = http.MultipartFile.fromBytes(
          entry.key,
          imageBytes,
          filename: entry.value.name.isNotEmpty
              ? entry.value.name
              : '${entry.key}.jpg',
        );
        request.files.add(imageFile);
      }
    }

    _log("request.fields: ${request.fields}");
    _log("request.files: ${request.files}");

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    _log("Status Code: ${response.statusCode}");
    _log("Response Body: ${response.body}");

    return _handleStatusCode(response, context);
  } catch (e) {
    _log("API error: $e");
    return null;
  }
}

// ------------------ DELETE JSON DATA ------------------
Future<Map<String, dynamic>?> deleteJsonData(
  String endpoint,
  Map<String, dynamic> jsonData,
  BuildContext? context, {
  Map<String, String>? headers,
}) async {
  return _handleRequest(
    (url, h) => http.delete(
      url,
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        ...h,
      },
      body: jsonEncode(jsonData),
    ),
    endpoint,
    context,
    headers: headers,
  );
}

// ------------------ COMMON HELPER ------------------
class CommonHelper {
  static void handleInactiveUserRedirect(BuildContext context, dynamic res) {
    if (res != null && res['active_flag'] == 0) {
      _redirectToLogin(context, _getErrorMessage(res), clearCache: true);
    }
  }
}

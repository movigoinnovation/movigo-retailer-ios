import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:movigo/utilities/app_config_provider.dart';

import 'package:http/http.dart' as http;

import 'Post_Provider/post_api_provider.dart';

Future<void> fetchAllContent(Function(List) onDataReady) async {
  if (AppContentCache().hasData) {
    onDataReady(AppContentCache().contentArr!);
    return;
  }
  final url = Uri.parse("${AppConfigProvider.apiUrl}manage/all_content");
  try {
    final response = await http.get(url);
    if (kDebugMode) print('response.statusCode ${response.statusCode}');
    if (response.statusCode == 200) {
      final res = jsonDecode(response.body);
      if (kDebugMode) print('res ${res['success']}');
      if (res['success'] == true) {
        List data = res['data'];
        AppContentCache().contentArr = data;
        onDataReady(data);
      }
    }
  } catch (e) {
    if (kDebugMode) print("Error fetching content: $e");
  }
}

import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FuelApi {
  FuelApi()
      : dio = Dio(BaseOptions(
            baseUrl: const String.fromEnvironment('API_BASE_URL',
                defaultValue: 'http://10.0.2.2:3000'),
            connectTimeout: const Duration(seconds: 12),
            receiveTimeout: const Duration(seconds: 20),
            headers: {'Accept': 'application/json'}));
  final Dio dio;
  Future<Map<String, dynamic>> cachedGet(String path,
      {Map<String, dynamic>? query}) async {
    final key = 'cache:$path:${query ?? {}}';
    final prefs = await SharedPreferences.getInstance();
    try {
      final response = await dio.get(path, queryParameters: query);
      final data = Map<String, dynamic>.from(response.data as Map);
      if (data['success'] != true) throw StateError('API returned an error');
      await prefs.setString(key, jsonEncode(data));
      await prefs.setString('lastFetch', DateTime.now().toIso8601String());
      return {...data, '_cached': false};
    } on DioException {
      final cached = prefs.getString(key);
      if (cached != null)
        return {
          ...Map<String, dynamic>.from(jsonDecode(cached) as Map),
          '_cached': true
        };
      rethrow;
    }
  }
}

import 'dart:async';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:gia_xang_dau/app.dart';
import 'package:gia_xang_dau/core/api.dart';
import 'package:gia_xang_dau/core/firebase_config.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

// The backend currently stores registration tokens and sends with the token-based Admin API.
// ignore_for_file: deprecated_member_use

const notificationFuelNames = <String, String>{
  'E5_RON_92': 'Xăng E5 RON 92',
  'E10_RON_95_III': 'Xăng E10 RON 95-III',
  'E10_RON_95_V': 'Xăng E10 RON 95-V',
  'RON_95_III': 'Xăng RON 95-III',
  'RON_95_V': 'Xăng RON 95-V',
  'DIESEL_001S': 'Dầu diesel 0,001S',
  'DIESEL_005S': 'Dầu diesel 0.05S',
  'KEROSENE': 'Dầu hỏa',
  'MAZUT_180CST_35S': 'Dầu mazut 180CST 3.5S',
};

const allNotificationFuelCodes = <String>[
  'E5_RON_92',
  'E10_RON_95_III',
  'E10_RON_95_V',
  'RON_95_III',
  'RON_95_V',
  'DIESEL_001S',
  'DIESEL_005S',
  'KEROSENE',
  'MAZUT_180CST_35S',
];

final pushNotifications = PushNotificationService(FuelApi());

class PushNotificationPreferences {
  const PushNotificationPreferences({
    required this.enabled,
    required this.fuelCodes,
    required this.region,
    required this.direction,
  });

  factory PushNotificationPreferences.defaults(String region) =>
      PushNotificationPreferences(
        enabled: false,
        fuelCodes: allNotificationFuelCodes.toSet(),
        region: region,
        direction: 'both',
      );

  factory PushNotificationPreferences.fromMap(
    Map<String, dynamic> values, {
    required String fallbackRegion,
  }) =>
      PushNotificationPreferences(
        enabled: values['notificationsEnabled'] == true,
        fuelCodes: (values['selectedFuelCodes'] as List? ?? const [])
            .whereType<String>()
            .toSet(),
        region: values['selectedRegion'] == 'REGION_2'
            ? 'REGION_2'
            : (values['selectedRegion'] == 'REGION_1'
                ? 'REGION_1'
                : fallbackRegion),
        direction: const ['increase', 'decrease', 'both']
                .contains(values['changeDirection'])
            ? values['changeDirection'] as String
            : 'both',
      );

  final bool enabled;
  final Set<String> fuelCodes;
  final String region;
  final String direction;

  PushNotificationPreferences copyWith({
    bool? enabled,
    Set<String>? fuelCodes,
    String? region,
    String? direction,
  }) =>
      PushNotificationPreferences(
        enabled: enabled ?? this.enabled,
        fuelCodes: fuelCodes ?? this.fuelCodes,
        region: region ?? this.region,
        direction: direction ?? this.direction,
      );

  Map<String, Object> toApiMap() => {
        'notificationsEnabled': enabled,
        'selectedFuelCodes': fuelCodes.toList()..sort(),
        'selectedRegion': region,
        'changeDirection': direction,
      };
}

class PushNotificationService {
  PushNotificationService(this._api);

  final FuelApi _api;
  bool _firebaseReady = false;
  String? initializationError;
  StreamSubscription<String>? _tokenSubscription;

  bool get isFirebaseReady => _firebaseReady;

  Future<void> initialize() async {
    final options = FirebaseConfig.options;
    if (options == null) return;
    try {
      if (Firebase.apps.isEmpty) {
        await Firebase.initializeApp(options: options);
      }
      _firebaseReady = true;
      final messaging = FirebaseMessaging.instance;
      await messaging.setForegroundNotificationPresentationOptions(
        alert: true,
        badge: true,
        sound: true,
      );
      FirebaseMessaging.onMessage.listen(_showForegroundMessage);
      FirebaseMessaging.onMessageOpenedApp.listen(_openMessage);
      _tokenSubscription ??=
          messaging.onTokenRefresh.listen(_uploadRefreshedToken);
    } on Object catch (error) {
      initializationError = error.toString();
    }
  }

  Future<void> handleInitialMessage() async {
    if (!_firebaseReady) return;
    final message = await FirebaseMessaging.instance.getInitialMessage();
    if (message != null) _openMessage(message);
  }

  Future<PushNotificationPreferences> loadPreferences({
    required String fallbackRegion,
  }) async {
    final local = await SharedPreferences.getInstance();
    var preferences = PushNotificationPreferences(
      enabled: local.getBool(_enabledKey) ?? false,
      fuelCodes:
          (local.getStringList(_fuelCodesKey) ?? allNotificationFuelCodes)
              .toSet(),
      region: local.getString(_regionKey) ?? fallbackRegion,
      direction: local.getString(_directionKey) ?? 'both',
    );
    final auth = _readAuth(local);
    if (auth != null) {
      try {
        if (local.getBool(_pendingSyncKey) == true) {
          await _api.dio.put<void>(
            '/api/v1/devices/${auth.installationId}/preferences',
            data: preferences.toApiMap(),
            options: _authOptions(auth),
          );
          await local.remove(_pendingSyncKey);
          return preferences;
        }
        final response = await _api.dio.get<Map<String, dynamic>>(
          '/api/v1/devices/${auth.installationId}/preferences',
          options: _authOptions(auth),
        );
        final data = response.data?['data'];
        if (response.data?['success'] == true && data is Map) {
          preferences = PushNotificationPreferences.fromMap(
            Map<String, dynamic>.from(data),
            fallbackRegion: fallbackRegion,
          );
          await _writeLocal(local, preferences);
        }
      } on Object {
        // The saved local preferences remain available while the API is offline.
      }
    }
    return preferences;
  }

  Future<void> enable(PushNotificationPreferences preferences) async {
    if (!_firebaseReady) {
      throw StateError(
        initializationError == null
            ? 'Firebase chưa được cấu hình cho bản ứng dụng này.'
            : 'Không khởi tạo được Firebase. Kiểm tra cấu hình ứng dụng.',
      );
    }
    if (preferences.fuelCodes.isEmpty) {
      throw StateError('Hãy chọn ít nhất một loại nhiên liệu.');
    }
    final messaging = FirebaseMessaging.instance;
    final permission = await messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (permission.authorizationStatus != AuthorizationStatus.authorized &&
        permission.authorizationStatus != AuthorizationStatus.provisional) {
      throw StateError('Bạn chưa cho phép ứng dụng gửi thông báo.');
    }
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      var apnsToken = await messaging.getAPNSToken();
      for (var attempt = 0; apnsToken == null && attempt < 8; attempt++) {
        await Future<void>.delayed(const Duration(seconds: 1));
        apnsToken = await messaging.getAPNSToken();
      }
      if (apnsToken == null) {
        throw StateError('iPhone chưa nhận được mã APNs từ Apple.');
      }
    }
    final token = await messaging.getToken();
    if (token == null || token.isEmpty) {
      throw StateError(
          'Firebase chưa cấp được mã nhận thông báo cho thiết bị.');
    }
    final local = await SharedPreferences.getInstance();
    final auth = await _ensureRegistered(local);
    await _api.dio.put<void>(
      '/api/v1/devices/${auth.installationId}/token',
      data: {'fcmToken': token},
      options: _authOptions(auth),
    );
    final enabled = preferences.copyWith(enabled: true);
    await _api.dio.put<void>(
      '/api/v1/devices/${auth.installationId}/preferences',
      data: enabled.toApiMap(),
      options: _authOptions(auth),
    );
    await _writeLocal(local, enabled);
    await local.remove(_pendingSyncKey);
  }

  Future<void> disable(PushNotificationPreferences preferences) async {
    final local = await SharedPreferences.getInstance();
    final disabled = preferences.copyWith(enabled: false);
    await _writeLocal(local, disabled);
    final auth = _readAuth(local);
    try {
      if (auth != null) {
        await local.setBool(_pendingSyncKey, true);
        await _api.dio.put<void>(
          '/api/v1/devices/${auth.installationId}/preferences',
          data: disabled.toApiMap(),
          options: _authOptions(auth),
        );
        await local.remove(_pendingSyncKey);
      } else {
        await local.remove(_pendingSyncKey);
      }
    } finally {
      if (_firebaseReady) {
        try {
          await FirebaseMessaging.instance.deleteToken();
        } on Object {
          // The server preference is already disabled; token cleanup can retry later.
        }
      }
    }
  }

  Future<void> savePreferences(
    PushNotificationPreferences preferences,
  ) async {
    final local = await SharedPreferences.getInstance();
    final auth = _readAuth(local);
    if (auth != null) {
      await _api.dio.put<void>(
        '/api/v1/devices/${auth.installationId}/preferences',
        data: preferences.toApiMap(),
        options: _authOptions(auth),
      );
      await local.remove(_pendingSyncKey);
    } else if (preferences.enabled) {
      throw StateError('Hãy bật thông báo để đăng ký thiết bị trước.');
    }
    await _writeLocal(local, preferences);
  }

  Future<_DeviceAuth> _ensureRegistered(SharedPreferences local) async {
    final existing = _readAuth(local);
    if (existing != null) return existing;
    final installationId = local.getString(_installationIdKey) ?? _newId();
    await local.setString(_installationIdKey, installationId);
    final packageInfo = await PackageInfo.fromPlatform();
    final response = await _api.dio.post<Map<String, dynamic>>(
      '/api/v1/devices/register',
      data: {
        'installationId': installationId,
        'platform':
            defaultTargetPlatform == TargetPlatform.iOS ? 'ios' : 'android',
        'appVersion': '${packageInfo.version}+${packageInfo.buildNumber}',
      },
    );
    final data = response.data?['data'];
    final credential = data is Map ? data['credential'] : null;
    if (response.data?['success'] != true || credential is! String) {
      throw StateError('Máy chủ không đăng ký được thiết bị.');
    }
    await local.setString(_credentialKey, credential);
    return _DeviceAuth(installationId, credential);
  }

  Future<void> _uploadRefreshedToken(String token) async {
    final local = await SharedPreferences.getInstance();
    if (local.getBool(_enabledKey) != true || !_firebaseReady) return;
    try {
      final auth = await _ensureRegistered(local);
      await _api.dio.put<void>(
        '/api/v1/devices/${auth.installationId}/token',
        data: {'fcmToken': token},
        options: _authOptions(auth),
      );
    } on Object {
      // The next app start or explicit enable action retries token registration.
    }
  }

  void _showForegroundMessage(RemoteMessage message) {
    final title = message.notification?.title ?? 'Có cập nhật giá nhiên liệu';
    final body = message.notification?.body ?? 'Có giá nhiên liệu mới.';
    appScaffoldMessengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text('$title\n$body'),
        duration: const Duration(seconds: 6),
        action: SnackBarAction(
          label: 'Xem',
          onPressed: () => _openMessage(message),
        ),
      ),
    );
  }

  void _openMessage(RemoteMessage message) {
    final fuelCode = message.data['fuelCode'];
    final region = message.data['region'];
    if (fuelCode is! String ||
        !RegExp(r'^[A-Z0-9_]{2,40}$').hasMatch(fuelCode) ||
        (region != 'REGION_1' && region != 'REGION_2')) {
      return;
    }
    router.go('/prices/$fuelCode?region=$region');
  }

  Future<void> _writeLocal(
    SharedPreferences local,
    PushNotificationPreferences preferences,
  ) async {
    await local.setBool(_enabledKey, preferences.enabled);
    await local.setStringList(
      _fuelCodesKey,
      preferences.fuelCodes.toList()..sort(),
    );
    await local.setString(_regionKey, preferences.region);
    await local.setString(_directionKey, preferences.direction);
  }

  _DeviceAuth? _readAuth(SharedPreferences local) {
    final installationId = local.getString(_installationIdKey);
    final credential = local.getString(_credentialKey);
    if (installationId == null || credential == null) return null;
    return _DeviceAuth(installationId, credential);
  }

  Options _authOptions(_DeviceAuth auth) =>
      Options(headers: {'x-installation-credential': auth.credential});

  String _newId() {
    const alphabet =
        'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final random = Random.secure();
    return List.generate(40, (_) => alphabet[random.nextInt(alphabet.length)])
        .join();
  }

  static const _installationIdKey = 'push.installationId';
  static const _credentialKey = 'push.installationCredential';
  static const _enabledKey = 'push.enabled';
  static const _fuelCodesKey = 'push.fuelCodes';
  static const _regionKey = 'push.region';
  static const _directionKey = 'push.direction';
  static const _pendingSyncKey = 'push.preferencesPendingSync';
}

class _DeviceAuth {
  const _DeviceAuth(this.installationId, this.credential);

  final String installationId;
  final String credential;
}

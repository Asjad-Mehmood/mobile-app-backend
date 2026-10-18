import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Compile-time default server, e.g. `flutter build apk --dart-define=API_URL=https://api.example.com`.
/// Android emulators reach the host machine at 10.0.2.2.
const String kDefaultApiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://10.0.2.2:8080');

/// Token in the platform keychain/keystore; everything else in shared preferences.
class AppStorage {
  AppStorage(this.prefs, {FlutterSecureStorage? secure}) : _secure = secure ?? const FlutterSecureStorage();

  final SharedPreferences prefs;
  final FlutterSecureStorage _secure;
  final String _tokenKey = 'auth_token';

  static Future<AppStorage> open() async => AppStorage(await SharedPreferences.getInstance());

  Future<String?> readToken() async {
    try {
      return await _secure.read(key: _tokenKey).timeout(const Duration(seconds: 4));
    } catch (_) {
      return prefs.getString('_$_tokenKey');
    }
  }

  Future<void> writeToken(String? token) async {
    try {
      if (token == null) {
        await prefs.remove('_$_tokenKey');
        await _secure.delete(key: _tokenKey).timeout(const Duration(seconds: 4));
      } else {
        await _secure.write(key: _tokenKey, value: token).timeout(const Duration(seconds: 4));
      }
    } catch (_) {
      // Keystore unavailable (rare emulator images) — fall back to prefs.
      if (token == null) {
        await prefs.remove('_$_tokenKey');
      } else {
        await prefs.setString('_$_tokenKey', token);
      }
    }
  }

  String get serverUrl => prefs.getString('server_url') ?? kDefaultApiUrl;
  Future<void> setServerUrl(String? url) async {
    if (url == null || url.trim().isEmpty || url.trim() == kDefaultApiUrl) {
      await prefs.remove('server_url');
    } else {
      await prefs.setString('server_url', url.trim());
    }
  }

  String? getString(String key) => prefs.getString(key);
  Future<void> setString(String key, String? value) => value == null ? prefs.remove(key) : prefs.setString(key, value);
  bool getBool(String key, [bool fallback = false]) => prefs.getBool(key) ?? fallback;
  Future<void> setBool(String key, bool value) => prefs.setBool(key, value);
}

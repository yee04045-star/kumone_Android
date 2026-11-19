import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class SecureStore {
  static const _key='kumone.cookies.v1';
  static const _storage=FlutterSecureStorage();
  static Future<Map<String,String>> readCookies() async {
    try { final raw=await _storage.read(key:_key); if(raw==null)return{}; return Map<String,String>.from(jsonDecode(raw)); } catch(_){ return{}; }
  }
  static Future<void> writeCookies(Map<String,String> cookies) async { await _storage.write(key:_key,value:jsonEncode(cookies)); }
  static Future<void> clearAuth() async { final c=await readCookies(); c.remove('MUSIC_U'); c.remove('__csrf'); await writeCookies(c); }
}

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart' as crypto;
import 'package:pointycastle/export.dart';

class NeteaseCrypto {
  static const _presetKey = '0CoJUm6Qyw8W8jud';
  static const _iv = '0102030405060708';
  static const _secretKey = 'kumone2026abcDEF';
  static const _encSecKey = '38cef2efdbcc1cfd6a44d81620dae5d23091f50ef27e01a1b1bb7e998e0fde2d7ab6002a9e79a3c195f661cbde80e21e6245997b11b54d28407115822f95d4477cc06b5a77de46fab6568410abf1229abef81b4c8588f386149010d190bb0b04f064be330bd877a4d4b99514febbdb4335b10744b13d9f7ee24d314d6e62cdc9';
  static const _eapiKey = 'e82ckenh8dichen8';

  static Map<String,String> weapi(Object payload) {
    final json = utf8.encode(jsonEncode(payload));
    final first = base64Encode(_aes(json, utf8.encode(_presetKey), iv:utf8.encode(_iv)));
    final second = base64Encode(_aes(utf8.encode(first), utf8.encode(_secretKey), iv:utf8.encode(_iv)));
    return {'params':second,'encSecKey':_encSecKey};
  }

  static Map<String,String> eapi(String apiPath,Object payload) {
    final text=jsonEncode(payload); final message='nobody${apiPath}use${text}md5forencrypt';
    final digest=crypto.md5.convert(utf8.encode(message)).toString();
    final data='$apiPath-36cd479b6b5-$text-36cd479b6b5-$digest';
    final encrypted=_aes(utf8.encode(data),utf8.encode(_eapiKey));
    return {'params':encrypted.map((b)=>b.toRadixString(16).padLeft(2,'0')).join().toUpperCase()};
  }

  static List<int> _aes(List<int> data,List<int> key,{List<int>? iv}) {
    final cipher = PaddedBlockCipherImpl(PKCS7Padding(), iv == null ? ECBBlockCipher(AESEngine()) : CBCBlockCipher(AESEngine()));
    if(iv == null) {
      cipher.init(true,PaddedBlockCipherParameters<KeyParameter,Null>(KeyParameter(Uint8List.fromList(key)),null));
    } else {
      cipher.init(true,PaddedBlockCipherParameters<ParametersWithIV<KeyParameter>,Null>(ParametersWithIV<KeyParameter>(KeyParameter(Uint8List.fromList(key)),Uint8List.fromList(iv)),null));
    }
    return cipher.process(Uint8List.fromList(data));
  }
}

import '../widgets/glass_category_chip.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../widgets/common.dart';
import '../../core/api/netease_api.dart';
import '../../core/api/netease_client.dart';
import '../../core/storage/account_store.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String? _key;
  int _qrCode = 0;
  String _phase = 'loading';
  Timer? _pollTimer;
  static const MethodChannel _qrNative = MethodChannel('im.kumone.netease/login');
  Timer? _smsTimer;
  final _phone = TextEditingController();
  final _captcha = TextEditingController();
  bool _sms = false;
  bool _sending = false;
  bool _logging = false;
  int _cooldown = 0;
  bool _polling = false;

  @override
  void initState() {
    super.initState();
    _startQr();
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _smsTimer?.cancel();
    _phone.dispose();
    _captcha.dispose();
    super.dispose();
  }

  Future<void> _startQr() async {
    _pollTimer?.cancel();
    if (mounted) {
      setState(() {
        _phase = 'loading';
        _key = null;
        _qrCode = 0;
      });
    }
    try {
      final key = await NeteaseApi.instance.qrKey();
      _key = key;
      if (!mounted) return;
      setState(() => _phase = 'waiting');
      // Keep the entire QR flow in the same authenticated Dio/cookie jar as
      // the iOS implementation. The native Android GET path is deliberately
      // not used because its 803 response can lose MUSIC_U/Set-Cookie.
      _pollTimer = Timer.periodic(
        const Duration(milliseconds: 1200),
        (_) => unawaited(_pollQr()),
      );
      unawaited(_pollQr());
    } catch (e) {
      if (mounted) setState(() => _phase = '失败：$e');
    }
  }

  Future<void> _pollQr() async {
    if (_polling) return;
    final key = _key;
    if (key == null) return;
    _polling = true;
    try {
      final result = await NeteaseApi.instance.qrCheck(key);
      if (!mounted) return;
      setState(() => _qrCode = result.code);
      switch (result.code) {
        case 800:
          _pollTimer?.cancel();
          setState(() => _phase = '二维码已过期');
          break;
        case 801:
          setState(() => _phase = 'waiting');
          break;
        case 802:
          setState(() => _phase = 'scanned');
          break;
        case 803:
          _pollTimer?.cancel();
          if (!mounted) return;
          setState(() => _phase = '授权成功，正在同步登录状态…');
          final account = context.read<AccountStore>();
          // iOS does not trust the QR response profile. It trusts the session
          // cookie captured from Set-Cookie and then calls userAccount().
          // Some Android/proxy stacks hide Set-Cookie on this exact response,
          // so perform one compatibility recovery before bootstrapping.
          if (!NeteaseClient.instance.isLoggedIn) {
            // Hybrid Android fallback: capture the raw 803 response cookies
            // through HttpURLConnection once. This is only a recovery path;
            // the normal QR state machine remains in Dart and mirrors iOS.
            try {
              final raw = await _qrNative.invokeMethod<dynamic>(
                'captureQrCookies',
                <String, dynamic>{
                  'key': key,
                  'cookies': NeteaseClient.instance.cookies,
                },
              );
              if (raw is Map && raw['cookies'] is Map) {
                final cookies = <String, String>{};
                (raw['cookies'] as Map).forEach((k, v) {
                  if (k != null && v != null) cookies['$k'] = '$v';
                });
                await NeteaseClient.instance.setCookies(cookies);
              }
            } catch (_) {
              // MissingPluginException is expected on non-Android builds.
            }
            if (!NeteaseClient.instance.isLoggedIn) {
              await NeteaseClient.instance.refreshQrCookies(key);
            }
          }
          final ok = await account.finishQrLogin(attempts: 6);
          if (!mounted) return;
          if (ok && account.isLoggedIn) {
            setState(() => _phase = 'success');
            Navigator.of(context).pop();
          } else {
            final cookie = NeteaseClient.instance.cookies['MUSIC_U'];
            final detail = account.lastError ??
                (cookie == null || cookie.isEmpty
                    ? '未捕获到 MUSIC_U Cookie'
                    : 'MUSIC_U 已捕获，但用户资料接口没有返回 profile');
            setState(() => _phase = '授权成功，但账号同步失败：$detail');
          }
          break;
      }
    } catch (e) {
      // 801/802/temporary network errors should not interrupt polling.
      if (mounted && _phase != 'waiting' && _phase != 'scanned') {
        setState(() => _phase = '连接二维码服务失败，正在重试…');
      }
    } finally {
      _polling = false;
    }
  }

  Future<void> _sendSms() async {
    final phone = _phone.text.trim();
    if (phone.length < 11 || _sending || _cooldown > 0) return;
    setState(() => _sending = true);
    try {
      await NeteaseApi.instance.sendSms(phone);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('验证码已发送')),
      );
      setState(() => _cooldown = 60);
      _smsTimer?.cancel();
      _smsTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
        if (!mounted || _cooldown <= 0) {
          timer.cancel();
          return;
        }
        setState(() => _cooldown--);
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _loginSms() async {
    if (_phone.text.trim().length < 11 || _captcha.text.trim().isEmpty) return;
    setState(() => _logging = true);
    final account = context.read<AccountStore>();
    try {
      await NeteaseApi.instance.loginCellphone(
        _phone.text.trim(),
        _captcha.text.trim(),
      );
      await account.bootstrap(force: true);
      if (mounted) {
        if (account.isLoggedIn) {
          Navigator.of(context).pop();
        } else {
          final detail = account.lastError ?? '服务器没有返回可用的账号信息';
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('登录成功，但账号资料读取失败：$detail')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$e')));
      }
    } finally {
      if (mounted) setState(() => _logging = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const KumoneGlassAppBar(title: Text('登录网易云音乐')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 430),
            child: Column(
              children: [
                const Icon(Icons.cloud_rounded, size: 54),
                const SizedBox(height: 12),
                const Text(
                  'Kumone',
                  style: TextStyle(fontSize: 30, fontWeight: FontWeight.w900),
                ),
                const SizedBox(height: 18),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  GlassCategoryChip(label: '扫码登录', selected: !_sms,
                    onTap: () => setState(() => _sms = false)),
                  const SizedBox(width: 10),
                  GlassCategoryChip(label: '手机号', selected: _sms,
                    onTap: () => setState(() => _sms = true)),
                ]),
                const SizedBox(height: 22),
                if (!_sms)
                  QrLoginPanel(
                    keyValue: _key,
                    code: _qrCode,
                    phase: _phase,
                    onRefresh: _startQr,
                  )
                else
                  SmsLoginPanel(
                    phone: _phone,
                    captcha: _captcha,
                    sending: _sending,
                    logging: _logging,
                    cooldown: _cooldown,
                    onSend: _sendSms,
                    onLogin: _loginSms,
                  ),
                const SizedBox(height: 20),
                Text(
                  '扫码登录通常更稳定；手机号登录可能受到网易云风控影响。',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class QrLoginPanel extends StatelessWidget {
  final String? keyValue;
  final int code;
  final String phase;
  final VoidCallback onRefresh;

  const QrLoginPanel({
    super.key,
    this.keyValue,
    required this.code,
    required this.phase,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    Widget body;
    if (keyValue == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Stack(
        alignment: Alignment.center,
        children: [
          QrImageView(
            data: NeteaseApi.instance.qrLoginUrl(keyValue!),
            size: 200,
          ),
          if (code == 802)
            Container(
              width: 200,
              height: 200,
              color: Colors.white.withValues(alpha: .84),
              alignment: Alignment.center,
              child: const Text(
                '已扫码\n等待确认',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
              ),
            ),
          if (code == 800)
            Container(
              width: 200,
              height: 200,
              color: Colors.white.withValues(alpha: .88),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text('二维码已过期'),
                  TextButton(onPressed: onRefresh, child: const Text('刷新二维码')),
                ],
              ),
            ),
        ],
      );
    }

    final label = switch (phase) {
      'waiting' => '打开网易云音乐 App 扫一扫',
      'scanned' => '等待手机确认…',
      'success' => '登录成功',
      _ => phase,
    };

    return Column(
      children: [
        Container(
          width: 230,
          height: 230,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
          ),
          child: body,
        ),
        const SizedBox(height: 16),
        Text(label),
      ],
    );
  }
}

class SmsLoginPanel extends StatelessWidget {
  final TextEditingController phone;
  final TextEditingController captcha;
  final bool sending;
  final bool logging;
  final int cooldown;
  final VoidCallback onSend;
  final VoidCallback onLogin;

  const SmsLoginPanel({
    super.key,
    required this.phone,
    required this.captcha,
    required this.sending,
    required this.logging,
    required this.cooldown,
    required this.onSend,
    required this.onLogin,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        TextField(
          controller: phone,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(
            prefixText: '+86  ',
            labelText: '手机号',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: captcha,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: '验证码',
            border: const OutlineInputBorder(),
            suffixIcon: TextButton(
              onPressed: sending || cooldown > 0 ? null : onSend,
              child: Text(
                sending
                    ? '发送中'
                    : cooldown > 0
                        ? '$cooldown s'
                        : '获取验证码',
              ),
            ),
          ),
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: logging ? null : onLogin,
            child: Text(logging ? '登录中…' : '登录'),
          ),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class FirstLaunchNotice {
  static const preferenceKey = 'learningNoticeAcknowledgedV1';
  static final _prefs = SharedPreferencesAsync();
  static Future<bool> get acknowledged async =>
      await _prefs.getBool(preferenceKey) ?? false;

  static Future<void> showIfNeeded(BuildContext context) async {
    if (await acknowledged || !context.mounted) return;
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (dialogContext) => const _NoticeDialog(),
    );
  }
}

class _NoticeDialog extends StatefulWidget {
  const _NoticeDialog();
  @override
  State<_NoticeDialog> createState() => _NoticeDialogState();
}

class _NoticeDialogState extends State<_NoticeDialog> {
  bool saving = false;
  String? error;
  @override
  Widget build(BuildContext context) => PopScope(
        canPop: false,
        child: AlertDialog(
          title: const Text('使用提示'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            const Text('本项目仅供学习交流使用，请在 24 小时内删除。\n\n'
                '本应用为非官方客户端，与音乐平台无隶属或授权关系。'
                '音乐、歌词与封面的权利归相应权利人所有，请仅使用你有权访问的内容。\n\n'
                '“学习交流”或“24 小时内删除”不构成免责或内容授权，也不限制适用开源许可证赋予的权利。'),
            if (error != null)
              Padding(
                  padding: const EdgeInsets.only(top: 12), child: Text(error!)),
          ]),
          actions: [
            TextButton(
                onPressed: saving
                    ? null
                    : () async {
                        setState(() {
                          saving = true;
                          error = null;
                        });
                        try {
                          await FirstLaunchNotice._prefs
                              .setBool(FirstLaunchNotice.preferenceKey, true);
                          if (context.mounted) Navigator.of(context).pop();
                        } catch (_) {
                          if (mounted) {
                            setState(() {
                              saving = false;
                              error = '无法保存确认状态，请重试';
                            });
                          }
                        }
                      },
                child: Text(saving ? '保存中…' : '确认'))
          ],
        ),
      );
}

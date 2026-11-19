import 'package:flutter/material.dart';
import '../../core/storage/custom_source_store.dart';
import '../widgets/common.dart';
import '../widgets/glass_controls.dart';

class SourceSettingsPage extends StatefulWidget {
  const SourceSettingsPage({super.key});
  @override
  State<SourceSettingsPage> createState() => _SourceSettingsPageState();
}

class _SourceSettingsPageState extends State<SourceSettingsPage> {
  final store = CustomSourceStore();
  bool busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    store.load();
  }

  @override
  void dispose() {
    store.dispose();
    super.dispose();
  }

  Future<void> change(Future<void> Function() action) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([CustomSource? source]) async {
    final name = TextEditingController(text: source?.name);
    final endpoint = TextEditingController(text: source?.endpoint);
    String? validation;
    try {
      final saved = await kumoneDialog<bool>(
          context: context,
          builder: (context) => StatefulBuilder(
                builder: (context, update) => AlertDialog(
                  title: Text(source == null ? '添加音源' : '编辑音源'),
                  content: SingleChildScrollView(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                    TextField(
                        controller: name,
                        decoration: const InputDecoration(labelText: '音源名称')),
                    TextField(
                        controller: endpoint,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        decoration:
                            const InputDecoration(labelText: 'HTTPS 解析接口地址')),
                    if (validation != null)
                      Text(validation!,
                          style: TextStyle(
                              color: Theme.of(context).colorScheme.error)),
                    const Padding(
                        padding: EdgeInsets.only(top: 12),
                        child:
                            Text('需使用兼容的 GET/JSON 解析服务，不是音乐平台网站地址。新增后默认关闭。')),
                  ])),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('取消')),
                    TextButton(
                        onPressed: () {
                          try {
                            CustomSourceStore.validate(
                                name.text, endpoint.text);
                            Navigator.pop(context, true);
                          } catch (e) {
                            update(() => validation = '$e');
                          }
                        },
                        child: const Text('保存'))
                  ],
                ),
              ));
      if (saved == true && mounted) {
        await change(() => store.put(
            id: source?.id,
            name: name.text,
            endpoint: endpoint.text,
            enabled: source?.enabled ?? false));
      }
    } finally {
      name.dispose();
      endpoint.dispose();
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        extendBodyBehindAppBar: true,
        appBar: const KumoneGlassAppBar(title: Text('音源配置')),
        body: ListenableBuilder(
            listenable: store,
            builder: (context, _) => ListView(
                  padding: EdgeInsets.fromLTRB(
                      16, kumoneToolbarInset(context) + 12, 16, 180),
                  children: [
                    const ListTile(
                        leading: Icon(Icons.verified_outlined),
                        title: Text('网易云官方音源'),
                        subtitle: Text('始终优先，不占自定义音源名额；付费权限以账号实际授权为准。')),
                    const ListTile(
                        title: Text('自定义音源'),
                        subtitle: Text(
                            '最多 7 个，无内置第三方服务。官方音源不可用时，按下列顺序尝试已启用音源，失败继续下一个。仅配置你有权使用的服务；歌曲信息将发送至该服务，不发送网易云登录凭据。')),
                    if (error != null)
                      Padding(
                          padding: const EdgeInsets.all(12),
                          child: Text(error!)),
                    for (var i = 0; i < store.sources.length; i++) ...[
                      KumoneGlassSwitchTile(
                          value: store.sources[i].enabled,
                          title: Text('${i + 1}. ${store.sources[i].name}'),
                          subtitle: Text(store.sources[i].endpoint,
                              maxLines: 2, overflow: TextOverflow.ellipsis),
                          onChanged: busy
                              ? null
                              : (value) {
                                  final source = store.sources[i];
                                  change(() => store.put(
                                      id: source.id,
                                      name: source.name,
                                      endpoint: source.endpoint,
                                      enabled: value));
                                }),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        IconButton(
                            tooltip: '上移',
                            icon: const Icon(Icons.arrow_upward),
                            onPressed: busy || i == 0
                                ? null
                                : () => change(() => store.move(i, -1))),
                        IconButton(
                            tooltip: '下移',
                            icon: const Icon(Icons.arrow_downward),
                            onPressed: busy || i == store.sources.length - 1
                                ? null
                                : () => change(() => store.move(i, 1))),
                        IconButton(
                            tooltip: '编辑',
                            icon: const Icon(Icons.edit_outlined),
                            onPressed:
                                busy ? null : () => edit(store.sources[i])),
                        IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: busy
                                ? null
                                : () async {
                                    final source = store.sources[i];
                                    final yes = await kumoneDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                                title: const Text('删除音源？'),
                                                content: Text(source.name),
                                                actions: [
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context),
                                                      child: const Text('取消')),
                                                  TextButton(
                                                      onPressed: () =>
                                                          Navigator.pop(
                                                              context, true),
                                                      child: const Text('删除'))
                                                ]));
                                    if (yes == true && mounted) {
                                      await change(
                                          () => store.remove(source.id));
                                    }
                                  }),
                      ]),
                      const Divider(),
                    ],
                    TextButton.icon(
                        onPressed: busy ||
                                store.sources.length >=
                                    CustomSourceStore.maxSources
                            ? null
                            : () => edit(),
                        icon: const Icon(Icons.add),
                        label: Text('添加音源（${store.sources.length}/7）')),
                    const ListTile(
                        subtitle: Text(
                            '接口协议：GET 查询参数 id、name、artist、album、durationMs。返回 JSON：{"url":"https://…","headers":{}}。headers 可选；仅支持 HTTPS 音频链接。不支持任意脚本或自动导入平台解析器。')),
                  ],
                )),
      );
}

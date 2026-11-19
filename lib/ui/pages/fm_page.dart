import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/api/netease_api.dart';
import '../../core/models/models.dart';
import '../../core/player/player_controller.dart';
import '../widgets/common.dart';
import '../widgets/liquid_surface.dart';

class FmPage extends StatefulWidget {
  const FmPage({super.key});

  @override
  State<FmPage> createState() => _FmPageState();
}

class _FmPageState extends State<FmPage> {
  List<Track> items = [];
  bool loading = true;
  bool working = false;
  String? error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final loaded = await NeteaseApi.instance.personalFm();
      items = loaded;
      error = loaded.isEmpty ? '私人漫游暂时没有歌曲' : null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => loading = false);
  }

  Future<void> _playCurrent() async {
    if (items.isEmpty || working) return;
    final player = context.read<PlayerController>();
    setState(() => working = true);
    try {
      await player.playTracks(items, index: 0);
    } catch (e) {
      error = '播放失败：$e';
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> _next() async {
    if (items.isEmpty || working) return;
    final playerController = context.read<PlayerController>();
    setState(() => working = true);
    try {
      await NeteaseApi.instance.fmTrash(items.first.id);
      final loaded = await NeteaseApi.instance.personalFm();
      items = loaded;
      if (items.isNotEmpty) {
        await playerController.playTracks(items, index: 0);
      }
      error = items.isEmpty ? '私人漫游暂时没有下一首' : null;
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => working = false);
  }

  Future<void> _trashCurrent() async {
    if (items.isEmpty || working) return;
    final playerController = context.read<PlayerController>();
    setState(() => working = true);
    try {
      await NeteaseApi.instance.fmTrash(items.first.id);
      items.removeAt(0);
      if (items.isNotEmpty) {
        await playerController.playTracks(items, index: 0);
      }
    } catch (e) {
      error = '$e';
    }
    if (mounted) setState(() => working = false);
  }

  @override
  Widget build(BuildContext context) {
    final player = context.watch<PlayerController>();
    if (loading) return const Center(child: CircularProgressIndicator());
    if (items.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(error ?? '私人漫游暂时不可用'),
            const SizedBox(height: 12),
            KumoneLiquidSurface(
                radius: 24,
                child: TextButton.icon(
                    onPressed: _load,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('重新加载'))),
          ],
        ),
      );
    }

    final track = items.first;
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Artwork(url: track.album.picUrl, size: 280, radius: 24),
              const SizedBox(height: 24),
              Text(
                track.name,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                track.artistNames,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    onPressed: working ? null : _trashCurrent,
                    icon: const Icon(Icons.thumb_down_outlined),
                  ),
                  const SizedBox(width: 20),
                  FilledButton(
                    onPressed: working ? null : _playCurrent,
                    child: working
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : Icon(
                            player.isPlaying ? Icons.pause : Icons.play_arrow,
                          ),
                  ),
                  const SizedBox(width: 20),
                  IconButton(
                    onPressed: working ? null : _next,
                    icon: const Icon(Icons.skip_next_rounded),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

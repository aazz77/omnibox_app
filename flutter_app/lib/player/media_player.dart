// 播放器默认占位实现（无 media_kit 依赖，保证 Flutter 3.0 环境可编译）。
//
// 【启用真正的 media_kit 播放器】
// 1) Flutter >= 3.7，pubspec.yaml 取消 media_kit / media_kit_video 注释并 pub get；
// 2) 把 detail.dart 的 import 从
//      import '../player/media_player.dart';
//    改为
//      import '../player/media_player_mpv.dart';
// 两个文件都导出同名 MpvPlayer，接口一致，切换只需改这一行。
import 'package:flutter/material.dart';

class MpvPlayer extends StatelessWidget {
  final String url;
  final Map<String, dynamic> headers;
  final VoidCallback? onError;
  MpvPlayer({required this.url, required this.headers, this.onError, Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.play_circle_outline, size: 56, color: Colors.grey),
        const SizedBox(height: 8),
        const Text('播放器占位：启用 media_kit 后播放'),
        const SizedBox(height: 4),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(url, maxLines: 2, overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 11, color: Colors.grey)),
        ),
      ]),
    );
  }
}

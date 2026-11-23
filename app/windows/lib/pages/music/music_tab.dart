import 'package:flutter/material.dart';
import '../../music/global_player.dart';
import '../../music/music_api.dart';
import 'music_home.dart';
import 'music_list.dart';
import 'music_player_page.dart';

/// 音乐模块导航根：持有音乐首页，榜单/搜索/播放页用 Navigator push。
/// 全局播放器跨页面持续播放；底部显示迷你播放条可回到播放页。
class MusicTabPage extends StatefulWidget {
  const MusicTabPage({Key? key}) : super(key: key);
  @override
  State<MusicTabPage> createState() => _MusicTabPageState();
}

class _MusicTabPageState extends State<MusicTabPage> {
  final GlobalKey<NavigatorState> _navKey = GlobalKey<NavigatorState>();

  void _openBoard(MusicBoard board) {
    _navKey.currentState!.push(MaterialPageRoute(builder: (_) => MusicListPage(
      title: board.name,
      source: board.source,
      bangid: board.bangid,
      onPlay: _onPlay,
    )));
  }

  void _openSearch(String keyword) {
    _navKey.currentState!.push(MaterialPageRoute(builder: (_) => MusicListPage(
      title: '搜索: $keyword',
      source: 'kw',
      keyword: keyword,
      onPlay: _onPlay,
    )));
  }

  Future<void> _onPlay(MusicSong song, List<MusicSong> queue, int index) async {
    await GlobalMusicPlayer.i.playSongs(queue, index);
    if (!mounted) return;
    _navKey.currentState!.push(MaterialPageRoute(builder: (_) => const MusicPlayerPage()));
  }

  void _openPlayer() {
    if (GlobalMusicPlayer.i.current == null) return;
    _navKey.currentState!.push(MaterialPageRoute(builder: (_) => const MusicPlayerPage()));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        Expanded(child: Navigator(
          key: _navKey,
          onGenerateRoute: (_) => MaterialPageRoute(
            builder: (_) => MusicHomePage(onOpenBoard: _openBoard, onSearch: _openSearch),
          ),
        )),
        _MiniBar(onTap: _openPlayer),
      ]),
    );
  }
}

/// 底部迷你播放条（当前曲目 + 播放/暂停，点击进播放页）
class _MiniBar extends StatelessWidget {
  final VoidCallback onTap;
  const _MiniBar({required this.onTap});
  @override
  Widget build(BuildContext context) {
    final p = GlobalMusicPlayer.i;
    return ValueListenableBuilder<int>(
      valueListenable: p.currentIndex,
      builder: (context, idx, _) {
        final song = p.currentSong;
        if (song == null) return const SizedBox.shrink();
        return Container(
          height: 60,
          decoration: BoxDecoration(
            color: Colors.indigo.shade50,
            border: Border(top: BorderSide(color: Colors.indigo.shade100)),
          ),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.indigo,
              child: const Icon(Icons.music_note, color: Colors.white, size: 18),
            ),
            title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
            subtitle: Text(song.singer, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11)),
            trailing: ValueListenableBuilder<bool>(
              valueListenable: p.playing,
              builder: (context, playing, _) => Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(icon: Icon(playing ? Icons.pause : Icons.play_arrow), onPressed: p.playPause),
                IconButton(icon: const Icon(Icons.skip_next), onPressed: p.next),
                IconButton(icon: const Icon(Icons.open_in_full, size: 18), onPressed: onTap),
              ]),
            ),
            onTap: onTap,
          ),
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import '../../music/music_api.dart';
import '../../app_core.dart';
import 'mv_player_page.dart';

/// 通用歌曲列表页：既可展示排行榜榜内歌曲，也可展示搜索结果。
class MusicListPage extends StatefulWidget {
  final String title;
  final String source;
  final String? bangid;       // 非空=榜单模式
  final String? keyword;      // 非空=搜索模式
  final Function(MusicSong song, List<MusicSong> queue, int index) onPlay;
  const MusicListPage({
    required this.title,
    required this.onPlay,
    this.source = 'kw',
    this.bangid,
    this.keyword,
    Key? key,
  }) : super(key: key);

  @override
  State<MusicListPage> createState() => _MusicListPageState();
}

class _MusicListPageState extends State<MusicListPage> {
  final List<MusicSong> _songs = [];
  int _page = 1;
  bool _loading = true;
  bool _loadingMore = false;
  String? _error;
  bool _hasMore = true;
  final ScrollController _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _load(1);
  }

  Future<void> _load(int page) async {
    setState(() { if (page == 1) { _loading = true; _error = null; } else { _loadingMore = true; } });
    try {
      final list = widget.bangid != null
          ? await MusicApi.boardList(widget.bangid!, source: widget.source, page: page)
          : await MusicApi.search(widget.keyword ?? '', source: widget.source, page: page);
      if (!mounted) return;
      setState(() {
        if (page == 1) _songs.clear();
        _songs.addAll(list);
        _page = page;
        _hasMore = list.isNotEmpty;
        _loading = false;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _loading = false; _loadingMore = false; });
    }
  }

  void _onScroll() {
    if (_scroll.position.pixels >= _scroll.position.maxScrollExtent - 200 && !_loadingMore && _hasMore) {
      _load(_page + 1);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), leading: IconButton(
        icon: const Icon(Icons.arrow_back),
        onPressed: () => Navigator.of(context).pop(),
      )),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null && _songs.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.error_outline, size: 40, color: Colors.grey.shade400),
                  const SizedBox(height: 8),
                  Text('加载失败: $_error', textAlign: TextAlign.center),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: () => _load(1), child: const Text('重试')),
                ]))
              : ListView.builder(
                  controller: _scroll,
                  itemCount: _songs.length + (_hasMore ? 1 : 0),
                  itemBuilder: (context, i) {
                    if (i >= _songs.length) {
                      return const Padding(
                        padding: EdgeInsets.all(16),
                        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    }
                    final song = _songs[i];
                    return ListTile(
                      leading: SizedBox(
                        width: 44,
                        height: 44,
                        child: song.picUrl.startsWith('http')
                            ? ClipRRect(borderRadius: BorderRadius.circular(4), child: NetImage(song.picUrl, width: 44, height: 44))
                            : Container(
                                color: Colors.indigo.shade100,
                                child: Center(child: Text('${i + 1}', style: TextStyle(color: Colors.indigo.shade700, fontWeight: FontWeight.bold))),
                              ),
                      ),
                      title: Text(song.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text('${song.singer}${song.albumName.isNotEmpty ? ' · ${song.albumName}' : ''}${song.interval.isNotEmpty ? '  ${song.interval}' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // 仅网易云/酷狗显示 MV 入口（进入后自动补全 mv id 并播放）
                          if (song.mvSupported)
                            IconButton(
                              icon: const Icon(Icons.music_video, color: Colors.purple),
                              tooltip: '播放MV',
                              onPressed: () => MvPlayerPage.open(context, song),
                            ),
                          IconButton(
                            icon: const Icon(Icons.play_circle_outline, color: Colors.indigo),
                            onPressed: () => widget.onPlay(song, List.unmodifiable(_songs), i),
                          ),
                        ],
                      ),
                      onTap: () => widget.onPlay(song, List.unmodifiable(_songs), i),
                    );
                  },
                ),
    );
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }
}

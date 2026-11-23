import 'package:flutter/material.dart';
import '../app_core.dart';
import 'detail.dart';

/// 播放历史页
class HistoryPage extends StatefulWidget {
  const HistoryPage({Key? key}) : super(key: key);
  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> with AutomaticKeepAliveClientMixin {
  List<dynamic> _list = [];
  bool _loading = true;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Api.i.call('history_list');
    if (!mounted) return;
    setState(() { _list = r['list'] as List? ?? []; _loading = false; });
  }

  Future<void> _remove(String key) async {
    await Api.i.call('history_remove', {'key': key});
    _load();
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('清空历史'),
        content: const Text('确定清空全部播放历史？'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('确定')),
        ],
      ),
    );
    if (ok == true) {
      await Api.i.call('history_clear');
      _load();
    }
  }

  void _resume(Map<String, dynamic> item) {
    final vod = Vod(
      id: (item['vod_id'] ?? '').toString(),
      name: (item['name'] ?? '未知').toString(),
      pic: (item['pic'] ?? '').toString(),
      source: (item['src'] ?? '').toString(),
    );
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => DetailPage(vod: vod)));
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('播放历史'),
        actions: [
          if (_list.isNotEmpty)
            IconButton(icon: const Icon(Icons.delete_sweep), onPressed: _clear, tooltip: '清空'),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.history, size: 48, color: Colors.grey),
                  SizedBox(height: 12),
                  Text('暂无播放历史'),
                ]))
              : ListView.builder(
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final item = _list[i] as Map<String, dynamic>;
                    final key = (item['key'] ?? '').toString();
                    final epName = (item['ep_name'] ?? '').toString();
                    return ListTile(
                      leading: ClipRRect(borderRadius: BorderRadius.circular(4), child: NetImage((item['pic'] ?? '').toString(), width: 56, height: 80)),
                      title: Text((item['name'] ?? '未知').toString(), maxLines: 2),
                      subtitle: Text('${item['src']} ${epName.isNotEmpty ? '· $epName' : ''}'),
                      trailing: IconButton(icon: const Icon(Icons.close), onPressed: () => _remove(key)),
                      onTap: () => _resume(item),
                    );
                  },
                ),
    );
  }
}

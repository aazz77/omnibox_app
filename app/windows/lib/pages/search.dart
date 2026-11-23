import 'package:flutter/material.dart';
import '../app_core.dart';
import 'detail.dart';

/// 搜索页：关键词 + 来源 chips + 结果列表
class SearchPage extends StatefulWidget {
  final String initialQuery;
  SearchPage({this.initialQuery = '', Key? key}) : super(key: key);
  @override
  State<SearchPage> createState() => _SearchPageState();
}

class _SearchPageState extends State<SearchPage> {
  final TextEditingController _kw = TextEditingController();
  List<dynamic> _sources = [];
  String _src = 'all';
  List<Vod> _results = [];
  bool _loading = false;
  String? _error;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _kw.text = widget.initialQuery;
    _loadSources();
    if (widget.initialQuery.isNotEmpty) _doSearch();
  }

  Future<void> _loadSources() async {
    final r = await Api.i.call('spiders_list');
    if (!mounted) return;
    setState(() => _sources = r['list'] as List? ?? []);
  }

  Future<void> _doSearch({int page = 1}) async {
    final kw = _kw.text.trim();
    if (kw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('请输入关键词')));
      return;
    }
    setState(() { _loading = true; _error = null; _page = page; });
    final r = await Api.i.call('search', {'src': _src, 'wd': kw, 'page': page});
    if (!mounted) return;
    if (r['ok'] == true) {
      final list = r['list'] as List? ?? [];
      setState(() {
        _results = list.whereType<Map<String, dynamic>>().map(Vod.fromJson).toList();
        _loading = false;
      });
    } else {
      setState(() { _error = r['error']?.toString(); _loading = false; });
    }
  }

  void _openDetail(Vod v) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DetailPage(vod: v),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('搜索影视')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(children: [
              Expanded(
                child: TextField(
                  controller: _kw,
                  decoration: const InputDecoration(
                    hintText: '输入片名',
                    border: OutlineInputBorder(),
                    contentPadding: EdgeInsets.symmetric(horizontal: 12),
                  ),
                  onSubmitted: (_) => _doSearch(),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton(onPressed: () => _doSearch(), child: const Text('搜索')),
            ]),
          ),
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              children: [
                SourceChip('全部', selected: _src == 'all', onTap: () => setState(() => _src = 'all')),
                const SizedBox(width: 8),
                ..._sources.whereType<Map<String, dynamic>>().map((s) {
                  final id = (s['id'] ?? '').toString();
                  final name = (s['display_name'] ?? s['name'] ?? id).toString();
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SourceChip(name, selected: _src == id, onTap: () => setState(() => _src = id)),
                  );
                }),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(child: _buildResult()),
        ],
      ),
    );
  }

  Widget _buildResult() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(_error!, textAlign: TextAlign.center, style: const TextStyle(color: Colors.orange)),
    ));
    if (_results.isEmpty) {
      return Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [
        Icon(Icons.search_off, size: 48, color: Colors.grey),
        SizedBox(height: 12),
        Text('输入关键词搜索影视'),
      ]));
    }
    return ListView.builder(
      itemCount: _results.length + 1,
      itemBuilder: (_, i) {
        if (i == _results.length) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(child: ElevatedButton.icon(
              onPressed: () => _doSearch(page: _page + 1),
              icon: const Icon(Icons.expand_more),
              label: const Text('下一页'),
            )),
          );
        }
        final v = _results[i];
        return ListTile(
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: NetImage(v.pic, width: 56, height: 80),
          ),
          title: Text(v.name, maxLines: 2),
          subtitle: Text('${v.source} ${v.remarks}', maxLines: 1, overflow: TextOverflow.ellipsis),
          onTap: () => _openDetail(v),
        );
      },
    );
  }
}

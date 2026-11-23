import 'package:flutter/material.dart';
import '../app_core.dart';
import 'file_picker_service.dart';
import 'music/music_sources_page.dart';

/// 源管理页：顶部切换「点播源 / 音源」。
/// - 点播源：影视点播 QuickJS 脚本（spiders_*）
/// - 音源：音乐播放链接解析脚本（music_source_*，对齐 lx-server 契约）
class SpidersPage extends StatefulWidget {
  const SpidersPage({Key? key}) : super(key: key);
  @override
  State<SpidersPage> createState() => _SpidersPageState();
}

class _SpidersPageState extends State<SpidersPage>
    with AutomaticKeepAliveClientMixin, SingleTickerProviderStateMixin {
  @override
  bool get wantKeepAlive => true;

  late final TabController _tab = TabController(length: 2, vsync: this);

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        bottom: TabBar(
          controller: _tab,
          tabs: const [
            Tab(icon: Icon(Icons.movie_outlined), text: '点播源'),
            Tab(icon: Icon(Icons.audiotrack_outlined), text: '音源'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tab,
        children: const [
          VodSourcesPane(),
          MusicSourcesPane(),
        ],
      ),
    );
  }
}

/// 点播源面板：影视脚本（粘贴 / 本地文件 / URL），启停 / 测试 / 源码 / 删除。
class VodSourcesPane extends StatefulWidget {
  const VodSourcesPane({Key? key}) : super(key: key);
  @override
  State<VodSourcesPane> createState() => _VodSourcesPaneState();
}

class _VodSourcesPaneState extends State<VodSourcesPane>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  List<dynamic> _list = [];
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final r = await Api.i.call('spiders_list');
    if (!mounted) return;
    setState(() { _list = r['list'] as List? ?? []; _loading = false; });
  }

  /// 粘贴源码导入
  Future<void> _addPasted(String name, String source) async {
    if (source.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('源码不能为空')));
      return;
    }
    setState(() => _busy = true);
    final r = await Api.i.call('spiders_add', {
      'name': name.isEmpty ? 'pasted.js' : name,
      'source': source,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['ok'] == true ? '导入成功: ${r['spider']?['id']}' : '导入失败: ${r['error']}'),
    ));
    if (r['ok'] == true) _load();
  }

  /// 从本地文件导入（系统文件对话框选 .js）
  Future<void> _addFromFile() async {
    final picked = await pickJsFile();
    if (picked == null) return; // 用户取消
    final name = picked['name'] ?? 'spider.js';
    final source = picked['source'] ?? '';
    await _addPasted(name, source);
  }

  /// 从 URL 远程拉取脚本
  Future<void> _addFromUrl(String url) async {
    if (url.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('URL 不能为空')));
      return;
    }
    setState(() => _busy = true);
    final r = await Api.i.call('spiders_add_url', {'url': url.trim()});
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['ok'] == true
          ? '拉取成功: ${r['spider']?['id']}'
          : '拉取失败: ${r['error']}'),
    ));
    if (r['ok'] == true) _load();
  }

  void _showUrlSheet() {
    final urlC = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('URL 远程拉取', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: urlC, decoration: const InputDecoration(
              labelText: '脚本 URL（http/https）',
              hintText: 'https://example.com/spider.js',
              border: OutlineInputBorder(),
            )),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _addFromUrl(urlC.text.trim());
              },
              child: const Text('拉取并导入'),
            )),
          ],
        )),
      ),
    );
  }

  /// 三种导入方式的选择菜单
  void _showImportMenu() {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
        const ListTile(title: Text('导入点播源'), leading: Icon(Icons.input)),
        ListTile(
          leading: const Icon(Icons.upload_file),
          title: const Text('从本地文件导入'),
          subtitle: const Text('选择 .js 文件'),
          onTap: () { Navigator.pop(ctx); _addFromFile(); },
        ),
        ListTile(
          leading: const Icon(Icons.link),
          title: const Text('URL 远程拉取'),
          subtitle: const Text('输入脚本地址下载'),
          onTap: () { Navigator.pop(ctx); _showUrlSheet(); },
        ),
        ListTile(
          leading: const Icon(Icons.content_paste),
          title: const Text('粘贴源码'),
          subtitle: const Text('手动粘贴 JS 代码'),
          onTap: () { Navigator.pop(ctx); _showAddSheet(); },
        ),
      ])),
    );
  }

  void _showAddSheet() {
    final nameC = TextEditingController(text: 'spider.js');
    final srcC = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('导入点播源脚本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: nameC, decoration: const InputDecoration(labelText: '文件名', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: srcC, maxLines: 8, decoration: const InputDecoration(
              labelText: 'JS 源码（OmniBox 格式：module.exports = {home,category,search,detail,play}）',
              border: OutlineInputBorder(),
            )),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _addPasted(nameC.text.trim(), srcC.text);
              },
              child: const Text('导入'),
            )),
          ],
        )),
      ),
    );
  }

  Future<void> _toggle(Map<String, dynamic> s) async {
    await Api.i.call('spiders_toggle', {'id': s['id'], 'enabled': !(s['enabled'] == true)});
    _load();
  }

  Future<void> _test(Map<String, dynamic> s) async {
    setState(() => _busy = true);
    final r = await Api.i.call('spiders_test', {'id': s['id'], 'kw': '测试'});
    if (!mounted) return;
    setState(() => _busy = false);
    final result = r['result'];
    int count = 0;
    if (result is Map && result['list'] is List) count = (result['list'] as List).length;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['ok'] == true ? '测试成功: $count 条结果' : '测试失败: ${r['error']}'),
    ));
    _load();
  }

  Future<void> _remove(Map<String, dynamic> s) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('删除 ${s['display_name'] ?? s['name']}?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
        ],
      ),
    );
    if (ok == true) {
      await Api.i.call('spiders_remove', {'id': s['id']});
      _load();
    }
  }

  Future<void> _viewSource(Map<String, dynamic> s) async {
    final r = await Api.i.call('spiders_source', {'id': s['id']});
    if (!mounted) return;
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text((s['display_name'] ?? s['name'] ?? '源码').toString()),
        content: SizedBox(
          width: double.maxFinite,
          height: 400,
          child: SingleChildScrollView(child: SelectableText((r['source'] ?? '').toString())),
        ),
        actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Stack(children: [
      _loading
          ? const Center(child: CircularProgressIndicator())
          : _list.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.movie_outlined, size: 48, color: Colors.grey),
                  const SizedBox(height: 12),
                  const Text('尚未导入点播源'),
                  const SizedBox(height: 8),
                  const Text('点右下角 + 导入（文件 / URL / 粘贴）', style: TextStyle(color: Colors.grey, fontSize: 12)),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 80),
                  itemCount: _list.length,
                  itemBuilder: (_, i) {
                    final s = _list[i] as Map<String, dynamic>;
                    final enabled = s['enabled'] == true;
                    final lastErr = s['last_error'];
                    return Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Row(children: [
                            Expanded(child: Text(
                              (s['display_name'] ?? s['name'] ?? s['id']).toString(),
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            )),
                            Chip(label: const Text('QuickJS'), backgroundColor: Colors.green.shade50),
                            Chip(label: Text(enabled ? '启用' : '禁用'),
                                backgroundColor: enabled ? Colors.green.shade50 : Colors.grey.shade200),
                          ]),
                          const SizedBox(height: 4),
                          Text('id: ${s['id']} · 来源: ${s['origin']}', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          if (lastErr != null)
                            Text('错误: $lastErr', style: const TextStyle(fontSize: 12, color: Colors.orange)),
                          const SizedBox(height: 8),
                          Wrap(spacing: 6, children: [
                            SmallBtn(label: enabled ? '禁用' : '启用', onTap: () => _toggle(s)),
                            SmallBtn(label: '测试', onTap: () => _test(s)),
                            SmallBtn(label: '源码', onTap: () => _viewSource(s)),
                            SmallBtn(label: '删除', onTap: () => _remove(s), danger: true),
                          ]),
                        ]),
                      ),
                    );
                  },
                ),
      Positioned(
        right: 16,
        bottom: 16,
        child: FloatingActionButton(
          onPressed: _showImportMenu,
          tooltip: '导入点播源',
          child: const Icon(Icons.add),
        ),
      ),
      if (_busy) const Center(child: CircularProgressIndicator()),
    ]);
  }
}

class SmallBtn extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final bool danger;
  SmallBtn({required this.label, required this.onTap, this.danger = false});
  @override
  Widget build(BuildContext context) => OutlinedButton(
        onPressed: onTap,
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 30),
        ),
        child: Text(label, style: TextStyle(fontSize: 12, color: danger ? Colors.red : null)),
      );
}

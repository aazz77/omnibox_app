import 'package:flutter/material.dart';
import '../app_core.dart';

/// 源管理页：导入脚本（粘贴源码）、列表（启停/切换引擎/测试/删除）
class SpidersPage extends StatefulWidget {
  const SpidersPage({Key? key}) : super(key: key);
  @override
  State<SpidersPage> createState() => _SpidersPageState();
}

class _SpidersPageState extends State<SpidersPage> with AutomaticKeepAliveClientMixin {
  List<dynamic> _list = [];
  bool _loading = true;
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

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
  Future<void> _addPasted(String name, String source, String runtime) async {
    if (source.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('源码不能为空')));
      return;
    }
    setState(() => _busy = true);
    final r = await Api.i.call('spiders_add', {
      'name': name.isEmpty ? 'pasted.js' : name,
      'source': source,
      'runtime': runtime,
    });
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(r['ok'] == true ? '导入成功: ${r['spider']?['id']}' : '导入失败: ${r['error']}'),
    ));
    if (r['ok'] == true) _load();
  }

  void _showAddSheet() {
    final nameC = TextEditingController(text: 'spider.js');
    final srcC = TextEditingController();
    String runtime = 'quickjs';
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => StatefulBuilder(builder: (ctx, setS) => Padding(
        padding: EdgeInsets.only(left: 16, right: 16, top: 16, bottom: MediaQuery.of(ctx).viewInsets.bottom + 16),
        child: SingleChildScrollView(child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('导入脚本', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            TextField(controller: nameC, decoration: const InputDecoration(labelText: '文件名', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            TextField(controller: srcC, maxLines: 8, decoration: const InputDecoration(
              labelText: '粘贴 JS 源码（OmniBox 格式：module.exports = {home,category,search,detail,play}）',
              border: OutlineInputBorder(),
            )),
            const SizedBox(height: 10),
            Row(children: [
              const Text('运行时: '),
              ChoiceChip(label: const Text('QuickJS'), selected: runtime == 'quickjs', onSelected: (_) => setS(() => runtime = 'quickjs')),
              const SizedBox(width: 8),
              ChoiceChip(label: const Text('Node.js'), selected: runtime == 'node', onSelected: (_) => setS(() => runtime = 'node')),
            ]),
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                _addPasted(nameC.text.trim(), srcC.text, runtime);
              },
              child: const Text('导入'),
            )),
          ],
        )),
      )),
    );
  }

  Future<void> _toggle(Map<String, dynamic> s) async {
    await Api.i.call('spiders_toggle', {'id': s['id'], 'enabled': !(s['enabled'] == true)});
    _load();
  }

  Future<void> _setRuntime(Map<String, dynamic> s, String rt) async {
    // Rust dispatch 里 runtime 切换方法名为 spiders_set_runtime
    await Api.i.call('spiders_set_runtime', {'id': s['id'], 'value': rt});
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('源管理'),
        actions: [IconButton(icon: const Icon(Icons.add), onPressed: _showAddSheet, tooltip: '导入脚本')],
      ),
      floatingActionButton: FloatingActionButton(onPressed: _showAddSheet, child: const Icon(Icons.add)),
      body: Stack(children: [
        _loading
            ? const Center(child: CircularProgressIndicator())
            : _list.isEmpty
                ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.source, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text('尚未导入影视脚本'),
                    SizedBox(height: 8),
                    Text('点右下角 + 粘贴 OmniBox 脚本', style: TextStyle(color: Colors.grey, fontSize: 12)),
                  ]))
                : ListView.builder(
                    itemCount: _list.length,
                    itemBuilder: (_, i) {
                      final s = _list[i] as Map<String, dynamic>;
                      final rt = (s['runtime'] ?? 'quickjs').toString();
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
                              Chip(label: Text(rt == 'node' ? 'Node' : 'QuickJS'),
                                  backgroundColor: rt == 'node' ? Colors.blue.shade50 : Colors.green.shade50),
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
                              SmallBtn(label: rt == 'node' ? '→QuickJS' : '→Node', onTap: () => _setRuntime(s, rt == 'node' ? 'quickjs' : 'node')),
                              SmallBtn(label: '删除', onTap: () => _remove(s), danger: true),
                            ]),
                          ]),
                        ),
                      );
                    },
                  ),
        if (_busy) const Center(child: CircularProgressIndicator()),
      ]),
    );
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
          foregroundColor: danger ? Colors.red : null,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          minimumSize: const Size(0, 30),
        ),
        child: Text(label, style: const TextStyle(fontSize: 12)),
      );
}

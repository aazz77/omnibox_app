import 'package:flutter/material.dart';
import '../../music/music_api.dart';

/// 音乐音源管理页：网络 URL / 本地粘贴导入，单活动源启用，删除，查看源码。
class MusicSourcesPage extends StatefulWidget {
  const MusicSourcesPage({Key? key}) : super(key: key);
  @override
  State<MusicSourcesPage> createState() => _MusicSourcesPageState();
}

class _MusicSourcesPageState extends State<MusicSourcesPage> {
  List<MusicSource> _sources = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await MusicApi.sources();
      if (mounted) setState(() { _sources = list; _loading = false; });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showImport() {
    showDialog(context: context, builder: (_) => _ImportDialog(onDone: _load));
  }

  Future<void> _toggle(MusicSource s, bool on) async {
    final r = await MusicApi.toggleSource(s.id, on);
    if (r['ok'] == true && mounted) _load();
  }

  Future<void> _remove(MusicSource s) async {
    final confirm = await showDialog<bool>(context: context, builder: (_) => AlertDialog(
      title: const Text('删除音源'),
      content: Text('确定删除「${s.name}」吗？'),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('取消')),
        TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('删除')),
      ],
    ));
    if (confirm == true) {
      await MusicApi.removeSource(s.id);
      _load();
    }
  }

  Future<void> _viewSource(MusicSource s) async {
    final text = await MusicApi.sourceContent(s.id);
    if (!mounted) return;
    showDialog(context: context, builder: (_) => AlertDialog(
      title: Text(s.name),
      content: SizedBox(
        width: 700, height: 500,
        child: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 11))),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('关闭'))],
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('音乐音源管理'),
        actions: [IconButton(icon: const Icon(Icons.add), tooltip: '导入音源', onPressed: _showImport)],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showImport,
        icon: const Icon(Icons.add),
        label: const Text('导入音源'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _sources.isEmpty
              ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.music_off, size: 56, color: Colors.grey.shade300),
                  const SizedBox(height: 12),
                  const Text('尚未导入音源'),
                  const SizedBox(height: 4),
                  const Text('导入并启用音源后才能获取播放链接', style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 16),
                  FilledButton.icon(onPressed: _showImport, icon: const Icon(Icons.add), label: const Text('导入音源')),
                ]))
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _sources.length,
                  itemBuilder: (context, i) {
                    final s = _sources[i];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          backgroundColor: s.enabled ? Colors.indigo : Colors.grey.shade300,
                          child: Icon(Icons.audiotrack, color: s.enabled ? Colors.white : Colors.grey.shade600),
                        ),
                        title: Row(children: [
                          Expanded(child: Text(s.name, maxLines: 1, overflow: TextOverflow.ellipsis)),
                          if (s.enabled) const Chip(label: Text('已启用'), visualDensity: VisualDensity.compact),
                        ]),
                        subtitle: Text(
                          '${s.author.isNotEmpty ? '作者: ${s.author}  ' : ''}${s.version.isNotEmpty ? 'v${s.version}  ' : ''}${s.sources.isNotEmpty ? '平台: ${s.sources.join(",")}' : '全平台'}',
                          maxLines: 1, overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (action) {
                            if (action == 'toggle') _toggle(s, !s.enabled);
                            else if (action == 'view') _viewSource(s);
                            else if (action == 'remove') _remove(s);
                          },
                          itemBuilder: (_) => [
                            PopupMenuItem(value: 'toggle', child: Text(s.enabled ? '停用' : '启用')),
                            const PopupMenuItem(value: 'view', child: Text('查看源码')),
                            const PopupMenuItem(value: 'remove', child: Text('删除')),
                          ],
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}

class _ImportDialog extends StatefulWidget {
  final VoidCallback onDone;
  const _ImportDialog({required this.onDone});
  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final TextEditingController _urlCtrl = TextEditingController();
  final TextEditingController _scriptCtrl = TextEditingController();
  bool _busy = false;
  String? _error;

  Future<void> _importUrl() async {
    final url = _urlCtrl.text.trim();
    if (!url.startsWith('http')) { setState(() => _error = '请输入 http(s) 开头的 URL'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await MusicApi.importSourceUrl(url, enable: true);
      if (r['ok'] != true) throw Exception((r['error'] ?? '导入失败').toString());
      if (mounted) { Navigator.pop(context); widget.onDone(); }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  Future<void> _importScript() async {
    final script = _scriptCtrl.text.trim();
    if (script.isEmpty) { setState(() => _error = '源码不能为空'); return; }
    setState(() { _busy = true; _error = null; });
    try {
      final r = await MusicApi.addSource(script, enable: true);
      if (r['ok'] != true) throw Exception((r['error'] ?? '导入失败').toString());
      if (mounted) { Navigator.pop(context); widget.onDone(); }
    } catch (e) {
      if (mounted) setState(() { _error = e.toString(); _busy = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入音乐音源'),
      content: SizedBox(
        width: 620,
        child: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const Text('方式一：网络 URL', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _urlCtrl, decoration: const InputDecoration(
            hintText: 'https://example.com/music-source.js',
            border: OutlineInputBorder(),
          )),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _busy ? null : _importUrl, child: const Text('从 URL 导入并启用')),
          const Divider(height: 28),
          const Text('方式二：粘贴 JS 源码', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          TextField(controller: _scriptCtrl, maxLines: 8, decoration: const InputDecoration(
            hintText: '/*! @name 音源名 */\n...',
            border: OutlineInputBorder(),
          )),
          const SizedBox(height: 8),
          ElevatedButton(onPressed: _busy ? null : _importScript, child: const Text('粘贴导入并启用')),
          if (_busy) const Padding(padding: EdgeInsets.only(top: 12), child: Center(child: CircularProgressIndicator(strokeWidth: 2))),
          if (_error != null) Padding(padding: const EdgeInsets.only(top: 12), child: Text(_error!, style: const TextStyle(color: Colors.red, fontSize: 12))),
        ])),
      ),
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('取消'))],
    );
  }

  @override
  void dispose() {
    _urlCtrl.dispose();
    _scriptCtrl.dispose();
    super.dispose();
  }
}

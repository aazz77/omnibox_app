// IPTV 直播源管理页（对齐 Nexus 的 iptv_tab_page.dart，去掉 GetX/hive/smart_dialog）。
// 支持网络 URL / 本地 m3u 文件导入，编辑、删除、刷新（刷新=重新拉取一次校验可达），
// 点击源卡片进入直播播放页（无左侧导航栏）。
import 'package:flutter/material.dart';

import '../iptv/iptv_sources.dart';
import '../player/iptv_player_page.dart';
import 'file_picker_service.dart';

class IptvPage extends StatefulWidget {
  const IptvPage({Key? key}) : super(key: key);
  @override
  State<IptvPage> createState() => _IptvPageState();
}

class _IptvPageState extends State<IptvPage> {
  final Set<int> _refreshing = {};

  void _openPlayer(int index) {
    final src = IptvStore.i.sources[index];
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => IptvPlayerPage(
        args: IptvPlayArgs(sourceIndex: index, sourceName: src.name),
      ),
    ));
  }

  Future<void> _refresh(int index) async {
    final src = IptvStore.i.sources[index];
    if (!src.isNetwork) return;
    setState(() => _refreshing.add(index));
    try {
      await IptvStore.i.loadContent(index);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已刷新: ${src.name}')),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('刷新失败: $e')),
      );
    } finally {
      if (mounted) setState(() => _refreshing.remove(index));
    }
  }

  Future<void> _delete(int index) async {
    final name = IptvStore.i.sources[index].name;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除「$name」吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      setState(() => IptvStore.i.remove(index));
    }
  }

  Future<void> _showEditor({int? index}) async {
    final existing = index != null ? IptvStore.i.sources[index] : null;
    final saved = await showDialog<IptvSource>(
      context: context,
      builder: (_) => _SourceEditor(existing: existing),
    );
    if (saved == null || !mounted) return;
    setState(() {
      if (index != null) {
        IptvStore.i.update(index, saved);
      } else {
        IptvStore.i.add(saved);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sources = IptvStore.i.sources;

    return Scaffold(
      appBar: AppBar(
        title: const Text('直播 / IPTV'),
        actions: [
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 18),
            label: const Text('导入'),
            onPressed: () => _showEditor(),
            style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8))),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: sources.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.live_tv_outlined,
                      size: 72, color: scheme.onSurfaceVariant.withAlpha(100)),
                  const SizedBox(height: 16),
                  const Text('暂无 IPTV 源',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  const Text('点击右上角「导入」按钮添加 M3U 源',
                      style: TextStyle(fontSize: 13, color: Colors.grey)),
                ],
              ),
            )
          : Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const minCardWidth = 280.0;
                  const spacing = 16.0;
                  final cols = ((constraints.maxWidth + spacing) /
                          (minCardWidth + spacing))
                      .floor()
                      .clamp(1, 3);
                  return GridView.builder(
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: cols,
                      crossAxisSpacing: spacing,
                      mainAxisSpacing: spacing,
                      childAspectRatio: 3.2,
                    ),
                    itemCount: sources.length,
                    itemBuilder: (_, i) => _SourceCard(
                      source: sources[i],
                      refreshing: _refreshing.contains(i),
                      onTap: () => _openPlayer(i),
                      onEdit: () => _showEditor(index: i),
                      onDelete: () => _delete(i),
                      onRefresh: () => _refresh(i),
                    ),
                  );
                },
              ),
            ),
    );
  }
}

class _SourceCard extends StatefulWidget {
  final IptvSource source;
  final bool refreshing;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onRefresh;
  const _SourceCard({
    required this.source,
    required this.refreshing,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onRefresh,
  });
  @override
  State<_SourceCard> createState() => _SourceCardState();
}

class _SourceCardState extends State<_SourceCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final src = widget.source;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          decoration: BoxDecoration(
            color: _hovered
                ? scheme.surfaceContainerHighest
                : scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hovered
                  ? scheme.primary.withAlpha(80)
                  : scheme.outlineVariant.withAlpha(60),
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: src.isNetwork
                      ? scheme.primaryContainer.withAlpha(120)
                      : scheme.secondaryContainer.withAlpha(120),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  src.isNetwork ? Icons.wifi_tethering : Icons.folder_open,
                  size: 20,
                  color: src.isNetwork ? scheme.primary : scheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      src.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        _Badge(
                          label: src.isNetwork ? '远程' : '文件',
                          color: src.isNetwork ? scheme.primary : scheme.secondary,
                          bg: src.isNetwork
                              ? scheme.primaryContainer.withAlpha(80)
                              : scheme.secondaryContainer.withAlpha(80),
                        ),
                        if (src.autoUpdate && src.isNetwork) ...[
                          const SizedBox(width: 4),
                          const _Badge(
                              label: '自动更新',
                              color: Colors.green,
                              bg: Color(0x1F4CAF50)),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (src.isNetwork)
                    _ActionBtn(
                      icon: Icons.refresh,
                      tooltip: '刷新',
                      color: scheme.primary,
                      loading: widget.refreshing,
                      onPressed: widget.onRefresh,
                    ),
                  _ActionBtn(
                      icon: Icons.edit_outlined,
                      tooltip: '编辑',
                      color: scheme.onSurfaceVariant,
                      onPressed: widget.onEdit),
                  _ActionBtn(
                      icon: Icons.delete_outline,
                      tooltip: '删除',
                      color: scheme.error.withAlpha(180),
                      onPressed: widget.onDelete),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final Color bg;
  const _Badge({required this.label, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration:
            BoxDecoration(color: bg, borderRadius: BorderRadius.circular(4)),
        child: Text(label, style: TextStyle(fontSize: 10, color: color)),
      );
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final Color color;
  final bool loading;
  final VoidCallback onPressed;
  const _ActionBtn({
    required this.icon,
    required this.tooltip,
    required this.color,
    required this.onPressed,
    this.loading = false,
  });
  @override
  Widget build(BuildContext context) => SizedBox(
        width: 32,
        height: 32,
        child: loading
            ? Padding(
                padding: const EdgeInsets.all(6),
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            : IconButton(
                padding: EdgeInsets.zero,
                icon: Icon(icon, size: 18, color: color),
                tooltip: tooltip,
                onPressed: onPressed,
              ),
      );
}

class _SourceEditor extends StatefulWidget {
  final IptvSource? existing;
  const _SourceEditor({this.existing});
  @override
  State<_SourceEditor> createState() => _SourceEditorState();
}

class _SourceEditorState extends State<_SourceEditor> {
  final _nameCtrl = TextEditingController();
  final _urlCtrl = TextEditingController();
  String _type = 'network';
  bool _autoUpdate = false;
  String? _filePath;
  String? _fileName;
  String? _nameError;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    if (e != null) {
      _nameCtrl.text = e.name;
      _urlCtrl.text = e.url;
      _type = e.type;
      _autoUpdate = e.autoUpdate;
      _filePath = e.filePath.isEmpty ? null : e.filePath;
      _fileName = e.fileName.isEmpty ? null : e.fileName;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final picked = await pickM3uFile();
    if (picked == null) return;
    setState(() {
      _filePath = picked['path'];
      _fileName = picked['name'];
    });
  }

  void _save() {
    setState(() => _nameError = null);
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = '名称不能为空');
      return;
    }
    if (_type == 'network' && _urlCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请输入 M3U 链接')),
      );
      return;
    }
    if (_type == 'file' && _filePath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请选择本地文件')),
      );
      return;
    }
    Navigator.of(context).pop(IptvSource(
      name: name,
      type: _type,
      autoUpdate: _autoUpdate,
      url: _type == 'network' ? _urlCtrl.text.trim() : '',
      filePath: _type == 'file' ? (_filePath ?? '') : '',
      fileName: _type == 'file' ? (_fileName ?? '') : '',
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isNetwork = _type == 'network';
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480, minWidth: 380),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.existing != null ? '编辑 IPTV 源' : '导入 IPTV 源',
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _nameCtrl,
                decoration: InputDecoration(
                  labelText: '名称 *',
                  hintText: '给这个源起个名字',
                  errorText: _nameError,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8)),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 16),
              const Text('导入方式',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: _TypeToggle(
                        label: '远程导入',
                        icon: Icons.wifi_tethering,
                        selected: isNetwork,
                        onTap: () => setState(() => _type = 'network')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _TypeToggle(
                        label: '文件导入',
                        icon: Icons.folder_open,
                        selected: !isNetwork,
                        onTap: () => setState(() => _type = 'file')),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Opacity(
                opacity: isNetwork ? 1.0 : 0.38,
                child: TextField(
                  controller: _urlCtrl,
                  enabled: isNetwork,
                  keyboardType: TextInputType.url,
                  decoration: InputDecoration(
                    labelText: 'M3U 链接',
                    hintText: 'http://example.com/playlist.m3u',
                    prefixIcon: const Icon(Icons.link, size: 18),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: isNetwork ? 0.38 : 1.0,
                child: Row(
                  children: [
                    OutlinedButton.icon(
                      icon: const Icon(Icons.upload_file, size: 16),
                      label: const Text('选择文件'),
                      onPressed: isNetwork ? null : _pickFile,
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _fileName ?? '未选择文件',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 12,
                            color: _fileName != null
                                ? scheme.onSurface
                                : scheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Opacity(
                opacity: isNetwork ? 1.0 : 0.38,
                child: Row(
                  children: [
                    Checkbox(
                      value: _autoUpdate,
                      onChanged: isNetwork
                          ? (v) => setState(() => _autoUpdate = v ?? false)
                          : null,
                    ),
                    const SizedBox(width: 4),
                    const Text('启动时自动更新', style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Divider(height: 1),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('取消'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: Text(widget.existing != null ? '保存' : '导入'),
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

class _TypeToggle extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;
  const _TypeToggle({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer
              : scheme.surfaceContainerHighest,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon,
                size: 16,
                color: selected ? scheme.primary : scheme.onSurfaceVariant),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                color: selected
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

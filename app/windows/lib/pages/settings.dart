import 'package:flutter/material.dart';
import '../settings.dart';
import '../live/live_api.dart';

/// 设置页：播放器解码方式 + 弹幕渲染参数
class SettingsPage extends StatelessWidget {
  const SettingsPage({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
        // ===== 点播播放器 =====
        const Text('点播播放器', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ValueListenableBuilder<String>(
          valueListenable: AppSettings.i.vodPlayer,
          builder: (context, core, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in AppSettings.vodPlayerOptions)
                RadioListTile<String>(
                  title: Text(o.label),
                  subtitle: Text(o.desc),
                  value: o.value,
                  groupValue: core,
                  onChanged: (v) {
                    if (v != null) AppSettings.i.setVodPlayer(v);
                  },
                ),
              if (core == 'mpv') ...[
                const Padding(
                  padding: EdgeInsets.only(left: 16, top: 4),
                  child: Text('mpv 解码方式', style: TextStyle(fontSize: 13, color: Colors.grey)),
                ),
                ValueListenableBuilder<String>(
                  valueListenable: AppSettings.i.hwdec,
                  builder: (context, current, _) => Column(
                    children: [
                      for (final o in AppSettings.hwdecOptions)
                        RadioListTile<String>(
                          title: Text(o.label),
                          subtitle: Text(o.desc),
                          value: o.value,
                          groupValue: current,
                          onChanged: (v) {
                            if (v != null) AppSettings.i.setHwdec(v);
                          },
                        ),
                    ],
                  ),
                ),
                const Text(
                  'mpv 解码切换后立即生效；若正在播放会自动重新加载当前剧集。',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ] else
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Text(
                    '当前点播走 VLC 内核，解码方式见下方「VLC 播放器」。',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        // ===== iptv 解码（原「直播解码」，M3U 直播走 VLC） =====
        const Text('iptv 解码（M3U 直播）',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ValueListenableBuilder<bool>(
          valueListenable: AppSettings.i.iptvHwdec,
          builder: (context, hw, _) => SwitchListTile(
            title: const Text('硬件解码'),
            subtitle: Text(hw
                ? 'VLC 自动选择 D3D11VA/DXVA2 硬解'
                : '强制软解，兼容性更好但 CPU 占用高'),
            value: hw,
            onChanged: (v) => AppSettings.i.setIptvHwdec(v),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: AppSettings.i.vlcHwdec,
          builder: (context, hw, _) => SwitchListTile(
            title: const Text('VLC 点播硬件解码'),
            subtitle: const Text('点播切到 VLC 内核时使用的解码方式'),
            value: hw,
            onChanged: (v) => AppSettings.i.setVlcHwdec(v),
          ),
        ),
        ValueListenableBuilder<bool>(
          valueListenable: AppSettings.i.showBuiltinIptv,
          builder: (context, show, _) => SwitchListTile(
            title: const Text('显示内置央视频源'),
            subtitle: const Text('在 iptv 页显示内置「央视频」源（只读，不可编辑删除）；关闭后不再显示'),
            value: show,
            onChanged: (v) => AppSettings.i.setShowBuiltinIptv(v),
          ),
        ),
        const Divider(height: 32),

        // ===== 音乐音质（对齐 lx-server preferredQuality + 智能降级）=====
        const Text('音乐音质', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        ValueListenableBuilder<String>(
          valueListenable: AppSettings.i.preferredQuality,
          builder: (context, current, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final o in AppSettings.musicQualityOptions)
                RadioListTile<String>(
                  title: Text(o.label),
                  subtitle: Text(o.desc),
                  value: o.value,
                  groupValue: current,
                  onChanged: (v) {
                    if (v != null) AppSettings.i.setPreferredQuality(v);
                  },
                ),
            ],
          ),
        ),
        const Text(
          '这是「偏好音质」：实际播放会从该档位开始，按歌曲支持的最高音质向下自动降级。'
          '正在播放的歌曲也会按新偏好重新加载；播放页底部可见当前实际音质。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
        const Divider(height: 32),

        // ===== 直播（6 平台聚合）=====
        const _LiveSettingsBody(),
        const Divider(height: 32),

        // ===== 弹幕（点播 + 直播共用同一设置项）=====
        ValueListenableBuilder<DanmuConfig>(
          valueListenable: AppSettings.i.danmu,
          builder: (context, cfg, _) => _DanmuSettingsBody(cfg: cfg),
        ),
        ],
      ),
    );
  }
}

class _DanmuSettingsBody extends StatelessWidget {
  final DanmuConfig cfg;
  const _DanmuSettingsBody({required this.cfg});

  void _update(DanmuConfig c) => AppSettings.i.setDanmu(c);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('弹幕（点播 + 直播共用）', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
        const SizedBox(height: 4),
        const Text('同一组参数同时作用于点播与直播弹幕；调整实时生效。',
            style: TextStyle(fontSize: 12, color: Colors.grey)),

        // ---- 通用 ----
        const Padding(padding: EdgeInsets.only(top: 10), child: Text('通用', style: TextStyle(fontSize: 13, color: Colors.indigo))),
        SwitchListTile(
          title: const Text('显示弹幕'),
          value: cfg.open,
          onChanged: (v) => _update(cfg.copyWith(open: v)),
        ),
        _slider(
          label: '透明度', value: cfg.alpha, min: 0.1, max: 1.0, divisions: 9,
          display: cfg.alpha.toStringAsFixed(1),
          onChanged: (v) => _update(cfg.copyWith(alpha: (v * 10).round() / 10)),
        ),

        // ---- 点播专属 ----
        const Padding(padding: EdgeInsets.only(top: 10), child: Text('点播弹幕', style: TextStyle(fontSize: 13, color: Colors.indigo))),
        _slider(
          label: '轨道行数', value: cfg.lines.toDouble(), min: 1, max: 30, divisions: 29,
          display: '${cfg.lines}',
          onChanged: (v) => _update(cfg.copyWith(lines: v.round())),
        ),
        _slider(
          label: '滚动速度', value: cfg.speed, min: 0.5, max: 5.0, divisions: 45,
          display: '${cfg.speed.toStringAsFixed(1)}（越大越慢）',
          onChanged: (v) => _update(cfg.copyWith(speed: (v * 10).round() / 10)),
        ),
        _slider(
          label: '字号缩放', value: cfg.size, min: 0.4, max: 2.4, divisions: 20,
          display: cfg.size.toStringAsFixed(1),
          onChanged: (v) => _update(cfg.copyWith(size: (v * 10).round() / 10)),
        ),
        _slider(
          label: '行间距', value: cfg.spacing.toDouble(), min: 0, max: 32, divisions: 32,
          display: '${cfg.spacing}px',
          onChanged: (v) => _update(cfg.copyWith(spacing: v.round())),
        ),
        _slider(
          label: '顶部边距', value: cfg.top.toDouble(), min: 0, max: 300, divisions: 30,
          display: '${cfg.top}px',
          onChanged: (v) => _update(cfg.copyWith(top: v.round())),
        ),
        SwitchListTile(
          title: const Text('随机颜色'),
          subtitle: const Text('忽略弹幕自带颜色'),
          value: cfg.randomColor,
          onChanged: (v) => _update(cfg.copyWith(randomColor: v)),
        ),
        _ApiBaseField(apiBase: cfg.apiBase, onSaved: (v) => _update(cfg.copyWith(apiBase: v))),

        // ---- 直播专属 ----
        const Padding(padding: EdgeInsets.only(top: 10), child: Text('直播弹幕', style: TextStyle(fontSize: 13, color: Colors.indigo))),
        _slider(
          label: '字号', value: cfg.fontSize.toDouble(), min: 12, max: 48, divisions: 36,
          display: '${cfg.fontSize}px',
          onChanged: (v) => _update(cfg.copyWith(fontSize: v.round())),
        ),
        _slider(
          label: '显示区域', value: cfg.area.toDouble(), min: 20, max: 100, divisions: 80,
          display: '${cfg.area}%',
          onChanged: (v) => _update(cfg.copyWith(area: v.round())),
        ),
        _slider(
          label: '水平间距', value: cfg.itemGap.toDouble(), min: 0, max: 300, divisions: 30,
          display: '${cfg.itemGap}px',
          onChanged: (v) => _update(cfg.copyWith(itemGap: v.round())),
        ),
        _slider(
          label: '滚动时长', value: cfg.duration, min: 2, max: 20, divisions: 18,
          display: '${cfg.duration.toStringAsFixed(0)}秒/屏',
          onChanged: (v) => _update(cfg.copyWith(duration: v.round().toDouble())),
        ),
        DropdownButtonFormField<String>(
          value: cfg.colorMode,
          decoration: const InputDecoration(labelText: '颜色模式', isDense: true),
          items: const [
            DropdownMenuItem(value: 'platform', child: Text('跟随平台')),
            DropdownMenuItem(value: 'rainbow', child: Text('缤纷')),
            DropdownMenuItem(value: 'white', child: Text('纯白')),
            DropdownMenuItem(value: 'custom', child: Text('自定义')),
          ],
          onChanged: (v) { if (v != null) _update(cfg.copyWith(colorMode: v)); },
        ),
        if (cfg.colorMode == 'custom')
          Padding(padding: const EdgeInsets.symmetric(vertical: 8), child: Row(children: [
            const Text('自定义颜色  '),
            Container(width: 24, height: 24, color: _hex(cfg.color), decoration: BoxDecoration(border: Border.all(color: Colors.grey))),
            const SizedBox(width: 8),
            SizedBox(width: 140, child: TextField(decoration: const InputDecoration(hintText: '#ffffff', isDense: true), controller: TextEditingController(text: cfg.color), onSubmitted: (v) => _update(cfg.copyWith(color: v.trim())))),
          ])),
        SwitchListTile(title: const Text('文字加粗'), value: cfg.bold, onChanged: (v) => _update(cfg.copyWith(bold: v))),
        SwitchListTile(title: const Text('描边阴影'), value: cfg.stroke, onChanged: (v) => _update(cfg.copyWith(stroke: v))),
        SwitchListTile(title: const Text('显示用户名'), value: cfg.showUser, onChanged: (v) => _update(cfg.copyWith(showUser: v))),

        const SizedBox(height: 12),
        const Text(
          '点播弹幕需在播放页点右上角「弹幕搜索」选择剧集后加载；直播弹幕进入直播播放页自动订阅。',
          style: TextStyle(fontSize: 12, color: Colors.grey),
        ),
      ],
    );
  }

  Color _hex(String s) {
    final v = int.tryParse(s.replaceFirst('#', ''), radix: 16);
    return v == null ? Colors.white : Color(0xff000000 | v);
  }

  Widget _slider({
    required String label,
    required double value,
    required double min,
    required double max,
    required int divisions,
    required String display,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(label, style: const TextStyle(fontSize: 13)),
          Text(display, style: const TextStyle(fontSize: 12, color: Colors.grey)),
        ]),
        Slider(value: value, min: min, max: max, divisions: divisions, onChanged: onChanged),
      ],
    );
  }
}

/// API 地址输入：controller 在 state 内持有，避免父级重建时丢失正在输入的内容
class _ApiBaseField extends StatefulWidget {
  final String apiBase;
  final ValueChanged<String> onSaved;
  const _ApiBaseField({required this.apiBase, required this.onSaved});
  @override
  State<_ApiBaseField> createState() => _ApiBaseFieldState();
}

class _ApiBaseFieldState extends State<_ApiBaseField> {
  late final TextEditingController _c;
  @override
  void initState() {
    super.initState();
    _c = TextEditingController(text: widget.apiBase);
  }
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _c,
      decoration: const InputDecoration(
        labelText: '弹幕 API 地址（留空用内置镜像）',
        hintText: 'https://logvardanmu.konfan.cn',
        isDense: true,
        border: OutlineInputBorder(),
      ),
      onSubmitted: (v) => widget.onSaved(v.trim()),
    );
  }
}

/// 直播（6 平台聚合）设置：内核 / 解码 / 画质 / 平台 Cookie。弹幕设置见下方共用项。
/// Cookie 由内核 silm.json 持久化（LiveSettingsGet/Set），其余为本地 ValueNotifier。
class _LiveSettingsBody extends StatefulWidget {
  const _LiveSettingsBody();
  @override
  State<_LiveSettingsBody> createState() => _LiveSettingsBodyState();
}

class _LiveSettingsBodyState extends State<_LiveSettingsBody> {
  final _douyinCtrl = TextEditingController();
  final _kuaishouCtrl = TextEditingController();
  bool _cookieLoaded = false;
  bool _cookieSaving = false;

  @override
  void initState() {
    super.initState();
    _loadCookie();
  }

  @override
  void dispose() {
    _douyinCtrl.dispose();
    _kuaishouCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadCookie() async {
    try {
      final s = await LiveApi.i.settingsGet();
      final cookies = (s['cookies'] as Map?) ?? {};
      _douyinCtrl.text = cookies['douyin']?.toString() ?? '';
      _kuaishouCtrl.text = cookies['kuaishou']?.toString() ?? '';
    } catch (_) {}
    if (mounted) setState(() => _cookieLoaded = true);
  }

  Future<void> _saveCookie() async {
    setState(() => _cookieSaving = true);
    try {
      final s = await LiveApi.i.settingsGet();
      // 保留内核返回的其余设置（danmaku/panelAuth），只改 cookies
      s['cookies'] = {'douyin': _douyinCtrl.text.trim(), 'kuaishou': _kuaishouCtrl.text.trim()};
      await LiveApi.i.settingsSet(Map<String, dynamic>.from(s));
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cookie 已保存')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('保存失败：$e')));
    }
    if (mounted) setState(() => _cookieSaving = false);
  }

  @override
  Widget build(BuildContext context) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      const Text('直播', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      const Text('6 平台聚合直播（B站/斗鱼/虎牙/抖音/快手/小红书），独立于点播与 iptv。',
          style: TextStyle(fontSize: 12, color: Colors.grey)),

      // 直播内核
      ValueListenableBuilder<String>(
        valueListenable: AppSettings.i.livePlayer,
        builder: (context, core, _) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Padding(padding: EdgeInsets.only(top: 8), child: Text('播放器内核', style: TextStyle(fontSize: 13, color: Colors.grey))),
          RadioListTile<String>(
            title: const Text('mpv'),
            subtitle: const Text('media_kit/libmpv，弹幕同步好'),
            value: 'mpv', groupValue: core,
            onChanged: (v) { if (v != null) AppSettings.i.setLivePlayer(v); },
          ),
          RadioListTile<String>(
            title: const Text('VLC'),
            subtitle: const Text('libVLC，对直播流容错更好'),
            value: 'vlc', groupValue: core,
            onChanged: (v) { if (v != null) AppSettings.i.setLivePlayer(v); },
          ),
          if (core == 'mpv')
            ValueListenableBuilder<String>(
              valueListenable: AppSettings.i.liveHwdec,
              builder: (context, cur, _) => Column(children: [
                const Padding(padding: EdgeInsets.only(left: 16), child: Text('直播 mpv 解码方式', style: TextStyle(fontSize: 12, color: Colors.grey))),
                for (final o in AppSettings.hwdecOptions)
                  RadioListTile<String>(
                    title: Text(o.label), subtitle: Text(o.desc),
                    value: o.value, groupValue: cur,
                    onChanged: (v) { if (v != null) AppSettings.i.setLiveHwdec(v); },
                  ),
              ]),
            )
          else
            ValueListenableBuilder<bool>(
              valueListenable: AppSettings.i.vlcHwdec,
              builder: (context, hw, _) => SwitchListTile(
                title: const Text('VLC 硬件解码'),
                subtitle: Text(hw ? '硬解（D3D11VA/DXVA2）' : '强制软解'),
                value: hw, onChanged: (v) => AppSettings.i.setVlcHwdec(v),
              ),
            ),
        ]),
      ),

      // 直播画质偏好
      const Padding(padding: EdgeInsets.only(top: 8), child: Text('默认画质', style: TextStyle(fontSize: 13, color: Colors.grey))),
      ValueListenableBuilder<String>(
        valueListenable: AppSettings.i.liveQuality,
        builder: (context, cur, _) => Column(children: [
          for (final o in AppSettings.liveQualityOptions)
            RadioListTile<String>(
              title: Text(o.label), subtitle: Text(o.desc),
              value: o.value, groupValue: cur,
              onChanged: (v) { if (v != null) AppSettings.i.setLiveQuality(v); },
            ),
        ]),
      ),

      // 弹幕设置已与点播统一，见下方「弹幕」设置项（点播 + 直播共用）

      // Cookie
      const Padding(padding: EdgeInsets.only(top: 12), child: Text('平台 Cookie', style: TextStyle(fontSize: 13, color: Colors.grey))),
      const Text('抖音搜索/弹幕、快手弹幕与搜索需要登录态 Cookie。可粘贴整段请求头。',
          style: TextStyle(fontSize: 12, color: Colors.grey)),
      if (_cookieLoaded) ...[
        TextField(controller: _douyinCtrl, decoration: const InputDecoration(labelText: '抖音 Cookie', isDense: true, border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 8),
        TextField(controller: _kuaishouCtrl, decoration: const InputDecoration(labelText: '快手 Cookie', isDense: true, border: OutlineInputBorder()), maxLines: 2),
        const SizedBox(height: 8),
        Align(alignment: Alignment.centerLeft, child: ElevatedButton.icon(
          onPressed: _cookieSaving ? null : _saveCookie,
          icon: const Icon(Icons.save), label: Text(_cookieSaving ? '保存中…' : '保存 Cookie'),
        )),
      ] else
        const Padding(padding: EdgeInsets.all(8), child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))),
    ]);
  }
}


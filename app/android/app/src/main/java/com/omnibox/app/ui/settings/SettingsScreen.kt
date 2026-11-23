package com.omnibox.app.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Divider
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.Button
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.core.DanmuConfig
import com.omnibox.app.core.LiveDanmuConfig
import kotlinx.coroutines.launch
import org.json.JSONObject

@Composable
fun SettingsScreen() {
    val scroll = rememberScrollState()
    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(16.dp)) {
        SectionTitle("IPTV / 直播")
        val showBuiltin by AppSettings.showBuiltinIptv.collectAsStateWithLifecycle()
        SwitchRow("显示内置央视频源", showBuiltin) { AppSettings.setShowBuiltinIptv(it) }

        Divider(Modifier.padding(vertical = 16.dp))
        SectionTitle("音乐音质")
        val quality by AppSettings.preferredQuality.collectAsStateWithLifecycle()
        RadioGroup(AppSettings.musicQualityOptions, quality) { AppSettings.setPreferredQuality(it) }
        Text("说明：这是偏好档位，播放时会按歌曲实际支持的音质智能降级", style = MaterialTheme.typography.bodySmall)

        Divider(Modifier.padding(vertical = 16.dp))
        SectionTitle("直播画质")
        val liveQuality by AppSettings.liveQuality.collectAsStateWithLifecycle()
        RadioGroup(AppSettings.liveQualityOptions, liveQuality) { AppSettings.setLiveQuality(it) }
        LiveCookieSection()

        Divider(Modifier.padding(vertical = 16.dp))
        SectionTitle("点播弹幕")
        DanmuSettingsSection()

        Divider(Modifier.padding(vertical = 16.dp))
        SectionTitle("直播弹幕")
        LiveDanmuSettingsSection()

        Spacer(Modifier.height(32.dp))
    }
}

@Composable
private fun SectionTitle(text: String) {
    Text(text, style = MaterialTheme.typography.titleMedium)
    Spacer(Modifier.height(4.dp))
}

@Composable
private fun RadioGroup(options: List<AppSettings.Option>, selected: String, onSelect: (String) -> Unit) {
    options.forEach { opt ->
        Row(Modifier.fillMaxWidth().padding(vertical = 2.dp), verticalAlignment = Alignment.CenterVertically) {
            RadioButton(selected = selected == opt.value, onClick = { onSelect(opt.value) })
            Column {
                Text(opt.label)
                if (opt.desc.isNotEmpty()) Text(opt.desc, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurface.copy(0.6f))
            }
        }
    }
}

@Composable
private fun SwitchRow(label: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(label, modifier = Modifier.weight(1f))
        Switch(checked = checked, onCheckedChange = onChange)
    }
}

@Composable
private fun DanmuSettingsSection() {
    val cfg by AppSettings.danmu.collectAsStateWithLifecycle()
    SwitchRow("显示弹幕", cfg.open) { AppSettings.setDanmu(cfg.copy(open = it)) }
    IntSlider("轨道行数", cfg.lines, 1, 30) { AppSettings.setDanmu(cfg.copy(lines = it)) }
    DoubleSlider("滚动时长（越大越慢）", cfg.speed, 0.5, 5.0) { AppSettings.setDanmu(cfg.copy(speed = it)) }
    DoubleSlider("字号", cfg.size, 0.4, 2.4) { AppSettings.setDanmu(cfg.copy(size = it)) }
    DoubleSlider("透明度", cfg.alpha, 0.1, 1.0) { AppSettings.setDanmu(cfg.copy(alpha = it)) }
    IntSlider("行间距", cfg.spacing, 0, 32) { AppSettings.setDanmu(cfg.copy(spacing = it)) }
    IntSlider("顶部边距", cfg.top, 0, 300) { AppSettings.setDanmu(cfg.copy(top = it)) }
    SwitchRow("忽略弹幕自带颜色", cfg.randomColor) { AppSettings.setDanmu(cfg.copy(randomColor = it)) }
    var apiBase by remember(cfg.apiBase) { mutableStateOf(cfg.apiBase) }
    OutlinedTextField(value = apiBase, onValueChange = { apiBase = it }, label = { Text("弹幕 API（留空用内置）") }, modifier = Modifier.fillMaxWidth(), singleLine = true)
    Button(onClick = { AppSettings.setDanmu(cfg.copy(apiBase = apiBase)) }) { Text("保存 API 地址") }
}

@Composable
private fun LiveDanmuSettingsSection() {
    val cfg by AppSettings.liveDanmu.collectAsStateWithLifecycle()
    SwitchRow("显示直播弹幕", cfg.enabled) { AppSettings.setLiveDanmu(cfg.copy(enabled = it)) }
    IntSlider("字号", cfg.fontSize, 12, 48) { AppSettings.setLiveDanmu(cfg.copy(fontSize = it)) }
    IntSlider("显示区域 %", cfg.area, 20, 100) { AppSettings.setLiveDanmu(cfg.copy(area = it)) }
    IntSlider("行间距", cfg.lineGap, 0, 40) { AppSettings.setLiveDanmu(cfg.copy(lineGap = it)) }
    IntSlider("水平间距", cfg.itemGap, 0, 300) { AppSettings.setLiveDanmu(cfg.copy(itemGap = it)) }
    DoubleSlider("秒/屏", cfg.duration, 2.0, 20.0) { AppSettings.setLiveDanmu(cfg.copy(duration = it)) }
    val modes = listOf("platform" to "跟随平台", "rainbow" to "缤纷", "white" to "纯白", "custom" to "自定义")
    modes.forEach { (v, label) ->
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            RadioButton(selected = cfg.colorMode == v, onClick = { AppSettings.setLiveDanmu(cfg.copy(colorMode = v)) })
            Text(label)
        }
    }
    DoubleSlider("透明度", cfg.opacity, 0.2, 1.0) { AppSettings.setLiveDanmu(cfg.copy(opacity = it)) }
    SwitchRow("文字加粗", cfg.bold) { AppSettings.setLiveDanmu(cfg.copy(bold = it)) }
    SwitchRow("描边阴影", cfg.stroke) { AppSettings.setLiveDanmu(cfg.copy(stroke = it)) }
    SwitchRow("显示用户名", cfg.showUser) { AppSettings.setLiveDanmu(cfg.copy(showUser = it)) }
}

@Composable
private fun LiveCookieSection() {
    var douyin by remember { mutableStateOf("") }
    var kuaishou by remember { mutableStateOf("") }
    var loaded by remember { mutableStateOf(false) }
    var saving by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    LaunchedEffect(Unit) {
        val r = Api.call("live_settings_get")
        val cookies = r.optJSONObject("cookies")
        douyin = cookies?.optString("douyin", "") ?: ""
        kuaishou = cookies?.optString("kuaishou", "") ?: ""
        loaded = true
    }
    OutlinedTextField(value = douyin, onValueChange = { douyin = it }, label = { Text("抖音 Cookie") }, modifier = Modifier.fillMaxWidth())
    OutlinedTextField(value = kuaishou, onValueChange = { kuaishou = it }, label = { Text("快手 Cookie") }, modifier = Modifier.fillMaxWidth())
    Button(onClick = {
        saving = true
        scope.launch {
            val settings = Api.call("live_settings_get")
            val cookies = JSONObject().apply { put("douyin", douyin); put("kuaishou", kuaishou) }
            settings.put("cookies", cookies)
            Api.call("live_settings_set", mapOf(*settings.keys().asSequence().map { it to settings.opt(it) }.toList().toTypedArray()))
            saving = false
        }
    }, enabled = loaded && !saving) { Text(if (saving) "保存中..." else "保存 Cookie") }
}

@Composable
private fun IntSlider(label: String, value: Int, min: Int, max: Int, onChange: (Int) -> Unit) {
    Text("$label: $value", style = MaterialTheme.typography.bodyMedium)
    Slider(value = value.toFloat(), onValueChange = { onChange(it.toInt()) }, valueRange = min.toFloat()..max.toFloat())
}

@Composable
private fun DoubleSlider(label: String, value: Double, min: Double, max: Double, onChange: (Double) -> Unit) {
    Text("$label: ${String.format("%.1f", value)}", style = MaterialTheme.typography.bodyMedium)
    Slider(value = value.toFloat(), onValueChange = { onChange((it * 10).toInt() / 10.0) }, valueRange = min.toFloat()..max.toFloat())
}

package com.omnibox.app.player

import androidx.compose.foundation.Canvas
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import com.omnibox.app.core.AppSettings
import com.omnibox.app.core.DanmuConfig
import com.omnibox.app.models.DanmuItem
import kotlinx.coroutines.flow.Flow
import kotlin.math.roundToInt

private data class Lane(
    val index: Int,
    var lastStart: Double = -1e9,
    var lastTextW: Float = 0f,
    var lastPx: Double = 0.0,
    var lastDur: Double = 0.0
)

private data class Active(
    val text: String,
    val start: Double,      // 弹幕自带视频时间（秒）
    val scroll: Boolean,
    val textW: Float,
    val pxSpeed: Double,
    val dur: Double,
    val top: Float,
    val color: Color,
    val fontSize: Float
)

private val PALETTE = listOf(
    0xFFFFFFFF, 0xFF70F3FF, 0xFF44CEF6, 0xFF3EEDE7, 0xFF00E079, 0xFF2EDFA3,
    0xFFBCE672, 0xFFFFF143, 0xFFFFA631, 0xFFFF7500, 0xFFFF4E20, 0xFFFF2D51,
    0xFFEF7A82, 0xFFFF0097, 0xFFB0A4E3, 0xFF4B5CC4
)

private const val GRACE = 0.5
private const val SEEK_THRESHOLD = 1.0
private const val TAIL_GAP = 32f
private const val FIXED_DUR = 5.0
private const val BASE_SCROLL = 8.0

/**
 * 点播弹幕层：按视频时间排程、轨道防重叠、seek 二分重定位。
 * 复刻 Flutter danmu_overlay.dart 的核心算法。
 *
 * @param positionFlow 播放位置流（毫秒）
 * @param items 弹幕列表（按 time 升序）
 * @param configProvider 当前弹幕配置
 */
@Composable
fun DanmuCanvas(
    positionFlow: Flow<Long>,
    items: List<DanmuItem>,
    config: DanmuConfig,
    modifier: Modifier = Modifier
) {
    val textMeasurer = rememberTextMeasurer()
    var nowSec by remember { mutableLongStateOf(0L) } // 毫秒
    var invalidateTick by remember { mutableLongStateOf(0L) }

    // 运行状态用普通可变列表（配合 withFrameMillis 手动重绘，避免重组开销）
    val state = remember { DanmuState() }
    state.items = items
    state.config = config

    LaunchedEffect(positionFlow) {
        positionFlow.collect { ms ->
            val now = ms / 1000.0
            state.lastObserved = now
        }
    }

    LaunchedEffect(Unit) {
        withFrameMillis { frameTimeMs ->
            val nowMs = state.lastObserved
            nowSec = (nowMs * 1000).toLong()
            state.tick(nowMs, textMeasurer)
            invalidateTick = frameTimeMs
        }
    }

    // configuration change => clear
    LaunchedEffect(config) { state.clear() }
    // items change => clear
    LaunchedEffect(items) { state.clear() }

    Canvas(modifier = modifier) {
        val w = size.width
        val h = size.height
        if (w <= 0 || h <= 0) return@Canvas
        state.layout(w, h)

        val now = state.lastObserved
        val alpha = config.alpha.toFloat()
        state.activeList.forEach { rec ->
            val prog = now - rec.start
            if (rec.scroll) {
                val x = w - (prog * rec.pxSpeed).toFloat()
                if (x + rec.textW < 0f || x > w) return@forEach
                drawDanmu(textMeasurer, rec.text, rec.fontSize, rec.color.copy(alpha = alpha), Offset(x, rec.top), rec.textW)
            } else {
                val x = (w - rec.textW) / 2f
                drawDanmu(textMeasurer, rec.text, rec.fontSize, rec.color.copy(alpha = alpha), Offset(x, rec.top), rec.textW)
            }
        }
        // 触发读取，确保重组时重绘
        @Suppress("UNUSED_VARIABLE") val t = invalidateTick
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.drawDanmu(
    measurer: TextMeasurer,
    text: String,
    fontSize: Float,
    color: Color,
    topLeft: Offset,
    width: Float
) {
    val style = TextStyle(
        color = color,
        fontSize = androidx.compose.ui.unit.TextUnit(fontSize, androidx.compose.ui.unit.TextUnitType.Sp),
        fontWeight = FontWeight.W500,
        shadow = Shadow(offset = Offset(1f, 1f), blurRadius = 2f, color = Color(0x99000000))
    )
    val measured = measurer.measure(text, style)
    drawText(measured, topLeft = topLeft)
}

/** 弹幕运行时状态（保持算法中的可变结构） */
private class DanmuState {
    var items: List<DanmuItem> = emptyList()
    var config: DanmuConfig = DanmuConfig()
    var lastObserved: Double = 0.0      // 秒
    private var lastNow: Double = 0.0
    private var pointer = 0
    private var w = 0f; private var h = 0f
    private var scrollLanes = Array(3) { Lane(it) }
    private var topLanes = Array(3) { Lane(it) }
    private var bottomLanes = Array(3) { Lane(it) }
    val activeList = mutableListOf<Active>()

    fun layout(width: Float, height: Float) {
        if (w != width || h != height) { w = width; h = height; resetLanes() }
    }

    fun clear() {
        activeList.clear()
        pointer = 0
        resetLanes()
    }

    private fun resetLanes() {
        val count = config.lines.coerceAtLeast(1)
        scrollLanes = Array(count) { Lane(it) }
        topLanes = Array(count) { Lane(it) }
        bottomLanes = Array(count) { Lane(it) }
    }

    private fun baseFont(): Int {
        if (h <= 0f) return 18
        return (18 + h / 24f).roundToInt().coerceIn(14, 28)
    }

    fun tick(now: Double, measurer: TextMeasurer) {
        if (items.isEmpty() || !config.open || w <= 0 || h <= 0) return
        // seek 判定
        if (kotlin.math.abs(now - lastNow) > SEEK_THRESHOLD) onSeek(now)
        lastNow = now

        while (pointer < items.size && items[pointer].time <= now) {
            val item = items[pointer++]
            if (now - item.time <= GRACE) place(item, item.time, measurer)
        }
        activeList.removeAll { now - it.start > it.dur }
    }

    private fun onSeek(now: Double) {
        activeList.clear()
        resetLanes()
        val t = now - 0.05
        var lo = 0; var hi = items.size
        while (lo < hi) {
            val mid = (lo + hi) ushr 1
            if (items[mid].time < t) lo = mid + 1 else hi = mid
        }
        pointer = lo
    }

    private fun textWidth(text: String, fs: Float, measurer: TextMeasurer): Float {
        val style = TextStyle(
            fontSize = androidx.compose.ui.unit.TextUnit(fs, androidx.compose.ui.unit.TextUnitType.Sp),
            fontWeight = FontWeight.W500
        )
        return measurer.measure(text, style).size.width.toFloat()
    }

    private fun parseColor(hex: String): Color = runCatching {
        val clean = hex.removePrefix("#")
        if (clean.length == 6) Color(("FF" + clean.uppercase()).toLong(16)) else Color.White
    }.getOrDefault(Color.White)

    private fun place(item: DanmuItem, start: Double, measurer: TextMeasurer) {
        val fs = (baseFont() * config.size).roundToInt().coerceAtLeast(8).toFloat()
        val laneH = fs + config.spacing
        val textW = textWidth(item.text, fs, measurer)
        val color = if (config.randomColor) {
            Color(PALETTE[((System.currentTimeMillis() + item.time.toLong()) % PALETTE.size).toInt()])
        } else parseColor(item.color)

        if (item.mode in 1..3) {
            val pxSpeed = (w + textW) / (BASE_SCROLL * config.speed)
            val lane = allocLane(scrollLanes, start, textW, pxSpeed, 0.0) ?: return
            lane.lastStart = start; lane.lastTextW = textW; lane.lastPx = pxSpeed
            lane.lastDur = (w + textW) / pxSpeed
            activeList.add(Active(item.text, start, true, textW, pxSpeed, lane.lastDur,
                config.top + lane.index * laneH, color, fs))
        } else {
            val lanes = if (item.mode == 4) bottomLanes else topLanes
            val lane = allocLane(lanes, start, textW, 0.0, FIXED_DUR) ?: return
            lane.lastStart = start
            val top = if (item.mode == 5) config.top + lane.index * laneH
                      else h - (lane.index + 1) * laneH
            activeList.add(Active(item.text, start, false, textW, 0.0, FIXED_DUR, top, color, fs))
        }
    }

    private fun allocLane(lanes: Array<Lane>, itemTime: Double, textW: Float, newPx: Double, busySec: Double): Lane? {
        for (lane in lanes) {
            if (lane.lastStart < -1e8) return lane
            if (busySec > 0) {
                if (itemTime - lane.lastStart >= busySec) return lane
                continue
            }
            val dt = itemTime - lane.lastStart
            if (dt * lane.lastPx < lane.lastTextW + TAIL_GAP) continue
            if (dt < lane.lastDur && (lane.lastDur - dt) * newPx > w) continue
            return lane
        }
        return null
    }
}

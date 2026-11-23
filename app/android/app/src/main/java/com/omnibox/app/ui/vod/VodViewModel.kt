package com.omnibox.app.ui.vod

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.omnibox.app.core.Api
import com.omnibox.app.core.AppSettings
import com.omnibox.app.models.DanmuItem
import com.omnibox.app.models.Episode
import com.omnibox.app.models.HistoryItem
import com.omnibox.app.models.PlayResult
import com.omnibox.app.models.SpiderMeta
import com.omnibox.app.models.Vod
import com.omnibox.app.models.VodDetail
import com.omnibox.app.models.str
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import org.json.JSONObject

class VodViewModel : ViewModel() {
    // 豆瓣首页
    private val _banners = MutableStateFlow<List<Vod>>(emptyList())
    val banners: StateFlow<List<Vod>> = _banners.asStateFlow()
    private val _movies = MutableStateFlow<List<Vod>>(emptyList())
    val movies: StateFlow<List<Vod>> = _movies.asStateFlow()
    private val _tv = MutableStateFlow<List<Vod>>(emptyList())
    val tv: StateFlow<List<Vod>> = _tv.asStateFlow()

    // 搜索
    private val _sources = MutableStateFlow<List<SpiderMeta>>(emptyList())
    val sources: StateFlow<List<SpiderMeta>> = _sources.asStateFlow()
    private val _results = MutableStateFlow<List<Vod>>(emptyList())
    val results: StateFlow<List<Vod>> = _results.asStateFlow()
    private val _searchHasMore = MutableStateFlow(false)
    val searchHasMore: StateFlow<Boolean> = _searchHasMore.asStateFlow()

    // 历史
    private val _history = MutableStateFlow<List<HistoryItem>>(emptyList())
    val history: StateFlow<List<HistoryItem>> = _history.asStateFlow()

    // 详情
    private val _detail = MutableStateFlow<VodDetail?>(null)
    val detail: StateFlow<VodDetail?> = _detail.asStateFlow()

    private val _loading = MutableStateFlow(false)
    val loading: StateFlow<Boolean> = _loading.asStateFlow()
    private val _error = MutableStateFlow<String?>(null)
    val error: StateFlow<String?> = _error.asStateFlow()

    fun loadHome() = viewModelScope.launch {
        _loading.value = true
        _error.value = null
        runCatching {
            val r = Api.doubanHome()
            fun vlist(key: String) = r.optJSONObject(key)?.optJSONArray("list")?.let { arr ->
                (0 until arr.length()).map { Vod.from(arr.getJSONObject(it)) }
            } ?: emptyList()
            _banners.value = r.optJSONArray("banners")?.let { arr ->
                (0 until arr.length()).map { i ->
                    val j = arr.getJSONObject(i)
                    Vod(pic = j.str("backgroundImage"), name = j.str("title"), remarks = j.str("genre"))
                }
            } ?: emptyList()
            _movies.value = vlist("movie")
            _tv.value = vlist("tv")
        }.onFailure { _error.value = it.message }
        _loading.value = false
    }

    fun loadSources() = viewModelScope.launch {
        runCatching {
            val r = Api.spidersList()
            _sources.value = r.optJSONArray("list")?.let { arr ->
                (0 until arr.length()).map { SpiderMeta.from(arr.getJSONObject(it)) }
            } ?: emptyList()
        }
    }

    fun search(src: String, wd: String, page: Int = 1) = viewModelScope.launch {
        if (wd.isBlank()) return@launch
        _loading.value = true
        _error.value = null
        runCatching {
            val r = Api.search(src, wd, page)
            val list = r.optJSONArray("list")?.let { arr ->
                (0 until arr.length()).map { Vod.from(arr.getJSONObject(it)) }
            } ?: emptyList()
            if (page == 1) _results.value = list else _results.value = _results.value + list
            _searchHasMore.value = r.optInt("pagecount", 1) > page
        }.onFailure { _error.value = it.message }
        _loading.value = false
    }

    fun loadHistory() = viewModelScope.launch {
        _loading.value = true
        runCatching {
            val r = Api.historyList()
            _history.value = r.optJSONArray("list")?.let { arr ->
                (0 until arr.length()).map { HistoryItem.from(arr.getJSONObject(it)) }
            } ?: emptyList()
        }.onFailure { _error.value = it.message }
        _loading.value = false
    }

    fun removeHistory(key: String) = viewModelScope.launch {
        val r = Api.historyRemove(key)
        r.optJSONArray("list")?.let { arr ->
            _history.value = (0 until arr.length()).map { HistoryItem.from(arr.getJSONObject(it)) }
        }
    }

    fun clearHistory() = viewModelScope.launch {
        Api.historyClear()
        _history.value = emptyList()
    }

    fun loadDetail(src: String, id: String, onDone: (Boolean) -> Unit = {}) = viewModelScope.launch {
        _loading.value = true
        _error.value = null
        runCatching {
            val r = Api.detail(src, id)
            if (r.has("error") && !r.has("vod")) {
                _error.value = r.optString("error")
                onDone(false)
            } else {
                val vodObj = r.optJSONObject("vod") ?: JSONObject()
                val vod = Vod.from(vodObj).copy(source = r.str("source", src))
                val eps = r.optJSONArray("episodes")?.let { arr ->
                    (0 until arr.length()).map { Episode.from(arr.getJSONObject(it)) }
                } ?: emptyList()
                _detail.value = VodDetail(
                    vod = vod,
                    episodes = eps,
                    desc = vodObj.str("vod_content"),
                    source = r.str("source", src),
                    year = vodObj.str("vod_year"),
                    area = vodObj.str("vod_area"),
                    actor = vodObj.str("vod_actor"),
                    director = vodObj.str("vod_director"),
                    type = vodObj.str("vod_class", vodObj.str("vod_type")),
                    remarks = vodObj.str("vod_remarks")
                )
                // 进入详情即记历史
                recordHistory(vod, 0, "")
                onDone(true)
            }
        }.onFailure { _error.value = it.message; onDone(false) }
        _loading.value = false
    }

    fun recordHistory(vod: Vod, ep: Int, epname: String) = viewModelScope.launch {
        runCatching { Api.historyAdd(vod.source, vod.id, vod.name, vod.pic, ep, epname) }
    }

    suspend fun resolvePlay(src: String, q: String): PlayResult? = runCatching {
        val r = Api.play(src, q)
        if (r.has("error") && !r.has("url")) null else {
            val url = r.optString("url")
            val headers = r.optJSONObject("header")?.let { h ->
                h.keys().asSequence().associateWith { k -> h.opt(k).toString() }
            } ?: emptyMap()
            PlayResult(url, headers)
        }
    }.getOrNull()

    suspend fun searchDanmu(keyword: String): List<com.omnibox.app.models.DanmuSearchItem> = runCatching {
        val r = if (AppSettings.danmu.value.apiBase.isEmpty()) Api.danmuSearch(keyword)
                else Api.danmuSearch(keyword, AppSettings.danmu.value.apiBase)
        r.optJSONArray("list")?.let { arr ->
            (0 until arr.length()).map { com.omnibox.app.models.DanmuSearchItem.from(arr.getJSONObject(it)) }
        } ?: emptyList()
    }.getOrDefault(emptyList())

    suspend fun loadDanmu(id: String): List<DanmuItem> = runCatching {
        val r = if (AppSettings.danmu.value.apiBase.isEmpty()) Api.danmuLoad(id)
                else Api.danmuLoad(id, AppSettings.danmu.value.apiBase)
        r.optJSONArray("list")?.let { arr ->
            (0 until arr.length()).map { DanmuItem.from(arr.getJSONObject(it)) }.sortedBy { it.time }
        } ?: emptyList()
    }.getOrDefault(emptyList())

    fun clearDetail() { _detail.value = null; _error.value = null }
}

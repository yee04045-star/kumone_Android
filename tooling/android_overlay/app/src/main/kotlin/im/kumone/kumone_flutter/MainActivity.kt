package im.kumone.kumone_flutter

import android.graphics.Color
import android.graphics.LinearGradient
import android.graphics.RadialGradient
import android.graphics.Shader
import android.graphics.Paint
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import android.webkit.CookieManager
import android.os.Build
import android.view.View
import android.view.ViewGroup
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.media.AudioAttributes
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.media.AudioDeviceCallback
import com.ryanheise.just_audio.KumoneUsbExclusiveController
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.BufferedReader
import java.io.InputStreamReader
import java.net.HttpURLConnection
import java.net.URL
import java.net.URLEncoder
import java.nio.charset.StandardCharsets
import org.json.JSONObject

/**
 * Android host for system media + a very small QR cookie recovery bridge.
 * Dart owns the QR state machine. Native is only used after a 803 success when
 * the Dart/Dio response did not expose MUSIC_U/Set-Cookie.
 */
open class MainActivity : AudioServiceActivity() {
    companion object {
        private const val CHANNEL = "im.kumone.netease/login"
        private const val USB_CHANNEL = "im.kumone.audio/usb"
        private const val SYSTEM_UI_CHANNEL = "im.kumone/system_ui"
    }

    private val audioManager by lazy { getSystemService(AUDIO_SERVICE) as AudioManager }
    private var nowPlayingStatusBarView: StatusBarBackdropView? = null

    private val usbAudioDeviceCallback = object : AudioDeviceCallback() {
        override fun onAudioDevicesAdded(addedDevices: Array<AudioDeviceInfo>) {
            super.onAudioDevicesAdded(addedDevices)
            applyPersistedUsbExclusive()
        }

        override fun onAudioDevicesRemoved(removedDevices: Array<AudioDeviceInfo>) {
            super.onAudioDevicesRemoved(removedDevices)
            applyPersistedUsbExclusive()
        }
    }


    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        setTheme(AppIconManager(this).theme())
        if (Build.VERSION.SDK_INT >= 31) {
            splashScreen.setOnExitAnimationListener { splash ->
                val reduceMotion = android.provider.Settings.Global.getFloat(
                    contentResolver, android.provider.Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
                if (reduceMotion) {
                    splash.remove()
                } else {
                    // Android may omit the icon view; still fade the splash
                    // container and always remove it when the animation ends.
                    splash.iconView?.let { icon ->
                        icon.animate().scaleX(1.08f).scaleY(1.08f)
                            .alpha(0f).setDuration(220L).start()
                    }
                    splash.animate().alpha(0f).setDuration(240L)
                        .withEndAction { splash.remove() }.start()
                }
            }
        }
        super.onCreate(savedInstanceState)
        // The whole app draws edge-to-edge so an extended background (and the
        // player's own backdrop) can reach the status bar. Individual routes
        // pick the bar tint and icon contrast through Flutter's
        // SystemUiOverlayStyle.
        enableEdgeToEdgeChrome()
        if (Build.VERSION.SDK_INT >= 34) {
            audioManager.registerAudioDeviceCallback(usbAudioDeviceCallback, null)
            window.decorView.post { applyPersistedUsbExclusive() }
        }
    }


    override fun onResume() {
        super.onResume()
        if (Build.VERSION.SDK_INT >= 34) {
            window.decorView.post { applyPersistedUsbExclusive() }
        }
    }

    override fun onDestroy() {
        if (Build.VERSION.SDK_INT >= 34) {
            runCatching { audioManager.unregisterAudioDeviceCallback(usbAudioDeviceCallback) }
        }
        super.onDestroy()
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        val icons = AppIconManager(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "im.kumone/app_icon")
            .setMethodCallHandler { call, result -> icons.handle(call, result) }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "captureQrCookies" -> {
                        val key = call.argument<String>("key")?.trim()
                        if (key.isNullOrEmpty()) {
                            result.error("BAD_KEY", "二维码 key 为空", null)
                            return@setMethodCallHandler
                        }
                        val suppliedCookies = mutableMapOf<String, String>()
                        val incoming = call.argument<Map<*, *>>("cookies")
                        incoming?.forEach { (k, v) ->
                            if (k != null && v != null) suppliedCookies[k.toString()] = v.toString()
                        }
                        Thread {
                            try {
                                var payload = requestQrCheck(key, suppliedCookies)
                                val firstCookies = payload["cookies"] as? Map<*, *>
                                val hasMusicU = firstCookies?.keys?.any { it?.toString() == "MUSIC_U" } == true
                                val code = (payload["code"] as? Number)?.toInt() ?: -1
                                if (code == 803 && !hasMusicU) {
                                    Thread.sleep(320L)
                                    val retry = requestQrCheck(key, suppliedCookies)
                                    val merged = linkedMapOf<String, String>()
                                    if (firstCookies != null) {
                                        firstCookies.forEach { (k, v) ->
                                            if (k != null && v != null) merged[k.toString()] = v.toString()
                                        }
                                    }
                                    val retryCookies = retry["cookies"] as? Map<*, *>
                                    retryCookies?.forEach { (k, v) ->
                                        if (k != null && v != null) merged[k.toString()] = v.toString()
                                    }
                                    payload = mapOf(
                                        "code" to ((retry["code"] as? Number)?.toInt() ?: code),
                                        "cookies" to merged,
                                    )
                                }
                                runOnUiThread { result.success(payload) }
                            } catch (t: Throwable) {
                                runOnUiThread {
                                    result.error("QR_COOKIE", t.message ?: "二维码 Cookie 捕获失败", null)
                                }
                            }
                        }.start()
                    }
                    "getAntiCheatToken" -> {
                        val incoming = call.argument<Map<*, *>>("cookies")
                        val cookies = mutableMapOf<String, String>()
                        incoming?.forEach { (k, v) ->
                            if (k != null && v != null) cookies[k.toString()] = v.toString()
                        }
                        fetchAntiCheatToken(cookies, result)
                    }
                    "subscribePlaylistInWebView" -> {
                        val id = call.argument<Number>("id")?.toLong() ?: 0L
                        val subscribe = call.argument<Boolean>("subscribe") ?: true
                        val incoming = call.argument<Map<*, *>>("cookies")
                        if (id <= 0L) {
                            result.error("BAD_PLAYLIST", "歌单 ID 无效", null)
                            return@setMethodCallHandler
                        }
                        val cookies = mutableMapOf<String, String>()
                        incoming?.forEach { (k, v) ->
                            if (k != null && v != null) cookies[k.toString()] = v.toString()
                        }
                        subscribePlaylistInWebView(id.toString(), subscribe, cookies, result)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_UI_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "enterNowPlaying" -> {
                        val darkIcons = call.argument<Boolean>("darkIcons") ?: false
                        val primaryColor =
                            (call.argument<Number>("primaryColor")?.toInt())
                                ?: Color.rgb(41, 41, 51)
                        val secondaryColor =
                            (call.argument<Number>("secondaryColor")?.toInt())
                                ?: Color.rgb(23, 23, 31)
                        enterNowPlayingSystemBars(
                            darkIcons,
                            primaryColor,
                            secondaryColor,
                        )
                        result.success(null)
                    }
                    "exitNowPlaying" -> {
                        val backgroundColor =
                            (call.argument<Number>("backgroundColor")?.toInt())
                                ?: Color.BLACK
                        val darkIcons = call.argument<Boolean>("darkIcons") ?: false
                        exitNowPlayingSystemBars(backgroundColor, darkIcons)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, USB_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "setUsbExclusive" -> {
                        val enabled = call.argument<Boolean>("enabled") ?: false
                        runCatching { setUsbExclusive(enabled) }
                            .onSuccess { result.success(it) }
                            .onFailure {
                                result.success(
                                    mapOf(
                                        "applied" to false,
                                        "message" to (it.message ?: "USB 独占设置失败"),
                                    ),
                                )
                            }
                    }
                    else -> result.notImplemented()
                }
            }
    }

    private fun enterNowPlayingSystemBars(
        darkIcons: Boolean,
        primaryColor: Int,
        secondaryColor: Int,
    ) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        // The Flutter surface is not reliable as the status-bar background on
        // every Android/OEM combination. Keep the system bar itself transparent
        // and draw a dedicated, non-interactive backdrop inside the window
        // decor. This remains effective on Android 15+, where statusBarColor
        // is ignored, and on Android 14 where edge-to-edge is opt-in.
        window.setDecorFitsSystemWindows(false)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }

        ensureNowPlayingStatusBarView()
        nowPlayingStatusBarView?.setGradientColors(primaryColor, secondaryColor)
        applySystemBarIconAppearance(darkIcons)
    }

    private fun ensureNowPlayingStatusBarView() {
        if (nowPlayingStatusBarView != null) return

        val decor = window.decorView as? ViewGroup ?: return
        val view = StatusBarBackdropView(this)
        view.isClickable = false
        view.isFocusable = false
        view.importantForAccessibility = View.IMPORTANT_FOR_ACCESSIBILITY_NO
        view.elevation = 0f

        val initialHeight = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.decorView.rootWindowInsets
                ?.getInsets(WindowInsets.Type.statusBars())
                ?.top
                ?: 0
        } else {
            resources.getIdentifier("status_bar_height", "dimen", "android")
                .takeIf { it != 0 }
                ?.let { resources.getDimensionPixelSize(it) }
                ?: 0
        }

        val params = ViewGroup.LayoutParams(
            ViewGroup.LayoutParams.MATCH_PARENT,
            initialHeight,
        )
        decor.addView(view, params)

        view.onHeightChanged = { height ->
            val lp = view.layoutParams
            if (lp != null && lp.height != height) {
                lp.height = height
                view.layoutParams = lp
            }
        }
        view.requestApplyInsets()
        nowPlayingStatusBarView = view
    }

    private fun enableEdgeToEdgeChrome() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return
        window.setDecorFitsSystemWindows(false)
        window.addFlags(android.view.WindowManager.LayoutParams.FLAG_DRAWS_SYSTEM_BAR_BACKGROUNDS)
        window.statusBarColor = Color.TRANSPARENT
        window.navigationBarColor = Color.TRANSPARENT
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            window.isStatusBarContrastEnforced = false
            window.isNavigationBarContrastEnforced = false
        }
    }

    private fun exitNowPlayingSystemBars(backgroundColor: Int, darkIcons: Boolean) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return

        // The window stays edge-to-edge for every route (see
        // enableEdgeToEdgeChrome); Android 15/16 enforce that regardless. So
        // leaving the player only drops its gradient backdrop and restores the
        // system-bar icon appearance — the surrounding route's own
        // SystemUiOverlayStyle then decides the bar tint.
        removeNowPlayingStatusBarView()
        applySystemBarIconAppearance(darkIcons)
    }

    private fun removeNowPlayingStatusBarView() {
        nowPlayingStatusBarView?.let { view ->
            (view.parent as? ViewGroup)?.removeView(view)
        }
        nowPlayingStatusBarView = null
    }

    private fun applySystemBarIconAppearance(darkIcons: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val lightAppearance =
                WindowInsetsController.APPEARANCE_LIGHT_STATUS_BARS or
                    WindowInsetsController.APPEARANCE_LIGHT_NAVIGATION_BARS
            val appearance = if (darkIcons) lightAppearance else 0
            window.insetsController?.setSystemBarsAppearance(appearance, lightAppearance)
        } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            var flags = window.decorView.systemUiVisibility
            flags = if (darkIcons) {
                flags or View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR
            } else {
                flags and View.SYSTEM_UI_FLAG_LIGHT_STATUS_BAR.inv()
            }
            window.decorView.systemUiVisibility = flags
        }
    }

    private fun setUsbExclusive(enabled: Boolean): Map<String, Any> {
        if (Build.VERSION.SDK_INT < 34) {
            return mapOf(
                "applied" to false,
                "message" to "独占 USB 需要 Android 14 或更高版本"
            )
        }

        val mediaAttributes = AudioAttributes.Builder()
            .setUsage(AudioAttributes.USAGE_MEDIA)
            .setContentType(AudioAttributes.CONTENT_TYPE_MUSIC)
            .build()

        fun clearSystemMixerPreference() {
            val outputs = audioManager.getDevices(AudioManager.GET_DEVICES_OUTPUTS)
                .filter { device ->
                    device.type == AudioDeviceInfo.TYPE_USB_DEVICE ||
                        device.type == AudioDeviceInfo.TYPE_USB_HEADSET ||
                        device.type == AudioDeviceInfo.TYPE_USB_ACCESSORY
                }
            for (device in outputs) {
                runCatching { audioManager.clearPreferredMixerAttributes(mediaAttributes, device) }
            }
        }

        if (!enabled) {
            KumoneUsbExclusiveController.disable(this)
            clearSystemMixerPreference()
            return mapOf(
                "applied" to true,
                "message" to "独占 USB 已关闭"
            )
        }

        val device = KumoneUsbExclusiveController.findDevice(this)
            ?: return mapOf(
                "applied" to false,
                "message" to "请先连接 USB DAC 或 USB 音频设备"
            )

        // Do not rely on AudioManager MIXER_BEHAVIOR_BIT_PERFECT. On many Android 14/15/16
        // OEM builds (including HyperOS), the HAL does not expose that optional path.
        // The direct engine owns the UAC interface instead. Clear any stale system preference
        // so AudioTrack cannot compete with the userspace USB stream.
        clearSystemMixerPreference()
        KumoneUsbExclusiveController.setEnabled(this, true)

        if (!KumoneUsbExclusiveController.hasPermission(this, device)) {
            KumoneUsbExclusiveController.requestPermission(this, device) { granted ->
                if (granted) {
                    KumoneUsbExclusiveController.setEnabled(this, true)
                    android.util.Log.i("KumoneUsbExclusive", "USB permission granted; direct mode ready")
                } else {
                    KumoneUsbExclusiveController.disable(this)
                    android.util.Log.w("KumoneUsbExclusive", "USB permission denied")
                }
            }
            return mapOf(
                "applied" to true,
                "pendingPermission" to true,
                "message" to "请在系统弹窗中允许访问 USB DAC，允许后将自动使用 USB 直连模式"
            )
        }

        return mapOf(
            "applied" to true,
            "mode" to "native_usb",
            "message" to "独占 USB 已开启（USB 直连模式）",
            "device" to (device.productName ?: "USB Audio Device")
        )
    }

    private fun applyPersistedUsbExclusive() {
        if (Build.VERSION.SDK_INT < 34) return
        val prefs = getSharedPreferences("FlutterSharedPreferences", MODE_PRIVATE)
        val enabled = prefs.getBoolean("flutter.usbExclusive", false)
        if (!enabled) {
            runCatching { KumoneUsbExclusiveController.disable(this) }
            return
        }
        val device = runCatching { KumoneUsbExclusiveController.findDevice(this) }.getOrNull()
        if (device != null && runCatching { KumoneUsbExclusiveController.hasPermission(this, device) }.getOrDefault(false)) {
            runCatching { KumoneUsbExclusiveController.setEnabled(this, true) }
        }
    }

    private fun subscribePlaylistInWebView(
        id: String,
        subscribe: Boolean,
        cookies: Map<String, String>,
        result: MethodChannel.Result,
    ) {
        runOnUiThread {
            val webView = WebView(this)
            val cookieManager = CookieManager.getInstance()
            cookieManager.setAcceptCookie(true)
            cookieManager.setAcceptThirdPartyCookies(webView, true)
            cookies.forEach { (name, value) ->
                if (name.isNotBlank() && value.isNotBlank() && name != "os" && name != "appver") {
                    cookieManager.setCookie(
                        "https://music.163.com/",
                        "$name=${value}; Path=/"
                    )
                }
            }
            cookieManager.flush()

            webView.alpha = 0f
            webView.layoutParams = android.widget.FrameLayout.LayoutParams(1, 1)
            addContentView(webView, webView.layoutParams)
            webView.settings.javaScriptEnabled = true
            webView.settings.domStorageEnabled = true
            webView.settings.databaseEnabled = true

            var finished = false
            fun finish(applied: Boolean, code: Int, message: String, raw: String = "") {
                if (finished) return
                finished = true
                try {
                    webView.stopLoading()
                    webView.removeJavascriptInterface("KumoneBridge")
                    (webView.parent as? android.view.ViewGroup)?.removeView(webView)
                    webView.destroy()
                } catch (_: Throwable) {}
                result.success(
                    mapOf(
                        "applied" to applied,
                        "code" to code,
                        "message" to message,
                        "raw" to raw,
                    )
                )
            }

            class Bridge {
                @JavascriptInterface
                fun response(raw: String?) {
                    runOnUiThread {
                        val text = raw.orEmpty()
                        try {
                            val obj = JSONObject(text)
                            val nested = obj.optJSONObject("data")
                            val code = when {
                                obj.has("code") -> obj.optInt("code", -1)
                                nested?.has("code") == true -> nested.optInt("code", -1)
                                else -> -1
                            }
                            val message = obj.optString(
                                "message",
                                obj.optString("msg", nested?.optString("message", "") ?: ""),
                            )
                            finish(
                                code == 200,
                                code,
                                message.ifBlank {
                                    if (code == 200) "操作成功" else "网页接口返回 code=$code"
                                },
                                text,
                            )
                        } catch (_: Throwable) {
                            // Some NetEase Web responses are JSONP or carry a
                            // short HTML/JS wrapper around the JSON object. Treat
                            // an explicit code=200 as success instead of exposing
                            // the misleading "返回格式异常" message.
                            val normalized = text.replace("\u0000", "").trim()
                            val success = Regex("\"code\"\\s*:\\s*200|(?:^|[?&])code=200(?:&|$)")
                                .containsMatchIn(normalized)
                            if (success) {
                                finish(true, 200, "操作成功", text)
                            } else {
                                finish(false, -1, "网页接口返回格式异常", text)
                            }
                        }
                    }
                }

                @JavascriptInterface
                fun failed(message: String?) {
                    runOnUiThread { finish(false, -1, message ?: "网页端收藏歌单失败") }
                }
            }

            webView.addJavascriptInterface(Bridge(), "KumoneBridge")
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    val t = if (subscribe) 1 else 2
                    val timestamp = System.currentTimeMillis()
                    val csrfToken = cookies["__csrf"]
                        .orEmpty()
                        .replace("\\", "\\\\")
                        .replace("'", "\\'")
                        .replace("\n", "\\n")
                    val js = """
                        (async function(){
                          if (window.__kumonePlaylistMutationStarted) return;
                          window.__kumonePlaylistMutationStarted = true;
                          try {
                            const body = new URLSearchParams({
                              id: '$id',
                              t: '$t',
                              timestamp: '$timestamp',
                              csrf_token: '$csrfToken'
                            }).toString();
                            let r = await fetch('/api/playlist/subscribe', {
                              method: 'POST',
                              credentials: 'include',
                              headers: {
                                'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
                                'X-Requested-With': 'XMLHttpRequest'
                              },
                              body: body
                            });
                            let text = await r.text();
                            // NetEase may answer this web endpoint with an empty
                            // body (or a non-JSON wrapper) even though the POST
                            // itself succeeded. Normalize the transport result
                            // to the small JSON contract expected by Flutter.
                            try {
                              const json = JSON.parse(text);
                              KumoneBridge.response(JSON.stringify({
                                code: typeof json.code === 'number' ? json.code : (r.ok ? 200 : r.status),
                                message: json.message || json.msg || (r.ok ? '操作成功' : '网页接口请求失败'),
                              }));
                            } catch (_) {
                              if (r.ok && text.trim().indexOf('<html') < 0 && text.trim().indexOf('<!DOCTYPE') < 0) {
                                KumoneBridge.response(JSON.stringify({code: 200, message: '操作成功'}));
                              } else {
                                KumoneBridge.response(JSON.stringify({code: r.status, message: '网页接口请求失败'}));
                              }
                            }
                          } catch(e) {
                            KumoneBridge.failed(String(e));
                          }
                        })();
                    """.trimIndent()
                    view.evaluateJavascript(js, null)
                }
            }

            webView.loadUrl("https://music.163.com/playlist?id=$id")
            webView.postDelayed({
                finish(false, -1, "网页端收藏歌单超时")
            }, 15000L)
        }
    }

    private fun fetchAntiCheatToken(
        cookies: Map<String, String>,
        result: MethodChannel.Result,
    ) {
        runOnUiThread {
            val webView = WebView(this)
            val cookieManager = CookieManager.getInstance()
            cookieManager.setAcceptCookie(true)
            cookieManager.setAcceptThirdPartyCookies(webView, true)
            cookies.forEach { (name, value) ->
                if (name.isNotBlank() && value.isNotBlank() && name != "os" && name != "appver") {
                    cookieManager.setCookie(
                        "https://music.163.com/",
                        "$name=$value; Path=/"
                    )
                }
            }
            cookieManager.flush()
            // Keep the WebView attached but visually inert so Android continues
            // to execute page JavaScript even though this is a background token
            // bridge rather than a user-facing browser.
            webView.alpha = 0f
            webView.layoutParams = android.widget.FrameLayout.LayoutParams(1, 1)
            addContentView(webView, webView.layoutParams)
            webView.settings.javaScriptEnabled = true
            webView.settings.domStorageEnabled = true
            webView.settings.databaseEnabled = true

            var finished = false
            fun finish(token: String?, error: String? = null) {
                if (finished) return
                finished = true
                try {
                    webView.stopLoading()
                    webView.removeJavascriptInterface("KumoneBridge")
                    (webView.parent as? android.view.ViewGroup)?.removeView(webView)
                    webView.destroy()
                } catch (_: Throwable) {}
                if (error != null) result.error("ANTI_CHEAT", error, null)
                else result.success(token ?: "")
            }

            class Bridge {
                @JavascriptInterface
                fun token(value: String?) {
                    runOnUiThread { finish(value ?: "") }
                }
                @JavascriptInterface
                fun failed(value: String?) {
                    runOnUiThread { finish("", value ?: "Watchman 初始化失败") }
                }
            }

            webView.addJavascriptInterface(Bridge(), "KumoneBridge")
            webView.webViewClient = object : WebViewClient() {
                override fun onPageFinished(view: WebView, url: String) {
                    val js = """
                        (function(){
                          if (window.__kumoneWatchmanStarted) return;
                          window.__kumoneWatchmanStarted = true;
                          try {
                            var s = document.createElement('script');
                            s.src = 'https://acstatic-dun.126.net/tool.min.js';
                            s.onload = function(){
                              try {
                                if (!window.initWatchman) {
                                  KumoneBridge.failed('Watchman SDK 未提供 initWatchman');
                                  return;
                                }
                                window.initWatchman({
                                  auto: true,
                                  productNumber: 'YD00000558929251',
                                  onload: function(instance){
                                    try {
                                      var raw = instance.getInstance();
                                      var afterReady = function(){
                                        try {
                                          instance.getToken('bd5d2f973ef74cd2a61325a412ae54d9', function(tk){
                                            KumoneBridge.token(String(tk || ''));
                                          });
                                        } catch(e){ KumoneBridge.failed(String(e)); }
                                      };
                                      if (raw && raw.I) {
                                        var settled = false;
                                        var timer = setTimeout(function(){ if(!settled){ settled=true; afterReady(); } }, 12000);
                                        raw.I(function(){ if(!settled){ settled=true; clearTimeout(timer); afterReady(); } });
                                      } else {
                                        afterReady();
                                      }
                                    } catch(e){ KumoneBridge.failed(String(e)); }
                                  },
                                  onerror: function(){ KumoneBridge.failed('Watchman 初始化失败'); }
                                });
                              } catch(e){ KumoneBridge.failed(String(e)); }
                            };
                            s.onerror = function(){ KumoneBridge.failed('Watchman SDK 下载失败'); };
                            document.head.appendChild(s);
                          } catch(e){ KumoneBridge.failed(String(e)); }
                        })();
                    """.trimIndent()
                    view.evaluateJavascript(js, null)
                }
            }

            webView.loadUrl("https://music.163.com/")

            webView.postDelayed({ finish("", "获取反作弊 Token 超时") }, 20000L)
        }
    }

    private fun requestQrCheck(
        key: String,
        cookies: Map<String, String>,
    ): Map<String, Any> {
        val encoded = URLEncoder.encode(key, "UTF-8")
        val url = URL(
            "https://music.163.com/api/login/qr/check?key=$encoded&_=${System.currentTimeMillis()}"
        )
        val conn = (url.openConnection() as HttpURLConnection).apply {
            requestMethod = "GET"
            connectTimeout = 8000
            readTimeout = 8000
            instanceFollowRedirects = false
            setRequestProperty(
                "User-Agent",
                "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 Chrome/125 Mobile Safari/537.36"
            )
            setRequestProperty("Referer", "https://music.163.com/")
            setRequestProperty("Accept", "application/json, text/plain, */*")
            setRequestProperty("Cache-Control", "no-cache")
            if (cookies.isNotEmpty()) {
                setRequestProperty(
                    "Cookie",
                    cookies.entries.joinToString("; ") { "${it.key}=${it.value}" }
                )
            }
        }
        try {
            val headerCookies = parseSetCookies(conn.headerFields)
            val stream = if (conn.responseCode in 200..499) conn.inputStream else conn.errorStream
            val body = stream?.use { input ->
                BufferedReader(InputStreamReader(input, StandardCharsets.UTF_8)).readText()
            }.orEmpty()
            val bodyCookies = parseBodyCookie(body)
            val merged = linkedMapOf<String, String>()
            merged.putAll(bodyCookies)
            merged.putAll(headerCookies)
            return mapOf(
                "code" to parseCode(body),
                "cookies" to merged,
            )
        } finally {
            conn.disconnect()
        }
    }

    private fun parseSetCookies(fields: Map<String?, List<String>?>?): Map<String, String> {
        val out = linkedMapOf<String, String>()
        for ((name, values) in fields.orEmpty()) {
            if (!name.equals("Set-Cookie", ignoreCase = true)) continue
            for (line in values.orEmpty()) {
                val first = line.substringBefore(';').trim()
                val eq = first.indexOf('=')
                if (eq <= 0) continue
                val key = first.substring(0, eq).trim()
                val value = first.substring(eq + 1).trim()
                if (key.isNotEmpty() && value.isNotEmpty()) out[key] = value
            }
        }
        return out
    }

    private fun parseBodyCookie(body: String): Map<String, String> {
        val regex = Regex("\"cookie\"\\s*:\\s*\"([^\"]+)\"")
        val out = linkedMapOf<String, String>()
        for (match in regex.findAll(body)) {
            for (part in match.groupValues[1].split(";;", ";")) {
                val first = part.trim().substringBefore(';').trim()
                val eq = first.indexOf('=')
                if (eq <= 0) continue
                val key = first.substring(0, eq).trim()
                val value = first.substring(eq + 1).trim()
                if (key.isNotEmpty() && value.isNotEmpty()) out[key] = value
            }
        }
        return out
    }

    private fun parseCode(body: String): Int {
        val match = Regex("\\\"code\\\"\\s*:\\s*(\\d+)").find(body)
        return match?.groupValues?.getOrNull(1)?.toIntOrNull() ?: -1
    }
}

/**
 * Draws the same artwork-derived backdrop used by the Flutter player behind
 * the Android status bar. It intentionally draws only in the status-bar inset
 * and never consumes touch or window insets.
 */
private class StatusBarBackdropView(context: android.content.Context) : View(context) {
    private val paint = Paint(Paint.ANTI_ALIAS_FLAG or Paint.DITHER_FLAG)
    private var primaryColor = Color.rgb(41, 41, 51)
    private var secondaryColor = Color.rgb(23, 23, 31)
    var onHeightChanged: ((Int) -> Unit)? = null

    init {
        setWillNotDraw(false)
        isClickable = false
        isFocusable = false
    }

    fun setGradientColors(primary: Int, secondary: Int) {
        if (primaryColor == primary && secondaryColor == secondary) return
        primaryColor = primary
        secondaryColor = secondary
        invalidate()
    }

    override fun onApplyWindowInsets(insets: WindowInsets): WindowInsets {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            onHeightChanged?.invoke(insets.getInsets(WindowInsets.Type.statusBars()).top)
        } else {
            onHeightChanged?.invoke(insets.systemWindowInsetTop)
        }
        return insets
    }

    override fun onDraw(canvas: android.graphics.Canvas) {
        super.onDraw(canvas)
        if (width <= 0 || height <= 0) return

        val rect = android.graphics.RectF(0f, 0f, width.toFloat(), height.toFloat())
        val rootWidth = rootView.width.coerceAtLeast(width).toFloat()
        val rootHeight = rootView.height.coerceAtLeast(height).toFloat()

        // Match the Flutter player's top-left -> bottom-right backdrop
        // gradient in screen coordinates, while only painting the status-bar
        // inset itself.
        paint.shader = LinearGradient(
            0f,
            0f,
            rootWidth,
            rootHeight,
            primaryColor,
            secondaryColor,
            Shader.TileMode.CLAMP,
        )
        paint.alpha = 255
        canvas.drawRect(rect, paint)

        // Match the subtle white highlight used by _ArtworkBackdrop.
        paint.shader = RadialGradient(
            0f,
            0f,
            (mathMax(rootWidth, rootHeight) * .95f),
            Color.argb(31, 255, 255, 255),
            Color.TRANSPARENT,
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(rect, paint)

        // Match the page-wide darkening gradient near the bottom. The status
        // bar is very short, so only the appropriate top slice is visible.
        paint.shader = LinearGradient(
            0f,
            0f,
            0f,
            rootHeight,
            Color.TRANSPARENT,
            Color.argb(89, 0, 0, 0),
            Shader.TileMode.CLAMP,
        )
        canvas.drawRect(rect, paint)

        paint.shader = null
    }

    private fun mathMax(a: Float, b: Float): Float = if (a > b) a else b
}

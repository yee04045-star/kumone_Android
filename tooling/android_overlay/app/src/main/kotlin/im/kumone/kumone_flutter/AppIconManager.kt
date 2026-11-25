package im.kumone.kumone_flutter

import android.app.Activity
import android.content.ComponentName
import android.content.pm.PackageManager
import android.os.Build
import io.flutter.plugin.common.MethodChannel

/** One preference controls launcher aliases and the launch theme. */
class AppIconManager(private val activity: Activity) {
    private val keys = listOf("red")
    private val prefs = activity.getSharedPreferences("kumone_icon", 0)

    fun selected(): String = prefs.getString("selected", "red")
        ?.takeIf { it in keys } ?: "red"

    fun theme(): Int = when (selected()) {
        else -> R.style.LaunchRed
    }

    private fun component(key: String): ComponentName = ComponentName(
        activity.packageName,
        "${activity.packageName}.Icon${key.replaceFirstChar { it.uppercaseChar() }}"
    )

    fun handle(call: io.flutter.plugin.common.MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "getIcon" -> result.success(selected())
            "setIcon" -> {
                val key = call.argument<String>("icon")
                if (key !in keys) {
                    result.error("BAD_ICON", "未知图标", null)
                    return
                }
                try {
                    val pm = activity.packageManager
                    val chosen = key!!
                    if (Build.VERSION.SDK_INT >= 33) {
                        // Atomic update avoids a temporary missing/duplicate launcher entry.
                        pm.setComponentEnabledSettings(keys.map {
                            PackageManager.ComponentEnabledSetting(
                                component(it),
                                if (it == chosen) PackageManager.COMPONENT_ENABLED_STATE_ENABLED
                                else PackageManager.COMPONENT_ENABLED_STATE_DISABLED,
                                PackageManager.DONT_KILL_APP
                            )
                        })
                    } else {
                        // Enable first so an exception never leaves the app without an entry.
                        pm.setComponentEnabledSetting(component(chosen),
                            PackageManager.COMPONENT_ENABLED_STATE_ENABLED, PackageManager.DONT_KILL_APP)
                        keys.filter { it != chosen }.forEach {
                            pm.setComponentEnabledSetting(component(it),
                                PackageManager.COMPONENT_ENABLED_STATE_DISABLED, PackageManager.DONT_KILL_APP)
                        }
                    }
                    if (!prefs.edit().putString("selected", chosen).commit()) {
                        throw IllegalStateException("无法保存图标选择")
                    }
                    result.success(null)
                } catch (error: Exception) {
                    result.error("ICON_CHANGE", error.message, null)
                }
            }
            else -> result.notImplemented()
        }
    }
}

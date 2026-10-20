#!/usr/bin/env bash
set -euo pipefail

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${G}[+]${NC} $*"; }
info() { echo -e "${B}[i]${NC} $*"; }
warn() { echo -e "${Y}[!]${NC} $*"; }
step() { echo -e "${C}[→]${NC} $*"; }
die()  { echo -e "${R}[x]${NC} $*" >&2; exit 1; }

# ─── 1. Проверки ───
step "Проверяю окружение…"
command -v java >/dev/null || die "Нужен JDK 17+"
JAVA_VER=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
[[ "$JAVA_VER" -ge 17 ]] || die "Нужен JDK 17+ (у тебя $JAVA_VER)"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  for d in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/local/android-sdk" "/opt/android-sdk"; do
    [[ -d "$d" ]] && { export ANDROID_HOME="$d"; break; }
  done
fi
[[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] || \
  die "ANDROID_HOME не найден"
log "ANDROID_HOME = $ANDROID_HOME | Java $JAVA_VER OK"

# ─── 2. Директории ───
WORK="${MOON_WORK:-$HOME/MoonVPNBuild}"
APP="$WORK/MoonVPN"
step "Рабочая директория: $WORK"
rm -rf "$APP"
mkdir -p "$APP/app/libs" \
         "$APP/app/src/main/java/com/moon/vpn/ui" \
         "$APP/app/src/main/java/com/moon/vpn/vpn" \
         "$APP/app/src/main/res/values" \
         "$APP/app/src/main/res/drawable" \
         "$APP/app/src/main/res/mipmap-anydpi-v26" \
         "$APP/app/src/main/res/mipmap-anydpi"

AAR="$APP/app/libs/libv2ray.aar"
step "Скачиваю libv2ray.aar…"
# Пытаемся скачать с GitHub, если не выходит — с зеркала SourceForge
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://github.com/2dust/AndroidLibXrayLite/releases/latest/download/libv2ray.aar" || \
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://sourceforge.net/projects/androidlibxraylite.mirror/files/latest/download" || \
  die "Не удалось скачать libv2ray.aar"
[[ -s "$AAR" ]] || die "libv2ray.aar пустой"
log "AAR готов ($(du -h "$AAR" | cut -f1))"

# ─── 4. Gradle ───
if ! command -v gradle >/dev/null; then
  GRADLE_VER=8.7
  GH="$WORK/gradle-$GRADLE_VER"
  if [[ ! -d "$GH" ]]; then
    step "Устанавливаю Gradle $GRADLE_VER…"
    curl -fL --progress-bar -o "$WORK/gradle.zip" \
      "https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"
    unzip -q "$WORK/gradle.zip" -d "$WORK"
  fi
  export PATH="$GH/bin:$PATH"
fi
log "Gradle: $(gradle --version | grep '^Gradle' | head -1)"

# ─── 5. Gradle-файлы ───
step "Генерирую Gradle-файлы…"
cat > "$APP/settings.gradle.kts" <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories { google(); mavenCentral() }
}
rootProject.name = "MoonVPN"
include(":app")
EOF

cat > "$APP/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.5.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
}
EOF

cat > "$APP/gradle.properties" <<'EOF'
org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8
android.useAndroidX=true
kotlin.code.style=official
android.nonTransitiveRClass=true
EOF

cat > "$APP/app/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}
android {
    namespace = "com.moon.vpn"
    compileSdk = 34
    defaultConfig {
        applicationId = "com.moon.vpn"
        minSdk = 24
        targetSdk = 34
        versionCode = 1
        versionName = "1.0.0"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging {
        resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}")
        jniLibs.useLegacyPackaging = true
    }
}
dependencies {
    implementation(files("libs/libv2ray.aar"))
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
EOF

# ─── 6. Иконка ───
step "Генерирую иконку Moon…"

cat > "$APP/app/src/main/res/drawable/ic_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#DFE4EC" android:fillType="evenOdd"
        android:pathData="M5,12 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0 Z
                          M10,12 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0 Z"/>
    <path android:fillColor="#DFE4EC"
        android:pathData="M17,5 L17.4,5.6 L18,6 L17.4,6.4 L17,7 L16.6,6.4 L16,6 L16.6,5.6 Z"/>
</vector>
EOF

cat > "$APP/app/src/main/res/drawable/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#080A0E" android:pathData="M0,0 h108 v108 h-108 Z"/>
</vector>
EOF

cat > "$APP/app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
    <background android:drawable="@drawable/ic_launcher_background"/>
    <foreground android:drawable="@drawable/ic_launcher_foreground"/>
</adaptive-icon>
EOF

cat > "$APP/app/src/main/res/mipmap-anydpi/ic_launcher.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#080A0E" android:pathData="M0,0 h24 v24 h-24 Z"/>
    <path android:fillColor="#DFE4EC" android:fillType="evenOdd"
        android:pathData="M5,12 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0 Z
                          M10,12 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0 Z"/>
    <path android:fillColor="#DFE4EC"
        android:pathData="M17,5 L17.4,5.6 L18,6 L17.4,6.4 L17,7 L16.6,6.4 L16,6 L16.6,5.6 Z"/>
</vector>
EOF

cat > "$APP/app/src/main/res/mipmap-anydpi/ic_launcher_round.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="24" android:viewportHeight="24">
    <path android:fillColor="#080A0E" android:pathData="M12,12 m-12,0 a12,12 0 1,0 24,0 a12,12 0 1,0 -24,0 Z"/>
    <path android:fillColor="#DFE4EC" android:fillType="evenOdd"
        android:pathData="M5,12 a7,7 0 1,0 14,0 a7,7 0 1,0 -14,0 Z
                          M10,12 a5,5 0 1,0 10,0 a5,5 0 1,0 -10,0 Z"/>
    <path android:fillColor="#DFE4EC"
        android:pathData="M17,5 L17.4,5.6 L18,6 L17.4,6.4 L17,7 L16.6,6.4 L16,6 L16.6,5.6 Z"/>
</vector>
EOF

cat > "$APP/app/src/main/res/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#080A0E</color>
    <color name="moon_accent">#DFE4EC</color>
</resources>
EOF

cat > "$APP/app/src/main/res/values/styles.xml" <<'EOF'
<resources>
    <style name="Theme.MoonVPN" parent="android:Theme.Material.NoActionBar">
        <item name="android:statusBarColor">#080A0E</item>
        <item name="android:navigationBarColor">#080A0E</item>
        <item name="android:windowLightStatusBar">false</item>
        <item name="android:windowLightNavigationBar">false</item>
    </style>
</resources>
EOF

# ─── 7. AndroidManifest ───
step "Генерирую AndroidManifest.xml…"
cat > "$APP/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">

    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application
        android:allowBackup="false"
        android:icon="@mipmap/ic_launcher"
        android:roundIcon="@mipmap/ic_launcher_round"
        android:label="Moon VPN"
        android:supportsRtl="true"
        android:theme="@style/Theme.MoonVPN">

        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:windowSoftInputMode="adjustResize">
            <intent-filter>
                <action android:name="android.intent.action.MAIN" />
                <category android:name="android.intent.category.LAUNCHER" />
            </intent-filter>
        </activity>

        <service
            android:name=".vpn.MoonVpnService"
            android:exported="false"
            android:foregroundServiceType="specialUse"
            android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter>
                <action android:name="android.net.VpnService" />
            </intent-filter>
            <property
                android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
                android:value="vpn" />
        </service>

        <receiver
            android:name=".BootReceiver"
            android:enabled="true"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
                <action android:name="com.htc.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
EOF

# ─── 8. Kotlin — базовые ───
step "Генерирую Kotlin-код…"
BASE="$APP/app/src/main/java/com/moon/vpn"

cat > "$BASE/MoonTheme.kt" <<'EOF'
package com.moon.vpn

import androidx.compose.ui.graphics.Color

object Moon {
    val Bg = Color(0xFF080A0E)
    val Surface = Color(0xFF11151B)
    val Surface2 = Color(0xFF171C24)
    val Surface3 = Color(0xFF202733)
    val Border = Color(0xFF292F38)
    val Text = Color(0xFFE9EDF3)
    val Muted = Color(0xFFAEB8C7)
    val Dim = Color(0xFF858E9D)
    val Accent = Color(0xFFDFE4EC)
    val Success = Color(0xFF70C398)
    val Warning = Color(0xFFD9B56B)
    val Error = Color(0xFFE47C7C)
}
EOF

cat > "$BASE/XrayNode.kt" <<'EOF'
package com.moon.vpn

data class XrayNode(
    val protocol: String,
    val name: String,
    val host: String,
    val port: Int,
    val rawLink: String
)

data class Subscription(
    val id: String,
    val name: String,
    val url: String,
    val nodes: List<XrayNode>,
    val lastError: String? = null,
    val lastUpdated: Long = 0L
)
EOF

cat > "$BASE/SubscriptionParser.kt" <<'EOF'
package com.moon.vpn

import android.util.Base64
import java.net.URI
import java.net.URLDecoder

object SubscriptionParser {
    fun parseSubscription(body: String): List<XrayNode> {
        val decoded = tryDecodeBase64(body).trim()
        return decoded.lineSequence()
            .map { it.trim() }.filter { it.isNotEmpty() }
            .mapNotNull { parseLink(it) }.toList()
    }
    fun parseLink(link: String): XrayNode? = try {
        when {
            link.startsWith("vless://") -> parseVless(link)
            link.startsWith("trojan://") -> parseTrojan(link)
            link.startsWith("ss://") -> parseShadowsocks(link)
            link.startsWith("vmess://") -> parseVmess(link)
            else -> null
        }
    } catch (_: Exception) { null }
    private fun parseVless(link: String): XrayNode? {
        val uri = URI(link); val host = uri.host ?: return null
        val port = if (uri.port > 0) uri.port else 443
        val name = uri.fragment?.let { decode(it) } ?: "$host:$port"
        return XrayNode("vless", name, host, port, link)
    }
    private fun parseTrojan(link: String): XrayNode? {
        val uri = URI(link); val host = uri.host ?: return null
        val port = if (uri.port > 0) uri.port else 443
        val name = uri.fragment?.let { decode(it) } ?: "$host:$port"
        return XrayNode("trojan", name, host, port, link)
    }
    private fun parseShadowsocks(link: String): XrayNode? {
        val raw = link.removePrefix("ss://")
        val withoutFragment = raw.substringBefore("#")
        val fragment = raw.substringAfter("#", "")
        val hostPort = withoutFragment.substringAfter("@", withoutFragment)
        val host = hostPort.substringBefore(":").ifBlank { return null }
        val port = hostPort.substringAfter(":").toIntOrNull() ?: 8388
        val name = if (fragment.isNotBlank()) decode(fragment) else "$host:$port"
        return XrayNode("shadowsocks", name, host, port, link)
    }
    private fun parseVmess(link: String): XrayNode? {
        val payload = link.removePrefix("vmess://")
        val json = String(Base64.decode(payload, Base64.DEFAULT))
        val host = Regex("\"add\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: return null
        val port = Regex("\"port\"\\s*:\\s*\"?(\\d+)\"?").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 443
        val name = Regex("\"ps\"\\s*:\\s*\"([^\"]*)\"").find(json)?.groupValues?.get(1) ?: "$host:$port"
        return XrayNode("vmess", name, host, port, link)
    }
    private fun tryDecodeBase64(text: String): String = try {
        String(Base64.decode(text.replace("\n", "").replace("\r", "").trim(), Base64.DEFAULT))
    } catch (_: Exception) { text }
    private fun decode(s: String): String = URLDecoder.decode(s, "UTF-8")
}
EOF

cat > "$BASE/SubscriptionFetcher.kt" <<'EOF'
package com.moon.vpn

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit

object SubscriptionFetcher {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()
    suspend fun fetch(url: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url(url)
                .header("User-Agent", "MoonVPN/1.0").build()
            client.newCall(req).execute().use { r ->
                if (!r.isSuccessful) Result.failure(Exception("HTTP ${r.code}"))
                else {
                    val body = r.body?.string()
                    if (body.isNullOrBlank()) Result.failure(Exception("Пустой ответ"))
                    else Result.success(body)
                }
            }
        } catch (e: Exception) { Result.failure(e) }
    }
}
EOF

cat > "$BASE/SubscriptionStore.kt" <<'EOF'
package com.moon.vpn

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject

object SubscriptionStore {
    private const val PREFS = "moon_vpn_prefs"
    private const val KEY_SUBS = "subscriptions"
    private const val KEY_SELECTED = "selected_node"
    private const val KEY_ACTIVE_CONFIG = "active_config"

    fun load(context: Context): List<Subscription> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SUBS, null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw)
            (0 until arr.length()).map { i -> parseSub(arr.getJSONObject(i)) }
        } catch (_: Exception) { emptyList() }
    }
    fun save(context: Context, subs: List<Subscription>) {
        val arr = JSONArray(); subs.forEach { arr.put(toJson(it)) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_SUBS, arr.toString()).apply()
    }
    fun saveSelected(context: Context, node: XrayNode?) {
        val obj = node?.let {
            JSONObject().apply {
                put("protocol", it.protocol); put("name", it.name)
                put("host", it.host); put("port", it.port); put("rawLink", it.rawLink)
            }
        }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_SELECTED, obj?.toString()).apply()
    }
    fun loadSelected(context: Context): XrayNode? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_SELECTED, null) ?: return null
        return try {
            val o = JSONObject(raw)
            XrayNode(o.getString("protocol"), o.getString("name"),
                     o.getString("host"), o.getInt("port"), o.getString("rawLink"))
        } catch (_: Exception) { null }
    }
    fun loadBool(context: Context, key: String, def: Boolean) =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(key, def)
    fun saveBool(context: Context, key: String, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putBoolean(key, value).apply()
    }
    fun saveActiveConfig(context: Context, config: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().putString(KEY_ACTIVE_CONFIG, config).apply()
    }
    fun loadActiveConfig(context: Context): String? =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getString(KEY_ACTIVE_CONFIG, null)
    fun clearActiveConfig(context: Context) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit().remove(KEY_ACTIVE_CONFIG).apply()
    }
    fun saveLastReconnect(context: Context, reason: String) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit()
            .putLong("last_reconnect_ts", System.currentTimeMillis())
            .putString("last_reconnect_reason", reason).apply()
    }
    fun loadLastReconnect(context: Context): Pair<Long, String?> {
        val p = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
        return p.getLong("last_reconnect_ts", 0L) to p.getString("last_reconnect_reason", null)
    }
    private fun toJson(s: Subscription): JSONObject = JSONObject().apply {
        put("id", s.id); put("name", s.name); put("url", s.url)
        put("lastError", s.lastError ?: JSONObject.NULL)
        put("lastUpdated", s.lastUpdated)
        val arr = JSONArray()
        s.nodes.forEach { n ->
            arr.put(JSONObject().apply {
                put("protocol", n.protocol); put("name", n.name)
                put("host", n.host); put("port", n.port); put("rawLink", n.rawLink)
            })
        }
        put("nodes", arr)
    }
    private fun parseSub(o: JSONObject): Subscription {
        val na = o.optJSONArray("nodes") ?: JSONArray()
        val nodes = (0 until na.length()).map { i ->
            val n = na.getJSONObject(i)
            XrayNode(n.getString("protocol"), n.getString("name"),
                     n.getString("host"), n.getInt("port"), n.getString("rawLink"))
        }
        return Subscription(
            id = o.getString("id"), name = o.getString("name"), url = o.getString("url"),
            nodes = nodes,
            lastError = if (o.isNull("lastError")) null else o.getString("lastError"),
            lastUpdated = o.optLong("lastUpdated", 0L))
    }
}
EOF

cat > "$BASE/XrayConfigBuilder.kt" <<'EOF'
package com.moon.vpn

import android.util.Base64
import org.json.JSONObject

object XrayConfigBuilder {
    fun build(node: XrayNode): String {
        val outbound = when (node.protocol) {
            "vless" -> vlessOutbound(node)
            "trojan" -> trojanOutbound(node)
            "shadowsocks" -> ssOutbound(node)
            "vmess" -> vmessOutbound(node)
            else -> throw IllegalArgumentException("Неподдерживаемый протокол: ${node.protocol}")
        }
        val config = JSONObject().apply {
            put("log", JSONObject().put("loglevel", "warning"))
            put("inbounds", org.json.JSONArray().put(JSONObject().apply {
                put("tag", "tun-in")
                put("protocol", "tun")
                put("settings", JSONObject().apply {
                    put("name", "tun0")
                    put("MTU", 1500)
                    put("autoSystemRoutingTable", org.json.JSONArray().put("0.0.0.0/0").put("::/0"))
                })
            }))
            put("outbounds", org.json.JSONArray().put(outbound))
        }
        return config.toString(2)
    }
    private fun vlessOutbound(node: XrayNode): JSONObject {
        val uri = java.net.URI(node.rawLink)
        val uuid = uri.userInfo ?: throw IllegalArgumentException("VLESS: нет UUID")
        val params = uri.query?.split("&")?.associate {
            val p = it.split("=", limit = 2); p[0] to (p.getOrNull(1) ?: "")
        } ?: emptyMap()
        val stream = JSONObject().apply {
            put("network", params["type"] ?: "tcp")
            put("security", params["security"] ?: "none")
            if (params["security"] == "tls" || params["security"] == "reality") {
                put("tlsSettings", JSONObject().apply {
                    put("serverName", params["sni"] ?: node.host)
                    params["fp"]?.let { put("fingerprint", it) }
                })
            }
            if (params["type"] == "ws") {
                put("wsSettings", JSONObject().apply {
                    put("path", params["path"] ?: "/")
                    params["host"]?.let { put("headers", JSONObject().put("Host", it)) }
                })
            }
            if (params["type"] == "grpc") {
                put("grpcSettings", JSONObject().put("serviceName", params["serviceName"] ?: ""))
            }
        }
        return JSONObject().apply {
            put("protocol", "vless")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port)
                put("users", org.json.JSONArray().put(JSONObject().apply {
                    put("id", uuid); put("encryption", "none")
                    if (params["flow"].orEmpty().isNotEmpty()) put("flow", params["flow"])
                }))
            })))
            put("streamSettings", stream)
        }
    }
    private fun trojanOutbound(node: XrayNode): JSONObject {
        val password = java.net.URI(node.rawLink).userInfo
            ?: throw IllegalArgumentException("Trojan: нет пароля")
        return JSONObject().apply {
            put("protocol", "trojan")
            put("settings", JSONObject().put("servers", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port); put("password", password)
            })))
            put("streamSettings", JSONObject().apply {
                put("security", "tls")
                put("tlsSettings", JSONObject().put("serverName", node.host))
            })
        }
    }
    private fun ssOutbound(node: XrayNode): JSONObject {
        val raw = node.rawLink.removePrefix("ss://").substringBefore("@")
        val decoded = try { String(Base64.decode(raw, Base64.DEFAULT)) } catch (_: Exception) { raw }
        val method = decoded.substringBefore(":")
        val password = decoded.substringAfter(":")
        return JSONObject().apply {
            put("protocol", "shadowsocks")
            put("settings", JSONObject().put("servers", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port)
                put("method", method); put("password", password)
            })))
        }
    }
    private fun vmessOutbound(node: XrayNode): JSONObject {
        val payload = node.rawLink.removePrefix("vmess://")
        val json = String(Base64.decode(payload, Base64.DEFAULT))
        val uuid = Regex("\"id\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1)
            ?: throw IllegalArgumentException("VMess: нет id")
        return JSONObject().apply {
            put("protocol", "vmess")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port)
                put("users", org.json.JSONArray().put(JSONObject().apply {
                    put("id", uuid); put("alterId", 0)
                }))
            })))
        }
    }
}
EOF

cat > "$BASE/AppState.kt" <<'EOF'
package com.moon.vpn

import android.content.Context
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

enum class ConnState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, ERROR }

class AppState(private val ctx: Context) {
    var screen by mutableStateOf("home")
    var subscriptions by mutableStateOf<List<Subscription>>(emptyList())
    var selectedNode by mutableStateOf<XrayNode?>(null)
    var conn by mutableStateOf(ConnState.DISCONNECTED)
    var error by mutableStateOf<String?>(null)
    var sessionSeconds by mutableStateOf(0L)
    var connectStartMs by mutableStateOf(0L)
    var autoConnect by mutableStateOf(SubscriptionStore.loadBool(ctx, "auto_connect", true))
    var killSwitch by mutableStateOf(SubscriptionStore.loadBool(ctx, "kill_switch", true))
    var notifications by mutableStateOf(SubscriptionStore.loadBool(ctx, "notifications", false))
    var lastReconnectTs by mutableStateOf(0L)
    var lastReconnectReason by mutableStateOf<String?>(null)

    fun init() {
        subscriptions = SubscriptionStore.load(ctx)
        selectedNode = SubscriptionStore.loadSelected(ctx)
        val (ts, reason) = SubscriptionStore.loadLastReconnect(ctx)
        lastReconnectTs = ts; lastReconnectReason = reason
    }
    fun allNodes(): List<XrayNode> = subscriptions.flatMap { it.nodes }
    fun setSubscriptions(list: List<Subscription>) {
        subscriptions = list; SubscriptionStore.save(ctx, list)
    }
    fun selectNode(n: XrayNode?) {
        selectedNode = n; SubscriptionStore.saveSelected(ctx, n)
    }
    fun setAutoConnect(v: Boolean) { autoConnect = v; SubscriptionStore.saveBool(ctx, "auto_connect", v) }
    fun setKillSwitch(v: Boolean) { killSwitch = v; SubscriptionStore.saveBool(ctx, "kill_switch", v) }
    fun setNotifications(v: Boolean) { notifications = v; SubscriptionStore.saveBool(ctx, "notifications", v) }
}
EOF

# ─── 9. VPN Service ───
cat > "$BASE/vpn/MoonVpnService.kt" <<'EOF'
package com.moon.vpn.vpn

import android.app.*
import android.content.Intent
import android.net.ConnectivityManager
import android.net.Network
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.moon.vpn.MainActivity
import com.moon.vpn.SubscriptionStore
import kotlinx.coroutines.*
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController

class MoonVpnService : VpnService() {
    private var tunFd: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private var running = false
    private var currentConfig: String? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    private var reconnectJob: Job? = null
    private lateinit var cm: ConnectivityManager
    private var netCallback: ConnectivityManager.NetworkCallback? = null

    private val cb = object : CoreCallbackHandler {
        override fun startup(): Int = 0
        override fun shutdown(): Int = 0
        override fun onEmitStatus(code: Int, message: String): Int {
            if (code != 0) sendError("Xray: $message"); return 0
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val cfg = intent.getStringExtra(EXTRA_CONFIG)
                if (cfg.isNullOrBlank()) {
                    sendError("Пустой конфиг"); stopSelf(); return START_NOT_STICKY
                }
                startVpn(cfg)
            }
            ACTION_DISCONNECT -> stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn(cfg: String) {
        if (running) stopVpn()
        startForeground(NOTIF_ID, notif("Подключение…"))
        currentConfig = cfg
        SubscriptionStore.saveActiveConfig(this, cfg)
        tunFd = buildTun()
        if (tunFd == null) { sendError("Не удалось создать TUN"); stopSelf(); return }
        try {
            core = CoreController(cb)
            core?.startLoop(cfg, tunFd!!.fd)
            running = true
            startNetworkMonitor()
            updateNotif("Подключено")
            sendState("CONNECTED")
        } catch (e: Exception) { sendError("Ошибка Xray: ${e.message}"); stopVpn() }
    }

    private fun buildTun(): ParcelFileDescriptor? = Builder()
        .setSession("Moon VPN").setMtu(1500)
        .addAddress("10.255.0.2", 32).addRoute("0.0.0.0", 0)
        .addDnsServer("1.1.1.1").setBlocking(true).establish()

    private fun startNetworkMonitor() {
        stopNetworkMonitor()
        cm = getSystemService(ConnectivityManager::class.java)
        netCallback = object : ConnectivityManager.NetworkCallback() {
            override fun onAvailable(network: Network) = scheduleReconnect("network_available")
            override fun onLost(network: Network) = scheduleReconnect("network_lost")
        }
        try { cm.registerDefaultNetworkCallback(netCallback!!) } catch (_: Exception) {}
    }
    private fun stopNetworkMonitor() {
        netCallback?.let { try { cm.unregisterNetworkCallback(it) } catch (_: Exception) {} }
        netCallback = null
    }
    private fun scheduleReconnect(reason: String) {
        if (!running || currentConfig == null) return
        reconnectJob?.cancel()
        reconnectJob = scope.launch {
            delay(2500)
            if (running) withContext(Dispatchers.Main) { reconnect(reason) }
        }
    }
    private fun reconnect(reason: String) {
        val cfg = currentConfig ?: return
        val fd = tunFd?.fd ?: run { fullRestart(cfg, reason); return }
        sendState("RECONNECTING")
        updateNotif("Переподключение…")
        try { core?.stopLoop() } catch (_: Exception) {}
        core = null
        try {
            core = CoreController(cb)
            core?.startLoop(cfg, fd)
            SubscriptionStore.saveLastReconnect(this, reason)
            updateNotif("Подключено"); sendState("CONNECTED")
        } catch (_: Exception) { fullRestart(cfg, reason) }
    }
    private fun fullRestart(cfg: String, reason: String) {
        try { core?.stopLoop() } catch (_: Exception) {}
        core = null
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        tunFd = buildTun()
        if (tunFd == null) { sendError("Reconnect: TUN failed"); stopVpn(); return }
        try {
            core = CoreController(cb)
            core?.startLoop(cfg, tunFd!!.fd)
            SubscriptionStore.saveLastReconnect(this, reason)
            updateNotif("Подключено"); sendState("CONNECTED")
        } catch (e: Exception) { sendError("Reconnect failed: ${e.message}"); stopVpn() }
    }
    private fun stopVpn() {
        stopNetworkMonitor()
        reconnectJob?.cancel(); reconnectJob = null
        try { core?.stopLoop() } catch (_: Exception) {}
        core = null
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        running = false; currentConfig = null
        SubscriptionStore.clearActiveConfig(this)
        stopForeground(true); stopSelf(); sendState("DISCONNECTED")
    }
    override fun onRevoke() { stopVpn() }
    override fun onDestroy() { stopVpn(); scope.cancel(); super.onDestroy() }

    private fun notif(text: String): Notification {
        val ch = "moon_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java)
                .createNotificationChannel(
                    NotificationChannel(ch, "Moon VPN", NotificationManager.IMPORTANCE_LOW))
        }
        val open = PendingIntent.getActivity(this, 0,
            Intent(this, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val disc = PendingIntent.getService(this, 1,
            Intent(this, MoonVpnService::class.java).apply { action = ACTION_DISCONNECT },
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        return NotificationCompat.Builder(this, ch)
            .setContentTitle("Moon VPN").setContentText(text)
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setOngoing(true).setContentIntent(open)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Отключить", disc)
            .setPriority(NotificationCompat.PRIORITY_LOW).build()
    }
    private fun updateNotif(t: String) {
        getSystemService(NotificationManager::class.java).notify(NOTIF_ID, notif(t))
    }
    private fun sendError(m: String) = sendBroadcast(Intent(ACTION_ERROR).putExtra(EXTRA_ERROR, m))
    private fun sendState(s: String) = sendBroadcast(Intent(ACTION_STATE).putExtra(EXTRA_STATE, s))

    companion object {
        const val ACTION_CONNECT = "com.moon.vpn.CONNECT"
        const val ACTION_DISCONNECT = "com.moon.vpn.DISCONNECT"
        const val ACTION_ERROR = "com.moon.vpn.ERROR"
        const val ACTION_STATE = "com.moon.vpn.STATE"
        const val EXTRA_CONFIG = "cfg"
        const val EXTRA_ERROR = "err"
        const val EXTRA_STATE = "st"
        private const val NOTIF_ID = 1
    }
}
EOF

# ─── 10. BootReceiver ───
cat > "$BASE/BootReceiver.kt" <<'EOF'
package com.moon.vpn

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.net.VpnService
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat
import com.moon.vpn.vpn.MoonVpnService

class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val action = intent.action ?: return
        if (action != Intent.ACTION_BOOT_COMPLETED &&
            action != "android.intent.action.QUICKBOOT_POWERON" &&
            action != "com.htc.intent.action.QUICKBOOT_POWERON") return
        val prefs = context.getSharedPreferences("moon_vpn_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("auto_connect", true)) return
        val node = SubscriptionStore.loadSelected(context) ?: return
        if (VpnService.prepare(context) != null) { showOpenAppNotification(context); return }
        val cfg = try { XrayConfigBuilder.build(node) } catch (_: Exception) { return }
        val svc = Intent(context, MoonVpnService::class.java).apply {
            this.action = MoonVpnService.ACTION_CONNECT
            putExtra(MoonVpnService.EXTRA_CONFIG, cfg)
        }
        try { ContextCompat.startForegroundService(context, svc) }
        catch (_: Exception) { showOpenAppNotification(context) }
    }
    private fun showOpenAppNotification(ctx: Context) {
        val ch = "moon_boot"
        val nm = ctx.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            nm.createNotificationChannel(
                NotificationChannel(ch, "Moon VPN", NotificationManager.IMPORTANCE_DEFAULT))
        }
        val open = PendingIntent.getActivity(ctx, 0,
            Intent(ctx, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        nm.notify(1001, NotificationCompat.Builder(ctx, ch)
            .setContentTitle("Moon VPN")
            .setContentText("Нажмите, чтобы подключить VPN")
            .setSmallIcon(android.R.drawable.ic_lock_lock)
            .setContentIntent(open).setAutoCancel(true).build())
    }
}
EOF

# ─── 11. MainActivity ───
cat > "$BASE/MainActivity.kt" <<'EOF'
package com.moon.vpn

import android.content.*
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import com.moon.vpn.ui.*
import com.moon.vpn.vpn.MoonVpnService
import kotlinx.coroutines.delay

class MainActivity : ComponentActivity() {
    private lateinit var state: AppState
    private val vpnPermLauncher = registerForActivityResult(
        ActivityResultContracts.StartActivityForResult()
    ) { r ->
        if (r.resultCode == RESULT_OK) state.selectedNode?.let { doConnect(it) }
        else { state.error = "Разрешение VPN не выдано"; state.conn = ConnState.ERROR }
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                MoonVpnService.ACTION_ERROR -> {
                    state.error = intent.getStringExtra(MoonVpnService.EXTRA_ERROR)
                    state.conn = ConnState.ERROR
                }
                MoonVpnService.ACTION_STATE -> when (intent.getStringExtra(MoonVpnService.EXTRA_STATE)) {
                    "CONNECTED" -> {
                        if (state.conn != ConnState.RECONNECTING) {
                            state.connectStartMs = System.currentTimeMillis()
                            state.sessionSeconds = 0
                        }
                        state.conn = ConnState.CONNECTED
                    }
                    "RECONNECTING" -> state.conn = ConnState.RECONNECTING
                    "DISCONNECTED" -> { state.conn = ConnState.DISCONNECTED; state.sessionSeconds = 0 }
                }
            }
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        state = AppState(this).also { it.init() }
        ContextCompat.registerReceiver(this, receiver,
            IntentFilter().apply {
                addAction(MoonVpnService.ACTION_ERROR)
                addAction(MoonVpnService.ACTION_STATE)
            }, ContextCompat.RECEIVER_NOT_EXPORTED)
        setContent {
            MaterialTheme(colorScheme = darkColorScheme(background = Moon.Bg, surface = Moon.Surface)) {
                MoonApp(state, ::toggleConnect)
            }
        }
    }
    private fun toggleConnect() {
        when (state.conn) {
            ConnState.CONNECTED, ConnState.CONNECTING, ConnState.RECONNECTING -> disconnect()
            ConnState.DISCONNECTED, ConnState.ERROR -> {
                val node = state.selectedNode ?: state.allNodes().firstOrNull()
                if (node == null) {
                    state.error = "Импортируйте подписку — список пуст"; return
                }
                state.selectNode(node)
                val p = VpnService.prepare(this)
                if (p != null) vpnPermLauncher.launch(p) else doConnect(node)
            }
        }
    }
    private fun doConnect(node: XrayNode) {
        val cfg = try { XrayConfigBuilder.build(node) }
        catch (e: Exception) { state.error = e.message; state.conn = ConnState.ERROR; return }
        state.error = null; state.conn = ConnState.CONNECTING
        val i = Intent(this, MoonVpnService::class.java).apply {
            action = MoonVpnService.ACTION_CONNECT
            putExtra(MoonVpnService.EXTRA_CONFIG, cfg)
        }
        ContextCompat.startForegroundService(this, i)
    }
    private fun disconnect() {
        startService(Intent(this, MoonVpnService::class.java).apply {
            action = MoonVpnService.ACTION_DISCONNECT
        })
    }
    override fun onDestroy() { unregisterReceiver(receiver); super.onDestroy() }
}

@Composable
fun MoonApp(state: AppState, onToggleConnect: () -> Unit) {
    LaunchedEffect(state.conn, state.connectStartMs) {
        if (state.conn == ConnState.CONNECTED) {
            while (true) {
                state.sessionSeconds = (System.currentTimeMillis() - state.connectStartMs) / 1000
                delay(1000)
            }
        }
    }
    Scaffold(containerColor = Moon.Bg,
        bottomBar = { MoonBottomNav(state.screen) { state.screen = it } }) { padding ->
        Box(Modifier.padding(padding).background(Moon.Bg)) {
            when (state.screen) {
                "home" -> HomeScreen(state, onToggleConnect)
                "servers" -> ServersScreen(state)
                "subscriptions" -> SubscriptionsScreen(state)
                "settings" -> SettingsScreen(state)
                "stats" -> StatsScreen(state)
            }
        }
    }
}
EOF

# ─── 12. UI Components ───
cat > "$BASE/ui/Components.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.ConnState
import com.moon.vpn.Moon

@Composable
fun MoonLogo(size: Int = 32) {
    Box(Modifier.size(size.dp).clip(RoundedCornerShape((size * 0.28).dp))
            .background(Moon.Surface2)
            .border(1.dp, Moon.Border, RoundedCornerShape((size * 0.28).dp)),
        contentAlignment = Alignment.Center) {
        Icon(Icons.Default.DarkMode, null, tint = Moon.Accent,
            modifier = Modifier.size((size * 0.6).dp))
    }
}

@Composable
fun MoonBottomNav(current: String, onSelect: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().background(Moon.Surface)
            .border(1.dp, Moon.Border).padding(vertical = 8.dp, horizontal = 8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly) {
        val tabs = listOf(
            "home" to (Icons.Default.Home to "Главная"),
            "servers" to (Icons.Default.Public to "Серверы"),
            "subscriptions" to (Icons.Default.List to "Подписки"),
            "stats" to (Icons.Default.BarChart to "Статистика"))
        tabs.forEach { (id, info) ->
            val active = current == id
            Column(Modifier.clip(RoundedCornerShape(8.dp)).clickable { onSelect(id) }
                    .padding(horizontal = 14.dp, vertical = 8.dp),
                horizontalAlignment = Alignment.CenterHorizontally) {
                Icon(info.first, null, tint = if (active) Moon.Text else Moon.Dim,
                    modifier = Modifier.size(20.dp))
                Spacer(Modifier.height(4.dp))
                Text(info.second, fontSize = 10.sp,
                    color = if (active) Moon.Text else Moon.Dim)
            }
        }
    }
}

@Composable
fun ConnectOrb(state: ConnState, onClick: () -> Unit) {
    val ringColor = when (state) {
        ConnState.CONNECTED -> Moon.Success
        ConnState.CONNECTING, ConnState.RECONNECTING -> Moon.Warning
        ConnState.ERROR -> Moon.Error
        else -> Moon.Border
    }
    Box(Modifier.size(160.dp).clip(CircleShape).background(Moon.Surface)
            .border(2.dp, ringColor, CircleShape).clickable(onClick = onClick),
        contentAlignment = Alignment.Center) {
        Box(Modifier.size(140.dp).clip(CircleShape).background(Color(0xFF0B0D10))
                .border(1.dp, Moon.Border.copy(alpha = 0.6f), CircleShape),
            contentAlignment = Alignment.Center) {
            Icon(Icons.Default.Shield, null, tint = Moon.Text, modifier = Modifier.size(36.dp))
        }
    }
}

@Composable
fun SectionTitle(text: String) {
    Text(text, fontSize = 22.sp, fontWeight = FontWeight.SemiBold,
        color = Moon.Text, modifier = Modifier.padding(bottom = 6.dp))
}

@Composable
fun Subtitle(text: String) {
    Text(text, fontSize = 12.sp, color = Moon.Dim, modifier = Modifier.padding(bottom = 20.dp))
}

@Composable
fun PrimaryButton(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    Button(onClick = onClick, enabled = enabled,
        modifier = Modifier.fillMaxWidth().height(52.dp),
        shape = RoundedCornerShape(13.dp),
        colors = ButtonDefaults.buttonColors(
            containerColor = Moon.Accent, contentColor = Color(0xFF101216),
            disabledContainerColor = Moon.Surface3, disabledContentColor = Moon.Dim)
    ) { Text(text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold) }
}

@Composable
fun SettingRow(icon: androidx.compose.ui.graphics.vector.ImageVector,
               title: String, desc: String, checked: Boolean, onChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(38.dp).clip(RoundedCornerShape(10.dp)).background(Moon.Surface2)
                .border(1.dp, Moon.Border, RoundedCornerShape(10.dp)),
            contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Moon.Muted, modifier = Modifier.size(18.dp))
        }
        Spacer(Modifier.width(12.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 14.sp, color = Moon.Text)
            Text(desc, fontSize = 11.sp, color = Moon.Dim)
        }
        Switch(checked = checked, onCheckedChange = onChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color(0xFF101216),
                checkedTrackColor = Moon.Accent,
                uncheckedThumbColor = Moon.Dim,
                uncheckedTrackColor = Moon.Surface3))
    }
}
EOF

# ─── 13. HomeScreen ───
cat > "$BASE/ui/HomeScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.AppState
import com.moon.vpn.ConnState
import com.moon.vpn.Moon

@Composable
fun HomeScreen(state: AppState, onToggleConnect: () -> Unit) {
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            MoonLogo(36); Spacer(Modifier.width(10.dp))
            Text("Moon", fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text)
            Spacer(Modifier.weight(1f))
            IconButton(onClick = { state.screen = "settings" }) {
                Icon(Icons.Default.Settings, null, tint = Moon.Muted)
            }
        }
        Spacer(Modifier.height(40.dp))
        Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
            ConnectOrb(state.conn, onToggleConnect)
            Spacer(Modifier.height(20.dp))
            val (title, sub) = when (state.conn) {
                ConnState.CONNECTED -> "Подключено" to "Соединение защищено"
                ConnState.CONNECTING -> "Подключение…" to "Устанавливаем туннель"
                ConnState.RECONNECTING -> "Переподключение…" to "Восстанавливаем соединение"
                ConnState.ERROR -> "Ошибка" to (state.error ?: "Проверьте подписку")
                else -> "Не подключён" to "Соединение не защищено VPN"
            }
            Text(title, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text)
            Text(sub, fontSize = 12.sp, color = Moon.Dim)
            Spacer(Modifier.height(28.dp))
            PrimaryButton(
                text = when (state.conn) {
                    ConnState.CONNECTED, ConnState.CONNECTING, ConnState.RECONNECTING -> "Отключить VPN"
                    else -> "Подключить VPN"
                },
                enabled = state.conn != ConnState.CONNECTING ||
                          state.selectedNode != null || state.allNodes().isNotEmpty(),
                onClick = onToggleConnect)
            Spacer(Modifier.height(16.dp))
            val node = state.selectedNode ?: state.allNodes().firstOrNull()
            Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(13.dp))
                    .background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(13.dp))
                    .clickable { state.screen = "servers" }.padding(13.dp),
                verticalAlignment = Alignment.CenterVertically) {
                Box(Modifier.size(36.dp).clip(RoundedCornerShape(10.dp)).background(Moon.Surface2),
                    contentAlignment = Alignment.Center) { Text("🌐", fontSize = 18.sp) }
                Spacer(Modifier.width(10.dp))
                Column(Modifier.weight(1f)) {
                    Text(node?.name ?: "Нет сервера", fontSize = 13.sp,
                        fontWeight = FontWeight.Medium, color = Moon.Text)
                    Text(node?.let { "${it.host}:${it.port}" } ?: "Импортируйте подписку",
                        fontSize = 10.sp, color = Moon.Dim)
                }
            }
            Spacer(Modifier.height(20.dp))
            if (state.conn == ConnState.CONNECTED) {
                Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp),
                    horizontalArrangement = Arrangement.SpaceBetween) {
                    Text("Время сессии", fontSize = 11.sp, color = Moon.Dim)
                    Text(formatTime(state.sessionSeconds), fontSize = 11.sp,
                        color = Moon.Muted, fontWeight = FontWeight.Medium)
                }
            }
        }
    }
}
private fun formatTime(s: Long): String =
    "%02d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
EOF

# ─── 14. ServersScreen ───
cat > "$BASE/ui/ServersScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextFieldDefaults
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.AppState
import com.moon.vpn.Moon
import com.moon.vpn.XrayNode

@Composable
fun ServersScreen(state: AppState) {
    var query by remember { mutableStateOf("") }
    val all = state.allNodes()
    val filtered = if (query.isBlank()) all
    else all.filter { it.name.contains(query, true) || it.host.contains(query, true) || it.protocol.contains(query, true) }
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        SectionTitle("Серверы")
        Subtitle("Выберите быстрый и стабильный маршрут")
        OutlinedTextField(value = query, onValueChange = { query = it },
            placeholder = { Text("Страна, город или код", color = Moon.Dim) },
            modifier = Modifier.fillMaxWidth(), singleLine = true,
            shape = RoundedCornerShape(11.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Moon.Surface, unfocusedContainerColor = Moon.Surface,
                focusedTextColor = Moon.Text, unfocusedTextColor = Moon.Text,
                focusedIndicatorColor = Moon.Border, unfocusedIndicatorColor = Moon.Border))
        Spacer(Modifier.height(10.dp))
        Text("${filtered.size} серверов", fontSize = 11.sp, color = Moon.Dim)
        Spacer(Modifier.height(12.dp))
        if (all.isEmpty()) {
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Нет серверов", fontSize = 15.sp, color = Moon.Text)
                    Text("Импортируйте подписку во вкладке «Подписки»",
                        fontSize = 12.sp, color = Moon.Dim)
                }
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(7.dp)) {
                items(filtered, key = { it.rawLink }) { node ->
                    ServerRow(node, state.selectedNode?.rawLink == node.rawLink) {
                        state.selectNode(node)
                    }
                }
            }
        }
    }
}
@Composable
private fun ServerRow(node: XrayNode, selected: Boolean, onClick: () -> Unit) {
    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
            .background(if (selected) Moon.Surface2 else Moon.Surface)
            .border(1.dp, if (selected) Moon.Muted else Moon.Border, RoundedCornerShape(12.dp))
            .clickable(onClick = onClick).padding(13.dp),
        verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(node.name, fontSize = 13.sp, fontWeight = FontWeight.Medium, color = Moon.Text)
            Text("${node.protocol.uppercase()} · ${node.host}:${node.port}",
                fontSize = 10.sp, color = Moon.Dim)
        }
        if (selected) {
            Box(Modifier.size(20.dp).clip(RoundedCornerShape(50.dp)).background(Moon.Accent),
                contentAlignment = Alignment.Center) {
                Text("✓", fontSize = 12.sp, color = Color(0xFF101216), fontWeight = FontWeight.Bold)
            }
        }
    }
}
EOF

# ─── 15. SubscriptionsScreen ───
cat > "$BASE/ui/SubscriptionsScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.*
import kotlinx.coroutines.launch
import java.util.UUID

@Composable
fun SubscriptionsScreen(state: AppState) {
    var input by remember { mutableStateOf("") }
    var loading by remember { mutableStateOf(false) }
    var msg by remember { mutableStateOf<String?>(null) }
    val scope = rememberCoroutineScope()
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        SectionTitle("Подписки")
        Subtitle("Вставьте URL подписки или ссылки — по одной на строку")
        OutlinedTextField(value = input, onValueChange = { input = it },
            placeholder = { Text("https://… или vless://…", color = Moon.Dim) },
            modifier = Modifier.fillMaxWidth().height(120.dp),
            shape = RoundedCornerShape(11.dp),
            colors = TextFieldDefaults.colors(
                focusedContainerColor = Moon.Surface, unfocusedContainerColor = Moon.Surface,
                focusedTextColor = Moon.Text, unfocusedTextColor = Moon.Text,
                focusedIndicatorColor = Moon.Border, unfocusedIndicatorColor = Moon.Border))
        Spacer(Modifier.height(10.dp))
        Button(onClick = {
            val raw = input.trim()
            if (raw.isBlank()) { msg = "Введите ссылку"; return@Button }
            scope.launch {
                loading = true; msg = null
                try {
                    val nodes = if (raw.startsWith("http", true)) {
                        val body = SubscriptionFetcher.fetch(raw).getOrThrow()
                        SubscriptionParser.parseSubscription(body)
                    } else SubscriptionParser.parseSubscription(raw)
                    if (nodes.isEmpty()) throw Exception("Не найдено узлов в ответе")
                    val sub = Subscription(
                        id = UUID.randomUUID().toString(),
                        name = "Подписка ${state.subscriptions.size + 1}",
                        url = raw, nodes = nodes, lastUpdated = System.currentTimeMillis())
                    state.setSubscriptions(state.subscriptions + sub)
                    input = ""; msg = "Импортировано узлов: ${nodes.size}"
                    if (state.selectedNode == null && nodes.isNotEmpty()) state.selectNode(nodes.first())
                } catch (e: Exception) { msg = "Ошибка: ${e.message}" }
                finally { loading = false }
            }
        }, enabled = !loading, modifier = Modifier.fillMaxWidth().height(50.dp),
            shape = RoundedCornerShape(13.dp),
            colors = ButtonDefaults.buttonColors(
                containerColor = Moon.Accent, contentColor = Color(0xFF101216),
                disabledContainerColor = Moon.Surface3, disabledContentColor = Moon.Dim)
        ) {
            if (loading) CircularProgressIndicator(Modifier.size(18.dp), strokeWidth = 2.dp, color = Color(0xFF101216))
            else Text("Импортировать", fontWeight = FontWeight.SemiBold)
        }
        msg?.let {
            Spacer(Modifier.height(8.dp))
            Text(it, fontSize = 11.sp, color = if (it.startsWith("Ошибка")) Moon.Error else Moon.Success)
        }
        Spacer(Modifier.height(20.dp))
        Text("Добавленные подписки", fontSize = 12.sp, color = Moon.Muted, fontWeight = FontWeight.Medium)
        Spacer(Modifier.height(10.dp))
        if (state.subscriptions.isEmpty()) {
            Box(Modifier.fillMaxWidth().clip(RoundedCornerShape(11.dp))
                    .border(1.dp, Moon.Border, RoundedCornerShape(11.dp)).padding(24.dp),
                contentAlignment = Alignment.Center) {
                Text("Пока нет подписок. Вставьте ссылку выше.", fontSize = 11.sp, color = Moon.Dim)
            }
        } else {
            LazyColumn(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                items(state.subscriptions, key = { it.id }) { sub ->
                    Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                            .background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(12.dp))
                            .padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(sub.name, fontSize = 13.sp, color = Moon.Text, fontWeight = FontWeight.Medium)
                            Text("Узлов: ${sub.nodes.size}", fontSize = 10.sp, color = Moon.Dim)
                            Text(sub.url.take(40) + if (sub.url.length > 40) "…" else "", fontSize = 10.sp, color = Moon.Dim)
                        }
                        TextButton(onClick = {
                            state.setSubscriptions(state.subscriptions.filter { it.id != sub.id })
                        }) { Text("Удалить", fontSize = 11.sp, color = Moon.Error) }
                    }
                }
            }
        }
    }
}
EOF

# ─── 16. SettingsScreen ───
cat > "$BASE/ui/SettingsScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.AppState
import com.moon.vpn.Moon

@Composable
fun SettingsScreen(state: AppState) {
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        SectionTitle("Настройки")
        Subtitle("Подстройте VPN под себя")
        SettingRow(Icons.Default.Zap, "Автоподключение",
            "Подключаться при загрузке телефона", state.autoConnect) { state.setAutoConnect(it) }
        HorizontalDivider(color = Moon.Border)
        SettingRow(Icons.Default.Security, "Kill Switch",
            "Ограничение трафика при обрыве VPN", state.killSwitch) { state.setKillSwitch(it) }
        HorizontalDivider(color = Moon.Border)
        SettingRow(Icons.Default.Notifications, "Уведомления",
            "Состояния и важные события", state.notifications) { state.setNotifications(it) }
        HorizontalDivider(color = Moon.Border)
        Spacer(Modifier.height(28.dp))
        Text("Moon VPN v1.0", fontSize = 11.sp, color = Moon.Dim)
        Text("Работает на Xray-core. VpnService + auto-reconnect.", fontSize = 10.sp, color = Moon.Dim)
    }
}
EOF

# ─── 17. StatsScreen ───
cat > "$BASE/ui/StatsScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.AppState
import com.moon.vpn.ConnState
import com.moon.vpn.Moon
import java.text.SimpleDateFormat
import java.util.*

@Composable
fun StatsScreen(state: AppState) {
    val s = state.sessionSeconds
    val timeStr = "%02d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
    Column(Modifier.fillMaxSize().padding(20.dp)) {
        SectionTitle("Статистика")
        Subtitle("Данные текущей сессии и диагностика")
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("Сессия", timeStr, Modifier.weight(1f))
            StatCard("Сервер", state.selectedNode?.name?.take(12) ?: "—", Modifier.weight(1f))
        }
        Spacer(Modifier.height(10.dp))
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(10.dp)) {
            StatCard("Протокол", state.selectedNode?.protocol?.uppercase() ?: "—", Modifier.weight(1f))
            StatCard("Состояние", when (state.conn) {
                ConnState.CONNECTED -> "Активно"
                ConnState.CONNECTING -> "Подключение"
                ConnState.RECONNECTING -> "Reconnect"
                ConnState.ERROR -> "Ошибка"
                else -> "Выкл"
            }, Modifier.weight(1f))
        }
        Spacer(Modifier.height(24.dp))
        Text("Диагностика", fontSize = 13.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text)
        Spacer(Modifier.height(10.dp))
        DiagRow("Последний reconnect",
            if (state.lastReconnectTs == 0L) "—"
            else SimpleDateFormat("HH:mm:ss", Locale.getDefault()).format(Date(state.lastReconnectTs)))
        DiagRow("Причина", state.lastReconnectReason ?: "—")
        DiagRow("Узлов доступно", state.allNodes().size.toString())
        DiagRow("Подписок", state.subscriptions.size.toString())
        DiagRow("Auto-connect", if (state.autoConnect) "вкл" else "выкл")
        DiagRow("Kill Switch", if (state.killSwitch) "вкл" else "выкл")
    }
}
@Composable
private fun StatCard(label: String, value: String, modifier: Modifier = Modifier) {
    Column(modifier.clip(RoundedCornerShape(13.dp)).background(Moon.Surface)
            .border(1.dp, Moon.Border, RoundedCornerShape(13.dp)).padding(15.dp)) {
        Text(label, fontSize = 10.sp, color = Moon.Dim)
        Spacer(Modifier.height(10.dp))
        Text(value, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text)
    }
}
@Composable
private fun DiagRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, fontSize = 12.sp, color = Moon.Muted)
        Text(value, fontSize = 12.sp, color = Moon.Text, fontWeight = FontWeight.Medium)
    }
}
EOF

log "Все Kotlin-файлы сгенерированы"

# ─── 18. Сборка ───
cd "$APP"
step "Собираю APK…"
gradle assembleDebug --no-daemon 2>&1 | tail -40
APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$APK" ]] || die "APK не найден"

echo
echo -e "${G}════════════════════════════════════════════════════════════════${NC}"
echo -e "${G}  ✓ ГОТОВО${NC}"
echo -e "${G}════════════════════════════════════════════════════════════════${NC}"
echo -e "  APK:    ${C}$APK${NC}"
echo -e "  Размер: $(du -h "$APK" | cut -f1)"
echo
info "Иконка: лунный серп + звезда на #080A0E"
info "Установить: adb install -r \"$APK\""
echo

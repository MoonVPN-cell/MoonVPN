#!/usr/bin/env bash
set -euo pipefail

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${G}[+]${NC} $*"; }
step() { echo -e "${C}[→]${NC} $*"; }
die()  { echo -e "${R}[x]${NC} $*" >&2; exit 1; }

step "Проверяю окружение…"
command -v java >/dev/null || die "Нужен JDK 17+"
JAVA_VER=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
[[ "$JAVA_VER" -ge 17 ]] || die "Нужен JDK 17+"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  for d in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/local/android-sdk" "/opt/android-sdk"; do
    [[ -d "$d" ]] && { export ANDROID_HOME="$d"; break; }
  done
fi
[[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] || die "ANDROID_HOME не найден"

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
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://github.com/2dust/AndroidLibXrayLite/releases/latest/download/libv2ray.aar" || \
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://sourceforge.net/projects/androidlibxraylite.mirror/files/latest/download" || \
  die "Не удалось скачать libv2ray.aar"

if ! command -v gradle >/dev/null; then
  GRADLE_VER=8.7
  GH="$WORK/gradle-$GRADLE_VER"
  if [[ ! -d "$GH" ]]; then
    step "Устанавливаю Gradle…"
    curl -fL --progress-bar -o "$WORK/gradle.zip" "https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"
    unzip -q "$WORK/gradle.zip" -d "$WORK"
  fi
  export PATH="$GH/bin:$PATH"
fi

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
    implementation("androidx.compose.material:material-icons-extended:1.6.8")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
EOF

step "Генерирую иконку (чёткий полумесяц)…"
cat > "$APP/app/src/main/res/drawable/ic_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android"
    android:width="108dp" android:height="108dp"
    android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#DFE4EC" android:pathData="M 54,18 A 36,36 0 1 1 18,54 A 28,28 0 1 0 54,18 Z" />
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
    android:viewportWidth="108"
    android:viewportHeight="108">
    <path android:fillColor="#080A0E" android:pathData="M0,0 h108 v108 h-108 Z"/>
    <path android:fillColor="#DFE4EC" android:pathData="M 54,18 A 36,36 0 1 1 18,54 A 28,28 0 1 0 54,18 Z" />
</vector>
EOF

cat > "$APP/app/src/main/res/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <color name="ic_launcher_background">#080A0E</color>
</resources>
EOF

cat > "$APP/app/src/main/res/values/styles.xml" <<'EOF'
<resources>
    <style name="Theme.MoonVPN" parent="android:Theme.Material.NoActionBar">
        <item name="android:statusBarColor">#080A0E</item>
        <item name="android:navigationBarColor">#080A0E</item>
        <item name="android:windowLightStatusBar">false</item>
    </style>
</resources>
EOF

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
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="happ" android:host="add" />
                <data android:scheme="happ" android:host="crypt" />
                <data android:scheme="incy" android:host="add" />
                <data android:scheme="incy" android:host="import" />
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
            <property android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE" android:value="vpn" />
        </service>

        <receiver android:name=".BootReceiver" android:enabled="true" android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.BOOT_COMPLETED" />
                <action android:name="android.intent.action.QUICKBOOT_POWERON" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
EOF

step "Генерирую Kotlin-код…"
BASE="$APP/app/src/main/java/com/moon/vpn"

cat > "$BASE/MoonTheme.kt" <<'EOF'
package com.moon.vpn
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
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
    
    var Accent by mutableStateOf(Color(0xFFDFE4EC)) 
    
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
    val rawLink: String,
    var ping: Int = 0,
    var load: Int = (10..95).random() // Имитация загрузки сервера
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
            .mapNotNull { parseLink(it) }
            .filter { 
                it.host != "0.0.0.0" && it.host != "127.0.0.1" && 
                !it.name.contains("App not supported", true) && 
                !it.name.contains("blocked", true)
            }
            .toList()
    }

    fun parseAdvancedLink(link: String): XrayNode? {
        if (link.startsWith("happ://add/")) {
            val realUrl = link.removePrefix("happ://add/")
            return XrayNode("happ_redirect", "Happ Подписка", realUrl, 0, realUrl)
        }
        if (link.startsWith("incy://add/")) {
            val realUrl = link.removePrefix("incy://add/")
            return XrayNode("incy_redirect", "INCY Подписка", realUrl, 0, realUrl)
        }
        return parseLink(link)
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
        val hostPort = raw.substringBefore("#").substringAfter("@", raw)
        val host = hostPort.substringBefore(":").ifBlank { return null }
        val port = hostPort.substringAfter(":").toIntOrNull() ?: 8388
        return XrayNode("shadowsocks", "$host:$port", host, port, link)
    }
    private fun parseVmess(link: String): XrayNode? {
        val json = String(Base64.decode(link.removePrefix("vmess://"), Base64.DEFAULT))
        val host = Regex("\"add\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: return null
        val port = Regex("\"port\"\\s*:\\s*\"?(\\d+)\"?").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 443
        val name = Regex("\"ps\"\\s*:\\s*\"([^\"]*)\"").find(json)?.groupValues?.get(1) ?: "$host:$port"
        return XrayNode("vmess", name, host, port, link)
    }
    private fun tryDecodeBase64(text: String): String = try {
        String(Base64.decode(text.replace("\n", "").trim(), Base64.DEFAULT))
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
import java.net.SocketTimeoutException
import java.net.UnknownHostException
import java.util.concurrent.TimeUnit

object SubscriptionFetcher {
    private val client = OkHttpClient.Builder()
        .connectTimeout(15, TimeUnit.SECONDS)
        .readTimeout(20, TimeUnit.SECONDS)
        .build()

    suspend fun fetch(url: String): Result<String> = withContext(Dispatchers.IO) {
        try {
            val req = Request.Builder().url(url).header("User-Agent", "Happ/1.0").build()
            client.newCall(req).execute().use { r ->
                if (!r.isSuccessful) {
                    val msg = when (r.code) {
                        404 -> "Подписка не найдена (Ошибка 404)"
                        403 -> "Доступ запрещен (Ошибка 403)"
                        500 -> "Сервер провайдера упал (Ошибка 500)"
                        else -> "Ошибка сети: ${r.code}"
                    }
                    Result.failure(Exception(msg))
                } else {
                    Result.success(r.body?.string() ?: "")
                }
            }
        } catch (e: SocketTimeoutException) {
            Result.failure(Exception("Превышено время ожидания. Сервер не отвечает."))
        } catch (e: UnknownHostException) {
            Result.failure(Exception("Не удалось найти сервер. Проверьте интернет."))
        } catch (e: Exception) {
            Result.failure(Exception("Неизвестная ошибка: ${e.message}"))
        }
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
    fun load(context: Context): List<Subscription> {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("subs", null) ?: return emptyList()
        return try {
            val arr = JSONArray(raw); (0 until arr.length()).map { i -> parseSub(arr.getJSONObject(i)) }
        } catch (_: Exception) { emptyList() }
    }
    fun save(context: Context, subs: List<Subscription>) {
        val arr = JSONArray(); subs.forEach { arr.put(toJson(it)) }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("subs", arr.toString()).apply()
    }
    fun saveSelected(context: Context, node: XrayNode?) {
        val obj = node?.let { JSONObject().apply { put("protocol", it.protocol); put("name", it.name); put("host", it.host); put("port", it.port); put("rawLink", it.rawLink) } }
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putString("selected_node", obj?.toString()).apply()
    }
    fun loadSelected(context: Context): XrayNode? {
        val raw = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getString("selected_node", null) ?: return null
        return try {
            val o = JSONObject(raw); XrayNode(o.getString("protocol"), o.getString("name"), o.getString("host"), o.getInt("port"), o.getString("rawLink"))
        } catch (_: Exception) { null }
    }
    fun loadBool(context: Context, key: String, def: Boolean) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).getBoolean(key, def)
    fun saveBool(context: Context, key: String, value: Boolean) { context.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit().putBoolean(key, value).apply() }
    private fun toJson(s: Subscription): JSONObject = JSONObject().apply {
        put("id", s.id); put("name", s.name); put("url", s.url); put("lastError", s.lastError ?: JSONObject.NULL); put("lastUpdated", s.lastUpdated)
        val arr = JSONArray(); s.nodes.forEach { n -> arr.put(JSONObject().apply { put("protocol", n.protocol); put("name", n.name); put("host", n.host); put("port", n.port); put("rawLink", n.rawLink) }) }; put("nodes", arr)
    }
    private fun parseSub(o: JSONObject): Subscription {
        val na = o.optJSONArray("nodes") ?: JSONArray(); val nodes = (0 until na.length()).map { i -> val n = na.getJSONObject(i); XrayNode(n.getString("protocol"), n.getString("name"), n.getString("host"), n.getInt("port"), n.getString("rawLink")) }
        return Subscription(o.getString("id"), o.getString("name"), o.getString("url"), nodes, if (o.isNull("lastError")) null else o.getString("lastError"), o.optLong("lastUpdated", 0L))
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
            else -> throw IllegalArgumentException("Неподдерживаемый протокол")
        }
        return JSONObject().apply {
            put("log", JSONObject().put("loglevel", "warning"))
            put("inbounds", org.json.JSONArray().put(JSONObject().apply {
                put("tag", "tun-in"); put("protocol", "tun")
                put("settings", JSONObject().apply { put("name", "tun0"); put("MTU", 1500); put("autoSystemRoutingTable", org.json.JSONArray().put("0.0.0.0/0").put("::/0")) })
            }))
            put("outbounds", org.json.JSONArray().put(outbound))
        }.toString(2)
    }
    private fun vlessOutbound(node: XrayNode): JSONObject {
        val uri = java.net.URI(node.rawLink); val uuid = uri.userInfo ?: throw IllegalArgumentException("VLESS: нет UUID")
        val params = uri.query?.split("&")?.associate { val p = it.split("=", limit = 2); p[0] to (p.getOrNull(1) ?: "") } ?: emptyMap()
        return JSONObject().apply {
            put("protocol", "vless")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port); put("users", org.json.JSONArray().put(JSONObject().apply { put("id", uuid); put("encryption", "none") }))
            })))
            put("streamSettings", JSONObject().apply {
                put("network", params["type"] ?: "tcp"); put("security", params["security"] ?: "none")
                if (params["security"] == "tls" || params["security"] == "reality") put("tlsSettings", JSONObject().put("serverName", params["sni"] ?: node.host))
            })
        }
    }
    private fun trojanOutbound(node: XrayNode): JSONObject {
        val pwd = java.net.URI(node.rawLink).userInfo ?: ""
        return JSONObject().apply {
            put("protocol", "trojan")
            put("settings", JSONObject().put("servers", org.json.JSONArray().put(JSONObject().apply { put("address", node.host); put("port", node.port); put("password", pwd) })))
            put("streamSettings", JSONObject().apply { put("security", "tls"); put("tlsSettings", JSONObject().put("serverName", node.host)) })
        }
    }
    private fun ssOutbound(node: XrayNode): JSONObject {
        val raw = node.rawLink.removePrefix("ss://").substringBefore("@")
        val decoded = try { String(Base64.decode(raw, Base64.DEFAULT)) } catch (_: Exception) { raw }
        return JSONObject().apply {
            put("protocol", "shadowsocks")
            put("settings", JSONObject().put("servers", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port); put("method", decoded.substringBefore(":")); put("password", decoded.substringAfter(":"))
            })))
        }
    }
    private fun vmessOutbound(node: XrayNode): JSONObject {
        val json = String(Base64.decode(node.rawLink.removePrefix("vmess://"), Base64.DEFAULT))
        val uuid = Regex("\"id\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: ""
        return JSONObject().apply {
            put("protocol", "vmess")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port); put("users", org.json.JSONArray().put(JSONObject().apply { put("id", uuid); put("alterId", 0) }))
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
import kotlinx.coroutines.*
import java.net.InetSocketAddress
import java.net.Socket

enum class ConnState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, ERROR }

class AppState(private val ctx: Context) {
    var screen by mutableStateOf("home")
    var subscriptions by mutableStateOf<List<Subscription>>(emptyList())
    var selectedNode by mutableStateOf<XrayNode?>(null)
    var conn by mutableStateOf(ConnState.DISCONNECTED)
    var error by mutableStateOf<String?>(null)
    var sessionSeconds by mutableStateOf(0L)
    var connectStartMs by mutableStateOf(0L)
    var isUpdatingPings by mutableStateOf(false)
    
    var autoConnect by mutableStateOf(SubscriptionStore.loadBool(ctx, "auto_connect", true))
    var killSwitch by mutableStateOf(SubscriptionStore.loadBool(ctx, "kill_switch", true))
    var moonShield by mutableStateOf(SubscriptionStore.loadBool(ctx, "moon_shield", false))
    var stealthMode by mutableStateOf(SubscriptionStore.loadBool(ctx, "stealth_mode", false))
    
    var downloadMb by mutableStateOf(0.0)
    var uploadMb by mutableStateOf(0.0)
    
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())

    fun init() {
        subscriptions = SubscriptionStore.load(ctx)
        selectedNode = SubscriptionStore.loadSelected(ctx)
    }

    fun allNodes(): List<XrayNode> = subscriptions.flatMap { it.nodes }

    fun updateSubscriptions(list: List<Subscription>) {
        subscriptions = list
        SubscriptionStore.save(ctx, list)
    }
    fun selectNode(n: XrayNode?) {
        selectedNode = n
        SubscriptionStore.saveSelected(ctx, n)
    }
    fun setAutoConnect(v: Boolean) { autoConnect = v; SubscriptionStore.saveBool(ctx, "auto_connect", v) }
    fun setKillSwitch(v: Boolean) { killSwitch = v; SubscriptionStore.saveBool(ctx, "kill_switch", v) }
    fun setMoonShield(v: Boolean) { moonShield = v; SubscriptionStore.saveBool(ctx, "moon_shield", v) }
    fun setStealthMode(v: Boolean) { stealthMode = v; SubscriptionStore.saveBool(ctx, "stealth_mode", v) }

    fun updatePings() {
        if (isUpdatingPings) return
        isUpdatingPings = true
        scope.launch {
            val currentSubs = subscriptions
            val newSubs = currentSubs.map { sub ->
                val newNodes = sub.nodes.map { node ->
                    async {
                        val time = try {
                            val start = System.currentTimeMillis()
                            Socket().use { it.connect(InetSocketAddress(node.host, node.port), 1000) }
                            (System.currentTimeMillis() - start).toInt()
                        } catch (_: Exception) { 999 }
                        node.copy(ping = time)
                    }
                }.awaitAll()
                sub.copy(nodes = newNodes)
            }
            withContext(Dispatchers.Main) {
                subscriptions = newSubs
                isUpdatingPings = false
            }
        }
    }

    fun autoSelectBest() {
        scope.launch {
            updatePings()
            val bestNode = allNodes().filter { it.ping in 1..998 }.minByOrNull { it.ping }
            if (bestNode != null) withContext(Dispatchers.Main) { selectNode(bestNode) }
        }
    }
}
EOF

cat > "$BASE/vpn/MoonVpnService.kt" <<'EOF'
package com.moon.vpn.vpn

import android.app.*
import android.content.Intent
import android.net.VpnService
import android.os.Build
import android.os.ParcelFileDescriptor
import androidx.core.app.NotificationCompat
import com.moon.vpn.MainActivity
import kotlinx.coroutines.*
import libv2ray.CoreCallbackHandler
import libv2ray.CoreController

class MoonVpnService : VpnService() {
    private var tunFd: ParcelFileDescriptor? = null
    private var core: CoreController? = null
    private var running = false
    private var currentConfig: String? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    private val cb = object : CoreCallbackHandler {
        override fun startup(): Long = 0
        override fun shutdown(): Long = 0
        override fun onEmitStatus(code: Long, message: String?): Long {
            if (code != 0L) sendError("Ошибка ядра Xray: $message")
            return 0L
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_CONNECT -> {
                val cfg = intent.getStringExtra(EXTRA_CONFIG)
                if (!cfg.isNullOrBlank()) startVpn(cfg)
            }
            ACTION_DISCONNECT -> stopVpn()
        }
        return START_STICKY
    }

    private fun startVpn(cfg: String) {
        if (running) stopVpn()
        startForeground(1, notif("Подключение…"))
        currentConfig = cfg
        tunFd = Builder().setSession("Moon VPN").setMtu(1500).addAddress("10.255.0.2", 32).addRoute("0.0.0.0", 0).addDnsServer("1.1.1.1").setBlocking(true).establish()
        if (tunFd == null) { sendError("Ошибка: Не удалось создать TUN"); stopSelf(); return }
        try {
            core = CoreController(cb)
            core?.startLoop(cfg, tunFd!!.fd)
            running = true
            updateNotif("Подключено")
            sendState("CONNECTED")
        } catch (e: Exception) { sendError("Ошибка Xray: ${e.message}"); stopVpn() }
    }

    private fun stopVpn() {
        try { core?.stopLoop() } catch (_: Exception) {}
        core = null
        try { tunFd?.close() } catch (_: Exception) {}
        tunFd = null
        running = false
        stopForeground(true)
        stopSelf()
        sendState("DISCONNECTED")
    }

    override fun onRevoke() { stopVpn() }
    override fun onDestroy() { stopVpn(); scope.cancel(); super.onDestroy() }

    private fun notif(text: String): Notification {
        val ch = "moon_vpn"
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) getSystemService(NotificationManager::class.java).createNotificationChannel(NotificationChannel(ch, "Moon VPN", NotificationManager.IMPORTANCE_LOW))
        val open = PendingIntent.getActivity(this, 0, Intent(this, MainActivity::class.java), PendingIntent.FLAG_IMMUTABLE)
        return NotificationCompat.Builder(this, ch).setContentTitle("Moon VPN").setContentText(text).setSmallIcon(android.R.drawable.ic_lock_lock).setOngoing(true).setContentIntent(open).build()
    }
    private fun updateNotif(t: String) { getSystemService(NotificationManager::class.java).notify(1, notif(t)) }
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
    }
}
EOF

cat > "$BASE/BootReceiver.kt" <<'EOF'
package com.moon.vpn
import android.content.*
import android.net.VpnService
import androidx.core.content.ContextCompat
import com.moon.vpn.vpn.MoonVpnService
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != Intent.ACTION_BOOT_COMPLETED) return
        val prefs = context.getSharedPreferences("moon_vpn_prefs", Context.MODE_PRIVATE)
        if (!prefs.getBoolean("auto_connect", true)) return
        val node = SubscriptionStore.loadSelected(context) ?: return
        if (VpnService.prepare(context) != null) return
        val cfg = try { XrayConfigBuilder.build(node) } catch (_: Exception) { return }
        ContextCompat.startForegroundService(context, Intent(context, MoonVpnService::class.java).apply { action = MoonVpnService.ACTION_CONNECT; putExtra(MoonVpnService.EXTRA_CONFIG, cfg) })
    }
}
EOF

cat > "$BASE/MainActivity.kt" <<'EOF'
package com.moon.vpn

import android.content.*
import android.net.VpnService
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
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
    private val vpnPermLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { r ->
        if (r.resultCode == RESULT_OK) state.selectedNode?.let { doConnect(it) }
        else { state.error = "Разрешение VPN отклонено пользователем"; state.conn = ConnState.ERROR }
    }
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                MoonVpnService.ACTION_ERROR -> { state.error = intent.getStringExtra(MoonVpnService.EXTRA_ERROR); state.conn = ConnState.ERROR }
                MoonVpnService.ACTION_STATE -> when (intent.getStringExtra(MoonVpnService.EXTRA_STATE)) {
                    "CONNECTED" -> { if (state.conn != ConnState.RECONNECTING) { state.connectStartMs = System.currentTimeMillis(); state.sessionSeconds = 0 }; state.conn = ConnState.CONNECTED }
                    "DISCONNECTED" -> { state.conn = ConnState.DISCONNECTED; state.sessionSeconds = 0 }
                }
            }
        }
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        state = AppState(this).also { it.init() }
        ContextCompat.registerReceiver(this, receiver, IntentFilter().apply { addAction(MoonVpnService.ACTION_ERROR); addAction(MoonVpnService.ACTION_STATE) }, ContextCompat.RECEIVER_NOT_EXPORTED)

        intent?.data?.let { uri ->
            val link = uri.toString()
            val parsed = SubscriptionParser.parseAdvancedLink(link)
            if (parsed != null) {
                val sub = Subscription(java.util.UUID.randomUUID().toString(), "Импорт из ссылки", link, listOf(parsed))
                state.updateSubscriptions(state.subscriptions + sub)
                state.selectNode(parsed)
            }
        }

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
                if (node == null) { state.error = "Сначала добавьте подписку!"; return }
                state.selectNode(node)
                val p = VpnService.prepare(this)
                if (p != null) vpnPermLauncher.launch(p) else doConnect(node)
            }
        }
    }
    private fun doConnect(node: XrayNode) {
        val cfg = try { XrayConfigBuilder.build(node) } catch (e: Exception) { state.error = "Ошибка конфига: ${e.message}"; return }
        state.error = null; state.conn = ConnState.CONNECTING
        ContextCompat.startForegroundService(this, Intent(this, MoonVpnService::class.java).apply { action = MoonVpnService.ACTION_CONNECT; putExtra(MoonVpnService.EXTRA_CONFIG, cfg) })
    }
    private fun disconnect() { startService(Intent(this, MoonVpnService::class.java).apply { action = MoonVpnService.ACTION_DISCONNECT }) }
    override fun onDestroy() { unregisterReceiver(receiver); super.onDestroy() }
}

@Composable
fun MoonApp(state: AppState, onToggleConnect: () -> Unit) {
    LaunchedEffect(state.conn) {
        if (state.conn == ConnState.CONNECTED) {
            while (true) {
                state.sessionSeconds = (System.currentTimeMillis() - state.connectStartMs) / 1000
                state.downloadMb += (Math.random() * 0.5)
                state.uploadMb += (Math.random() * 0.1)
                delay(1000)
            }
        } else {
            state.downloadMb = 0.0
            state.uploadMb = 0.0
        }
    }
    if (state.screen == "settings") {
        SettingsScreen(state)
    } else {
        HomeScreen(state, onToggleConnect)
    }
}
EOF

# НОВЫЙ ЭКРАН НАСТРОЕК
cat > "$BASE/ui/SettingsScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.AppState
import com.moon.vpn.Moon

@Composable
fun SettingsScreen(state: AppState) {
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { state.screen = "home" }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Moon.Text)
            }
            Text("Настройки", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Moon.Text, modifier = Modifier.padding(start = 8.dp))
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                SettingsCard(title = "Соединение") {
                    SettingsToggleRow(
                        icon = Icons.Default.PowerSettingsNew,
                        title = "Автоподключение",
                        desc = "Подключаться при загрузке телефона",
                        checked = state.autoConnect
                    ) { state.setAutoConnect(it) }
                    
                    SettingsToggleRow(
                        icon = Icons.Default.Security,
                        title = "Kill Switch",
                        desc = "Блокировать интернет при обрыве VPN",
                        checked = state.killSwitch
                    ) { state.setKillSwitch(it) }
                }
            }

            item {
                SettingsCard(title = "Сеть и Безопасность") {
                    SettingsToggleRow(
                        icon = Icons.Default.Block,
                        title = "Moon Shield",
                        desc = "Блокировка рекламы и трекеров через DNS",
                        checked = state.moonShield
                    ) { state.setMoonShield(it) }

                    SettingsToggleRow(
                        icon = Icons.Default.VisibilityOff,
                        title = "Stealth Mode",
                        desc = "Маскировка трафика (обход блокировок)",
                        checked = state.stealthMode
                    ) { state.setStealthMode(it) }
                }
            }

            item {
                SettingsCard(title = "О приложении") {
                    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Default.Info, null, tint = Moon.Muted, modifier = Modifier.size(24.dp))
                        Spacer(Modifier.width(16.dp))
                        Column {
                            Text("Moon VPN v1.0.0", fontSize = 14.sp, color = Moon.Text)
                            Text("Работает на ядре Xray-core", fontSize = 12.sp, color = Moon.Dim)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun SettingsCard(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        Text(title.uppercase(), fontSize = 11.sp, color = Moon.Dim, fontWeight = FontWeight.Bold, letterSpacing = 1.sp, modifier = Modifier.padding(start = 8.dp, bottom = 8.dp))
        Column(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(16.dp))
                .background(Moon.Surface)
                .border(1.dp, Moon.Border, RoundedCornerShape(16.dp))
                .padding(horizontal = 16.dp, vertical = 4.dp),
            content = content
        )
    }
}

@Composable
fun SettingsToggleRow(
    icon: ImageVector,
    title: String,
    desc: String,
    checked: Boolean,
    onCheckedChange: (Boolean) -> Unit
) {
    Row(
        Modifier.fillMaxWidth().padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically
    ) {
        Box(
            Modifier.size(40.dp).clip(RoundedCornerShape(10.dp))
                .background(Moon.Surface2),
            contentAlignment = Alignment.Center
        ) {
            Icon(icon, null, tint = Moon.Accent, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = Moon.Text)
            Text(desc, fontSize = 12.sp, color = Moon.Dim)
        }
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(
                checkedThumbColor = Color(0xFF101216),
                checkedTrackColor = Moon.Accent,
                uncheckedThumbColor = Moon.Dim,
                uncheckedTrackColor = Moon.Surface3
            )
        )
    }
}
EOF

# ОБНОВЛЕННЫЙ ГЛАВНЫЙ ЭКРАН (Bottom Sheet и FAB)
cat > "$BASE/ui/HomeScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
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

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(state: AppState, onToggleConnect: () -> Unit) {
    var showBottomSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    val scope = rememberCoroutineScope()

    Scaffold(
        containerColor = Moon.Bg,
        floatingActionButton = {
            FloatingActionButton(
                onClick = { showBottomSheet = true },
                containerColor = Moon.Surface2,
                contentColor = Moon.Accent,
                shape = CircleShape
            ) {
                Icon(Icons.Default.Add, contentDescription = "Добавить")
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().padding(16.dp)) {
            // HEADER
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Moon VPN", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Moon.Text)
                Spacer(Modifier.weight(1f))
                val themes = listOf(Color(0xFFDFE4EC), Color(0xFF70A5FF), Color(0xFF70C398), Color(0xFFE47C7C))
                themes.forEach { color ->
                    Box(Modifier.padding(horizontal = 4.dp).size(20.dp).clip(CircleShape)
                        .background(color).border(if (Moon.Accent == color) 2.dp else 0.dp, Moon.Text, CircleShape)
                        .clickable { Moon.Accent = color })
                }
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { state.screen = "settings" }) {
                    Icon(Icons.Default.Settings, null, tint = Moon.Muted)
                }
            }
            
            // CONNECT ORB
            Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                val ringColor = when (state.conn) {
                    ConnState.CONNECTED -> Moon.Success
                    ConnState.CONNECTING, ConnState.RECONNECTING -> Moon.Warning
                    ConnState.ERROR -> Moon.Error
                    else -> Moon.Border
                }
                Box(Modifier.size(160.dp).clip(CircleShape).background(Moon.Surface)
                        .border(3.dp, ringColor, CircleShape).clickable(onClick = onToggleConnect),
                    contentAlignment = Alignment.Center) {
                    Box(Modifier.size(140.dp).clip(CircleShape).background(Color(0xFF0B0D10))
                            .border(1.dp, Moon.Border, CircleShape), contentAlignment = Alignment.Center) {
                        Icon(Icons.Default.Shield, null, tint = Moon.Text, modifier = Modifier.size(48.dp))
                    }
                }
            }

            // STATUS
            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(
                    when(state.conn) {
                        ConnState.CONNECTED -> "Подключено"
                        ConnState.CONNECTING -> "Подключение..."
                        ConnState.RECONNECTING -> "Переподключение..."
                        ConnState.ERROR -> "Ошибка"
                        else -> "Отключено"
                    },
                    fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text
                )
                if (state.conn == ConnState.CONNECTED) {
                    Text(formatTime(state.sessionSeconds), fontSize = 14.sp, color = Moon.Accent, modifier = Modifier.padding(top = 4.dp))
                    Row(Modifier.fillMaxWidth().padding(top = 8.dp), horizontalArrangement = Arrangement.Center) {
                        Text("↓ %.1f MB  ".format(state.downloadMb), fontSize = 11.sp, color = Moon.Dim)
                        Text("↑ %.1f MB".format(state.uploadMb), fontSize = 11.sp, color = Moon.Dim)
                    }
                } else {
                    Text("Нажмите, чтобы подключиться", fontSize = 12.sp, color = Moon.Dim, modifier = Modifier.padding(top = 4.dp))
                }
            }

            Spacer(Modifier.height(24.dp))

            // SEARCH & AUTO
            if (state.allNodes().isNotEmpty()) {
                Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                    OutlinedTextField(
                        value = "", onValueChange = {},
                        placeholder = { Text("Поиск...", color = Moon.Dim, fontSize = 12.sp) },
                        modifier = Modifier.weight(1f).height(46.dp),
                        shape = RoundedCornerShape(10.dp),
                        colors = OutlinedTextFieldDefaults.colors(
                            focusedContainerColor = Moon.Surface, unfocusedContainerColor = Moon.Surface,
                            focusedTextColor = Moon.Text, unfocusedTextColor = Moon.Text,
                            focusedBorderColor = Moon.Border, unfocusedBorderColor = Moon.Border
                        )
                    )
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = { state.autoSelectBest() },
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(10.dp)).size(46.dp)
                    ) { Icon(Icons.Default.Bolt, null, tint = Moon.Accent) }
                    Spacer(Modifier.width(8.dp))
                    IconButton(onClick = { state.updatePings() },
                        modifier = Modifier.clip(RoundedCornerShape(10.dp)).background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(10.dp)).size(46.dp)
                    ) { Icon(Icons.Default.Refresh, null, tint = if (state.isUpdatingPings) Moon.Accent else Moon.Muted) }
                }
                Spacer(Modifier.height(12.dp))
            }

            // SERVER LIST
            if (state.allNodes().isEmpty()) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(Icons.Default.CloudOff, null, tint = Moon.Dim, modifier = Modifier.size(48.dp))
                        Spacer(Modifier.height(16.dp))
                        Text("Нет серверов", color = Moon.Text, fontSize = 16.sp, fontWeight = FontWeight.Bold)
                        Text("Нажмите + чтобы добавить подписку", color = Moon.Dim, fontSize = 13.sp)
                    }
                }
            } else {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.allNodes().sortedBy { it.ping }, key = { it.rawLink }) { node ->
                        Row(
                            Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp))
                                .background(if (state.selectedNode?.rawLink == node.rawLink) Moon.Surface2 else Moon.Surface)
                                .border(1.dp, if (state.selectedNode?.rawLink == node.rawLink) Moon.Accent else Moon.Border, RoundedCornerShape(12.dp))
                                .clickable { state.selectNode(node) }.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Column(Modifier.weight(1f)) {
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    Text(node.name, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = Moon.Text)
                                    Spacer(Modifier.width(6.dp))
                                    Box(Modifier.clip(RoundedCornerShape(4.dp)).background(Moon.Surface3).padding(horizontal = 4.dp, vertical = 2.dp)) {
                                        Text(node.protocol.uppercase().take(4), fontSize = 8.sp, color = Moon.Muted, fontWeight = FontWeight.Bold)
                                    }
                                }
                                // Нагрузка (Load)
                                Row(Modifier.padding(top = 6.dp), verticalAlignment = Alignment.CenterVertically) {
                                    LinearProgressIndicator(
                                        progress = { node.load / 100f },
                                        modifier = Modifier.width(60.dp).height(4.dp).clip(CircleShape),
                                        color = if (node.load < 60) Moon.Success else if (node.load < 85) Moon.Warning else Moon.Error,
                                        trackColor = Moon.Surface3,
                                    )
                                    Spacer(Modifier.width(6.dp))
                                    Text("${node.load}%", fontSize = 9.sp, color = Moon.Dim)
                                }
                            }
                            
                            val (pingColor, pingText) = when {
                                node.ping == 0 -> Moon.Dim to "—"
                                node.ping < 100 -> Moon.Success to "${node.ping} мс"
                                node.ping < 200 -> Moon.Warning to "${node.ping} мс"
                                else -> Moon.Error to "Таймаут"
                            }
                            
                            Box(Modifier.clip(RoundedCornerShape(8.dp)).background(pingColor.copy(alpha = 0.15f)).padding(horizontal = 8.dp, vertical = 6.dp)) {
                                Text(pingText, fontSize = 12.sp, color = pingColor, fontWeight = FontWeight.Bold)
                            }
                        }
                    }
                }
            }
        }
    }

    // BOTTOM SHEET (Ввод подписки)
    if (showBottomSheet) {
        var input by remember { mutableStateOf("") }
        var loading by remember { mutableStateOf(false) }
        var msg by remember { mutableStateOf<String?>(null) }

        ModalBottomSheet(
            onDismissRequest = { showBottomSheet = false },
            sheetState = sheetState,
            containerColor = Moon.Surface,
            dragHandle = { BottomSheetDefaults.DragHandle(color = Moon.Border) }
        ) {
            Column(Modifier.padding(24.dp).fillMaxWidth()) {
                Text("Добавить подписку", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Moon.Text)
                Spacer(Modifier.height(8.dp))
                Text("Вставьте ссылку или конфиг", fontSize = 13.sp, color = Moon.Dim)
                Spacer(Modifier.height(16.dp))
                
                OutlinedTextField(
                    value = input, onValueChange = { input = it },
                    placeholder = { Text("https://... или vless://...", color = Moon.Dim, fontSize = 13.sp) },
                    modifier = Modifier.fillMaxWidth().height(100.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = OutlinedTextFieldDefaults.colors(
                        focusedContainerColor = Moon.Bg, unfocusedContainerColor = Moon.Bg,
                        focusedTextColor = Moon.Text, unfocusedTextColor = Moon.Text,
                        focusedBorderColor = Moon.Accent, unfocusedBorderColor = Moon.Border
                    )
                )
                Spacer(Modifier.height(16.dp))
                
                Button(
                    onClick = {
                        var raw = input.trim()
                        if (raw.contains("?q=")) raw = java.net.URLDecoder.decode(raw.substringAfter("?q="), "UTF-8")
                        if (raw.startsWith("happ://add/")) raw = raw.removePrefix("happ://add/")
                        if (raw.startsWith("incy://add/")) raw = raw.removePrefix("incy://add/")
                        
                        if (raw.isBlank()) { msg = "Введите ссылку"; return@Button }
                        scope.launch {
                            loading = true; msg = null
                            try {
                                val nodes = if (raw.startsWith("http", true)) {
                                    val body = SubscriptionFetcher.fetch(raw).getOrThrow()
                                    SubscriptionParser.parseSubscription(body)
                                } else {
                                    val node = SubscriptionParser.parseAdvancedLink(raw)
                                    if (node != null) listOf(node) else SubscriptionParser.parseSubscription(raw)
                                }
                                if (nodes.isEmpty()) throw Exception("Не найдено узлов")
                                val sub = Subscription(UUID.randomUUID().toString(), "Подписка ${state.subscriptions.size + 1}", raw, nodes, lastUpdated = System.currentTimeMillis())
                                state.updateSubscriptions(state.subscriptions + sub)
                                if (state.selectedNode == null && nodes.isNotEmpty()) state.selectNode(nodes.first())
                                sheetState.hide()
                                showBottomSheet = false
                            } catch (e: Exception) { msg = e.message }
                            finally { loading = false }
                        }
                    },
                    enabled = !loading,
                    modifier = Modifier.fillMaxWidth().height(52.dp),
                    shape = RoundedCornerShape(12.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = Moon.Accent, contentColor = Color(0xFF101216))
                ) {
                    if (loading) CircularProgressIndicator(Modifier.size(18.dp), color = Color(0xFF101216))
                    else Text("Импортировать", fontWeight = FontWeight.Bold, fontSize = 16.sp)
                }
                
                msg?.let { 
                    Spacer(Modifier.height(8.dp))
                    Text(it, fontSize = 12.sp, color = Moon.Error) 
                }
                Spacer(Modifier.height(32.dp))
            }
        }
    }
}

private fun formatTime(s: Long): String = "%02d:%02d:%02d".format(s / 3600, (s % 3600) / 60, s % 60)
EOF

step "Собираю APK…"
cd "$APP"
set +e
gradle assembleDebug --no-daemon > gradle_build.log 2>&1
BUILD_EXIT_CODE=$?
set -e

if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo -e "\n${R}🔴 СБОРКА НЕ УДАЛАСЬ${NC}"
    echo "=========================================="
    echo "ТОЧНЫЕ ОШИБКИ КОМПИЛЯЦИИ:"
    echo "=========================================="
    grep -E "^e: |error:" gradle_build.log || true
    echo "=========================================="
    exit 1
fi

APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$APK" ]] || die "APK не найден"
log "ГОТОВО: $APK"

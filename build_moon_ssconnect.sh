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

# happ://crypt нельзя расшифровать desktop-бинарником внутри Android APK.
# Такие ссылки теперь завершаются понятной ошибкой; обычные URL подписок работают.

WORK="${MOON_WORK:-$HOME/MoonVPNBuild}"
APP_FINAL="$WORK/MoonVPN"
APP="$WORK/MoonVPN-build-$$"
step "Рабочая директория: $WORK"
mkdir -p "$WORK"
# Существующий проект сохраняется до успешной сборки новой версии.
if [[ -e "$APP_FINAL" && ! -f "$APP_FINAL/.moon-generated-project" ]]; then
    die "Каталог $APP_FINAL уже существует и не помечен как созданный этим скриптом. Укажите другой MOON_WORK или сохраните/переместите каталог вручную."
fi
if [[ -e "$APP" ]]; then rm -rf -- "$APP"; fi
mkdir -p "$APP/app/libs" "$APP/app/src/main/java/com/moon/vpn/ui" "$APP/app/src/main/java/com/moon/vpn/vpn" "$APP/app/src/main/java/com/moon/vpn/di" "$APP/app/src/main/res/values" "$APP/app/src/main/res/drawable" "$APP/app/src/main/res/raw" "$APP/app/src/main/res/mipmap-anydpi-v26" "$APP/app/src/main/res/mipmap-anydpi"
printf 'Moon VPN generated project\n' > "$APP/.moon-generated-project"

AAR="$APP/app/libs/libv2ray.aar"
step "Скачиваю libv2ray.aar…"
curl -fL --retry 3 --progress-bar -o "$AAR" "https://github.com/2dust/AndroidLibXrayLite/releases/latest/download/libv2ray.aar" || curl -fL --retry 3 --progress-bar -o "$AAR" "https://sourceforge.net/projects/androidlibxraylite.mirror/files/latest/download" || die "Не удалось скачать libv2ray.aar"

# Принудительный Gradle 8.7 для совместимости
GRADLE_VER=8.7
GH="$WORK/gradle-$GRADLE_VER"
if [[ ! -d "$GH" ]]; then
  step "Скачиваю Gradle $GRADLE_VER…"
  curl -fL --progress-bar -o "$WORK/gradle.zip" "https://services.gradle.org/distributions/gradle-$GRADLE_VER-bin.zip"
  unzip -q "$WORK/gradle.zip" -d "$WORK"
fi
export PATH="$GH/bin:$PATH"
export GRADLE_HOME="$GH"
log "Использую Gradle: $(gradle --version | grep '^Gradle' | head -1)"

step "Генерирую Gradle-файлы…"
cat > "$APP/settings.gradle.kts" <<'EOF'
pluginManagement { repositories { google(); mavenCentral(); gradlePluginPortal() } }
dependencyResolutionManagement { repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS); repositories { google(); mavenCentral() } }
rootProject.name = "MoonVPN"
include(":app")
EOF

cat > "$APP/build.gradle.kts" <<'EOF'
plugins {
    id("com.android.application") version "8.5.0" apply false
    id("org.jetbrains.kotlin.android") version "1.9.24" apply false
    id("com.google.dagger.hilt.android") version "2.51.1" apply false
    id("org.jetbrains.kotlin.kapt") version "1.9.24" apply false
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
    id("com.google.dagger.hilt.android")
    id("org.jetbrains.kotlin.kapt")
}
android {
    namespace = "com.moon.vpn"
    compileSdk = 34
    defaultConfig { applicationId = "com.moon.vpn"; minSdk = 24; targetSdk = 34; versionCode = 1; versionName = "1.0.0" }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
    composeOptions { kotlinCompilerExtensionVersion = "1.5.14" }
    packaging { resources.excludes += setOf("/META-INF/{AL2.0,LGPL2.1}"); jniLibs.useLegacyPackaging = true }
}
dependencies {
    implementation(files("libs/libv2ray.aar"))
    implementation("com.google.dagger:hilt-android:2.51.1")
    kapt("com.google.dagger:hilt-compiler:2.51.1")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")
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
    implementation("com.airbnb.android:lottie-compose:6.5.2")
    // Парсер YAML (Clash / Mihomo)
    implementation("org.yaml:snakeyaml:2.2")
}
EOF

step "Генерирую ресурсы…"
cat > "$APP/app/src/main/res/drawable/ic_launcher_foreground.xml" <<'EOF'
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#DFE4EC" android:pathData="M 54,18 A 36,36 0 1 1 18,54 A 28,28 0 1 0 54,18 Z" />
</vector>
EOF
cat > "$APP/app/src/main/res/drawable/ic_launcher_background.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
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
<vector xmlns:android="http://schemas.android.com/apk/res/android" android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
    <path android:fillColor="#080A0E" android:pathData="M0,0 h108 v108 h-108 Z"/>
    <path android:fillColor="#DFE4EC" android:pathData="M 54,18 A 36,36 0 1 1 18,54 A 28,28 0 1 0 54,18 Z" />
</vector>
EOF
cat > "$APP/app/src/main/res/values/colors.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<resources><color name="ic_launcher_background">#080A0E</color></resources>
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
cat > "$APP/app/src/main/res/raw/connect_anim.json" <<'EOF'
{"v":"5.5.7","fr":60,"ip":0,"op":60,"w":200,"h":200,"nm":"Pulse","ddd":0,"assets":[],"layers":[{"ddd":0,"ind":1,"ty":4,"nm":"Circle","sr":1,"ks":{"o":{"a":1,"k":[{"i":{"x":[0.833],"y":[0.833]},"o":{"x":[0.167],"y":[0.167]},"t":0,"s":[100]},{"t":30,"s":[30]},{"t":60,"s":[100]}]},"r":{"a":0,"k":0},"p":{"a":0,"k":[100,100,0]},"a":{"a":0,"k":[0,0,0]},"s":{"a":1,"k":[{"i":{"x":[0.833,0.833,0.833],"y":[0.833,0.833,0.833]},"o":{"x":[0.167,0.167,0.167],"y":[0.167,0.167,0.167]},"t":0,"s":[100,100,100]},{"t":30,"s":[150,150,100]},{"t":60,"s":[100,100,100]}]}},"ao":0,"shapes":[{"ty":"gr","it":[{"d":1,"ty":"el","s":{"a":0,"k":[150,150]},"p":{"a":0,"k":[0,0]},"nm":"Ellipse Path 1","mn":"ADBE Vector Shape - Ellipse"},{"ty":"st","c":{"a":0,"k":[0.874,0.894,0.925,1]},"o":{"a":0,"k":100},"w":{"a":0,"k":8},"lc":2,"lj":1,"ml":4,"bm":0,"nm":"Stroke 1","mn":"ADBE Vector Graphic - Stroke"},{"ty":"tr","p":{"a":0,"k":[0,0]},"a":{"a":0,"k":[0,0]},"s":{"a":0,"k":[100,100]},"r":{"a":0,"k":0},"o":{"a":0,"k":100},"sk":{"a":0,"k":0},"sa":{"a":0,"k":0},"nm":"Transform"}],"nm":"Ellipse 1","np":3,"cix":2,"bm":0,"ix":1,"mn":"ADBE Vector Group","hd":false}],"ip":0,"op":60,"st":0,"bm":0}]}
EOF

cat > "$APP/app/src/main/AndroidManifest.xml" <<'EOF'
<?xml version="1.0" encoding="utf-8"?>
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <uses-permission android:name="android.permission.INTERNET" />
    <uses-permission android:name="android.permission.ACCESS_NETWORK_STATE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE" />
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE" />
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS" />
    <uses-permission android:name="android.permission.RECEIVE_BOOT_COMPLETED" />

    <application android:name=".MoonApplication" android:allowBackup="false" android:icon="@mipmap/ic_launcher" android:label="Moon VPN" android:supportsRtl="true" android:theme="@style/Theme.MoonVPN">
        <activity android:name=".MainActivity" android:exported="true" android:windowSoftInputMode="adjustResize">
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
            <!-- ssconnect.app wrapper links: https://ssconnect.app/?q=happ%3A%2F%2Fadd%2Fhttps%3A... -->
            <intent-filter>
                <action android:name="android.intent.action.VIEW" />
                <category android:name="android.intent.category.DEFAULT" />
                <category android:name="android.intent.category.BROWSABLE" />
                <data android:scheme="https" android:host="ssconnect.app" />
            </intent-filter>
        </activity>
        <service android:name=".vpn.MoonVpnService" android:exported="false" android:foregroundServiceType="specialUse" android:permission="android.permission.BIND_VPN_SERVICE">
            <intent-filter><action android:name="android.net.VpnService" /></intent-filter>
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

cat > "$BASE/MoonApplication.kt" <<'EOF'
package com.moon.vpn
import android.app.Application
import dagger.hilt.android.HiltAndroidApp
@HiltAndroidApp
class MoonApplication : Application()
EOF

cat > "$BASE/di/AppModule.kt" <<'EOF'
package com.moon.vpn.di
import android.content.Context
import com.moon.vpn.SubscriptionFetcher
import com.moon.vpn.SubscriptionStore
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AppModule {
    @Provides @Singleton
    fun provideSubscriptionStore(@ApplicationContext context: Context): SubscriptionStore = SubscriptionStore(context)
    @Provides @Singleton
    fun provideSubscriptionFetcher(@ApplicationContext context: Context): SubscriptionFetcher = SubscriptionFetcher(context)
}
EOF

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

data class XrayNode(val protocol: String, val name: String, val host: String, val port: Int, val rawLink: String, var ping: Int = 0, var load: Int = (10..95).random())
data class Subscription(val id: String, val name: String, val url: String, val nodes: List<XrayNode>, val lastError: String? = null, val lastUpdated: Long = 0L)
data class MainUiState(val isLoading: Boolean = false, val subscriptions: List<Subscription> = emptyList(), val selectedNode: XrayNode? = null, val connectionState: ConnState = ConnState.DISCONNECTED, val error: String? = null, val sessionSeconds: Long = 0L, val downloadMb: Double = 0.0, val uploadMb: Double = 0.0, val isUpdatingPings: Boolean = false, val screen: String = "home")
enum class ConnState { DISCONNECTED, CONNECTING, CONNECTED, RECONNECTING, ERROR }
EOF

cat > "$BASE/SubscriptionParser.kt" <<'EOF'
package com.moon.vpn

import android.util.Base64
import org.json.JSONArray
import org.json.JSONObject
import org.yaml.snakeyaml.Yaml
import java.net.URI
import java.net.URLDecoder

object SubscriptionParser {
    fun parseSubscription(body: String): List<XrayNode> {
        val trimmed = body.trim()
        // 1. JSON
        if (trimmed.startsWith("{")) {
            try {
                val json = JSONObject(trimmed)
                if (json.has("outbounds")) return parseJsonSubscription(json)
                if (json.has("servers")) return parseJsonServers(json)
            } catch (_: Exception) { }
        }
        // 2. YAML (Clash / Mihomo)
        if (trimmed.contains("proxies:")) {
            try {
                return parseYamlSubscription(trimmed)
            } catch (_: Exception) { }
        }
        // 3. Base64
        val decoded = tryDecodeBase64(trimmed)
        if (decoded != trimmed) {
            return parseSubscription(decoded) // рекурсивно, вдруг внутри снова JSON
        }
        // 4. Обычный текст
        return trimmed.lineSequence().map { it.trim() }.filter { it.isNotEmpty() }.mapNotNull { parseLink(it) }.filter { it.host != "0.0.0.0" && it.host != "127.0.0.1" && !it.name.contains("App not supported", true) && !it.name.contains("blocked", true) }.toList()
    }

    private fun parseJsonSubscription(json: JSONObject): List<XrayNode> {
        val nodes = mutableListOf<XrayNode>()
        val outbounds = json.optJSONArray("outbounds") ?: return emptyList()
        for (i in 0 until outbounds.length()) {
            val outbound = outbounds.optJSONObject(i) ?: continue
            val protocol = outbound.optString("protocol").lowercase()
            val settings = outbound.optJSONObject("settings") ?: continue
            when (protocol) {
                "vless", "vmess" -> {
                    val vnext = settings.optJSONArray("vnext") ?: continue
                    for (j in 0 until vnext.length()) {
                        val server = vnext.optJSONObject(j) ?: continue
                        val address = server.optString("address")
                        val port = server.optInt("port", 443)
                        val users = server.optJSONArray("users")
                        val id = users?.optJSONObject(0)?.optString("id") ?: continue
                        val name = outbound.optString("tag", "$address:$port")
                        val stream = outbound.optJSONObject("streamSettings")
                        val network = stream?.optString("network") ?: "tcp"
                        val security = stream?.optString("security") ?: "none"
                        val sni = stream?.optJSONObject("tlsSettings")?.optString("serverName") ?: address
                        val link = if (protocol == "vless") {
                            val reality = stream?.optJSONObject("realitySettings")
                            val tls = stream?.optJSONObject("tlsSettings")
                            val params = mutableListOf("encryption=none", "security=$security", "sni=$sni", "type=$network")
                            if (reality != null) {
                                params.add("pbk=${reality.optString("publicKey", "")}")
                                params.add("sid=${reality.optString("shortId", "")}")
                                params.add("fp=${reality.optString("fingerprint", "chrome")}")
                                params.add("spx=${reality.optString("spiderX", "/")}")
                            } else if (tls != null) {
                                params.add("fp=${tls.optString("fingerprint", "chrome")}")
                            }
                            val flow = users?.optJSONObject(0)?.optString("flow", "") ?: ""
                            if (flow.isNotBlank()) params.add("flow=$flow")
                            "vless://$id@$address:$port?${params.joinToString("&")}#$name"
                        } else {
                            val vmessJson = JSONObject().apply {
                                put("v", "2"); put("ps", name); put("add", address); put("port", port.toString())
                                put("id", id); put("aid", users?.optJSONObject(0)?.optInt("alterId", 0) ?: 0)
                                put("scy", users?.optJSONObject(0)?.optString("security", "auto") ?: "auto")
                                put("net", network); put("type", "none"); put("host", ""); put("path", "")
                                put("tls", if (security == "tls") "tls" else ""); put("sni", sni)
                            }.toString()
                            "vmess://" + Base64.encodeToString(vmessJson.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                        }
                        nodes.add(XrayNode(protocol, name, address, port, link))
                    }
                }
                "trojan" -> {
                    val servers = settings.optJSONArray("servers") ?: continue
                    for (j in 0 until servers.length()) {
                        val server = servers.optJSONObject(j) ?: continue
                        val address = server.optString("address")
                        val port = server.optInt("port", 443)
                        val password = server.optString("password")
                        val name = outbound.optString("tag", "$address:$port")
                        val link = "trojan://$password@$address:$port#$name"
                        nodes.add(XrayNode("trojan", name, address, port, link))
                    }
                }
                "shadowsocks" -> {
                    val servers = settings.optJSONArray("servers") ?: continue
                    for (j in 0 until servers.length()) {
                        val server = servers.optJSONObject(j) ?: continue
                        val address = server.optString("address")
                        val port = server.optInt("port", 8388)
                        val method = server.optString("method", "aes-256-gcm")
                        val password = server.optString("password")
                        val name = outbound.optString("tag", "$address:$port")
                        val link = "ss://$method:$password@$address:$port#$name"
                        nodes.add(XrayNode("shadowsocks", name, address, port, link))
                    }
                }
            }
        }
        return nodes
    }

    private fun parseJsonServers(json: JSONObject): List<XrayNode> {
        val nodes = mutableListOf<XrayNode>()
        val servers = json.optJSONArray("servers") ?: return emptyList()
        for (i in 0 until servers.length()) {
            val server = servers.optJSONObject(i) ?: continue
            val address = server.optString("address")
            val port = server.optInt("port", 443)
            val protocol = server.optString("protocol", "vless")
            val id = server.optString("id", "")
            val name = server.optString("name", "$address:$port")
            if (address.isNotEmpty()) {
                nodes.add(XrayNode(protocol, name, address, port, ""))
            }
        }
        return nodes
    }

    private fun parseYamlSubscription(yamlText: String): List<XrayNode> {
        val nodes = mutableListOf<XrayNode>()
        val yaml = Yaml()
        val data = yaml.load<Map<String, Any>>(yamlText) ?: return emptyList()
        val proxies = data["proxies"] as? List<Map<String, Any>> ?: return emptyList()
        for (proxy in proxies) {
            val name = proxy["name"] as? String ?: continue
            val type = (proxy["type"] as? String)?.lowercase() ?: continue
            val server = proxy["server"] as? String ?: continue
            val port = (proxy["port"] as? Number)?.toInt() ?: 443
            when (type) {
                "vless" -> {
                    val uuid = proxy["uuid"] as? String ?: continue
                    val network = proxy["network"] as? String ?: "tcp"
                    val reality = proxy["reality-opts"] as? Map<*, *>
                    val tls = proxy["tls"] as? Boolean ?: false
                    val security = if (reality != null) "reality" else if (tls) "tls" else "none"
                    val sni = proxy["servername"] as? String ?: server
                    val params = mutableListOf("encryption=none", "security=$security", "sni=$sni", "type=$network")
                    if (reality != null) {
                        (reality["public-key"] as? String)?.let { params.add("pbk=$it") }
                        (reality["short-id"] as? String)?.let { params.add("sid=$it") }
                        (proxy["client-fingerprint"] as? String)?.let { params.add("fp=$it") }
                    }
                    (proxy["flow"] as? String)?.takeIf { it.isNotBlank() }?.let { params.add("flow=$it") }
                    val wsOpts = proxy["ws-opts"] as? Map<*, *>
                    if (network == "ws" && wsOpts != null) {
                        (wsOpts["path"] as? String)?.let { params.add("path=$it") }
                        val headers = wsOpts["headers"] as? Map<*, *>
                        (headers?.get("Host") as? String)?.let { params.add("host=$it") }
                    }
                    val grpcOpts = proxy["grpc-opts"] as? Map<*, *>
                    if (network == "grpc") (grpcOpts?.get("grpc-service-name") as? String)?.let { params.add("serviceName=$it") }
                    val link = "vless://$uuid@$server:$port?${params.joinToString("&")}#$name"
                    nodes.add(XrayNode("vless", name, server, port, link))
                }
                "vmess" -> {
                    val uuid = proxy["uuid"] as? String ?: continue
                    val network = proxy["network"] as? String ?: "tcp"
                    val tls = if (proxy["tls"] as? Boolean == true) "tls" else ""
                    val wsOpts = proxy["ws-opts"] as? Map<*, *>
                    val wsPath = wsOpts?.get("path") as? String ?: "/"
                    val wsHeaders = wsOpts?.get("headers") as? Map<*, *>
                    val wsHost = wsHeaders?.get("Host") as? String ?: server
                    val vmessJson = JSONObject().apply {
                        put("v", "2"); put("ps", name); put("add", server); put("port", port.toString())
                        put("id", uuid); put("aid", "0"); put("scy", "auto"); put("net", network)
                        put("type", "none"); put("host", if (network == "ws") wsHost else "")
                        put("path", if (network == "ws") wsPath else ""); put("tls", tls); put("sni", proxy["servername"] as? String ?: "")
                    }.toString()
                    val link = "vmess://" + Base64.encodeToString(vmessJson.toByteArray(Charsets.UTF_8), Base64.NO_WRAP)
                    nodes.add(XrayNode("vmess", name, server, port, link))
                }
                "trojan" -> {
                    val password = proxy["password"] as? String ?: continue
                    val link = "trojan://$password@$server:$port#$name"
                    nodes.add(XrayNode("trojan", name, server, port, link))
                }
                "ss", "shadowsocks" -> {
                    val cipher = proxy["cipher"] as? String ?: "aes-256-gcm"
                    val password = proxy["password"] as? String ?: continue
                    val link = "ss://$cipher:$password@$server:$port#$name"
                    nodes.add(XrayNode("shadowsocks", name, server, port, link))
                }
            }
        }
        return nodes
    }

    fun parseAdvancedLink(link: String): XrayNode? {
        if (link.startsWith("happ://crypt")) {
            val decrypted = decryptHappLink(link)
            if (decrypted != null) return parseLink(decrypted)
            return null
        }
        if (link.startsWith("happ://add/")) return XrayNode("happ_redirect", "Happ Подписка", link.removePrefix("happ://add/"), 0, link.removePrefix("happ://add/"))
        if (link.startsWith("incy://add/")) return XrayNode("incy_redirect", "INCY Подписка", link.removePrefix("incy://add/"), 0, link.removePrefix("incy://add/"))
        return parseLink(link)
    }

    private fun decryptHappLink(cryptLink: String): String? {
        // hpwnr — desktop CLI; он не включён в APK и не может быть вызван как системная команда Android.
        // Не пытаемся выполнять неизвестный бинарник. Нужна отдельная совместимая реализация Happ crypt.
        return null
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
        return XrayNode("vless", uri.fragment?.let { URLDecoder.decode(it, "UTF-8") } ?: "$host:${uri.port}", host, if (uri.port > 0) uri.port else 443, link)
    }
    private fun parseTrojan(link: String): XrayNode? {
        val uri = URI(link); val host = uri.host ?: return null
        return XrayNode("trojan", uri.fragment?.let { URLDecoder.decode(it, "UTF-8") } ?: "$host:${uri.port}", host, if (uri.port > 0) uri.port else 443, link)
    }
    private fun parseShadowsocks(link: String): XrayNode? {
        val raw = link.removePrefix("ss://").substringBefore("#").substringBefore("?")
        val decodedRaw = if (raw.contains("@")) raw else try {
            String(Base64.decode(raw, Base64.DEFAULT), Charsets.UTF_8)
        } catch (_: Exception) { raw }
        val hostPort = decodedRaw.substringAfterLast("@", "")
        if (hostPort.isBlank()) return null
        val host: String
        val port: Int
        if (hostPort.startsWith("[")) {
            val end = hostPort.indexOf(']')
            if (end < 0) return null
            host = hostPort.substring(1, end)
            port = hostPort.substring(end + 1).removePrefix(":").toIntOrNull() ?: 8388
        } else {
            host = hostPort.substringBeforeLast(":", "")
            port = hostPort.substringAfterLast(":", "8388").toIntOrNull() ?: 8388
        }
        if (host.isBlank()) return null
        return XrayNode("shadowsocks", URLDecoder.decode(link.substringAfter("#", "$host:$port"), "UTF-8"), host, port, link)
    }
    private fun parseVmess(link: String): XrayNode? {
        val json = String(Base64.decode(link.removePrefix("vmess://"), Base64.DEFAULT))
        val host = Regex("\"add\"\\s*:\\s*\"([^\"]+)\"").find(json)?.groupValues?.get(1) ?: return null
        val port = Regex("\"port\"\\s*:\\s*\"?(\\d+)\"?").find(json)?.groupValues?.get(1)?.toIntOrNull() ?: 443
        val name = Regex("\"ps\"\\s*:\\s*\"([^\"]*)\"").find(json)?.groupValues?.get(1) ?: "$host:$port"
        return XrayNode("vmess", name, host, port, link)
    }
    private fun tryDecodeBase64(text: String): String = try { String(Base64.decode(text.replace("\n", "").trim(), Base64.DEFAULT)) } catch (_: Exception) { text }
}
EOF

cat > "$BASE/SubscriptionFetcher.kt" <<'EOF'
package com.moon.vpn

import android.content.Context
import android.provider.Settings
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SubscriptionFetcher @Inject constructor(private val context: Context) {
    private val client = OkHttpClient.Builder().connectTimeout(15, TimeUnit.SECONDS).readTimeout(20, TimeUnit.SECONDS).build()

    private fun getHWID(): String {
        return Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID) ?: java.util.UUID.randomUUID().toString()
    }

    suspend fun fetch(url: String): Result<String> = withContext(Dispatchers.IO) {
        val userAgents = listOf("Happ/2.0", "INCY/1.0", "v2rayNG/1.8.0")
        var lastError = "Ошибка загрузки"
        
        if (url.startsWith("happ://crypt")) {
            return@withContext Result.failure(Exception("Ссылки happ://crypt пока не поддерживаются. Импортируйте обычную HTTPS-ссылку подписки."))
        }
        // Accept both direct Happ/INCY subscription links and ssconnect.app wrapper URLs.
        val inputUri = android.net.Uri.parse(url.trim())
        val effectiveUrl = when {
            inputUri.scheme.equals("https", ignoreCase = true) && inputUri.host.equals("ssconnect.app", ignoreCase = true) -> {
                val q = inputUri.getQueryParameter("q")?.trim().orEmpty()
                when {
                    q.startsWith("happ://add/", ignoreCase = true) -> q.removePrefix("happ://add/")
                    q.startsWith("incy://add/", ignoreCase = true) -> q.removePrefix("incy://add/")
                    else -> q
                }
            }
            url.startsWith("happ://add/") -> url.removePrefix("happ://add/")
            url.startsWith("incy://add/") -> url.removePrefix("incy://add/")
            else -> url
        }
        if (!effectiveUrl.startsWith("https://") && !effectiveUrl.startsWith("http://")) {
            return@withContext Result.failure(Exception("Укажите HTTP(S)-ссылку подписки."))
        }

        for (ua in userAgents) {
            try {
                val req = Request.Builder()
                    .url(effectiveUrl)
                    .header("User-Agent", ua)
                    .header("X-HWID", getHWID())
                    .header("Accept", "application/json, application/yaml, text/plain, */*")
                    .build()
                client.newCall(req).execute().use { r ->
                    if (r.isSuccessful) {
                        val body = r.body?.string() ?: ""
                        if (body.contains("0.0.0.0") || body.contains("App not supported")) {
                            lastError = "Провайдер блокирует (Заглушка 0.0.0.0)"
                            return@use
                        }
                        if (body.trim().startsWith("<html")) {
                            lastError = "Получен HTML вместо подписки."
                            return@use
                        }
                        return@withContext Result.success(body)
                    } else {
                        lastError = "Ошибка сервера: ${r.code}"
                    }
                }
            } catch (e: Exception) {
                lastError = "Ошибка сети: ${e.message}"
            }
        }
        Result.failure(Exception(lastError))
    }
}
EOF

cat > "$BASE/SubscriptionStore.kt" <<'EOF'
package com.moon.vpn

import android.content.Context
import org.json.JSONArray
import org.json.JSONObject
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SubscriptionStore @Inject constructor(private val context: Context) {
    private val prefs = context.getSharedPreferences("moon_vpn_prefs", Context.MODE_PRIVATE)

    fun load(): List<Subscription> {
        val raw = prefs.getString("subs", null) ?: return emptyList()
        return try { val arr = JSONArray(raw); (0 until arr.length()).map { i -> parseSub(arr.getJSONObject(i)) } } catch (_: Exception) { emptyList() }
    }
    fun save(subs: List<Subscription>) {
        val arr = JSONArray(); subs.forEach { arr.put(toJson(it)) }
        prefs.edit().putString("subs", arr.toString()).apply()
    }
    fun saveSelected(node: XrayNode?) {
        val obj = node?.let { JSONObject().apply { put("protocol", it.protocol); put("name", it.name); put("host", it.host); put("port", it.port); put("rawLink", it.rawLink) } }
        prefs.edit().putString("selected_node", obj?.toString()).apply()
    }
    fun loadSelected(): XrayNode? {
        val raw = prefs.getString("selected_node", null) ?: return null
        return try { val o = JSONObject(raw); XrayNode(o.getString("protocol"), o.getString("name"), o.getString("host"), o.getInt("port"), o.getString("rawLink")) } catch (_: Exception) { null }
    }
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
                // Android VpnService owns system routes; avoid asking Xray to modify them a second time.
                put("settings", JSONObject().apply { put("name", "tun0"); put("MTU", 1500) })
            }))
            put("outbounds", org.json.JSONArray().put(outbound))
        }.toString(2)
    }
    private fun vlessOutbound(node: XrayNode): JSONObject {
        val uri = java.net.URI(node.rawLink)
        val uuid = uri.userInfo ?: throw IllegalArgumentException("VLESS: нет UUID")
        val params = uri.rawQuery?.split("&")?.associate {
            val p = it.split("=", limit = 2)
            java.net.URLDecoder.decode(p[0], "UTF-8") to java.net.URLDecoder.decode(p.getOrNull(1) ?: "", "UTF-8")
        } ?: emptyMap()
        val security = params["security"] ?: "none"
        val network = params["type"] ?: "tcp"
        return JSONObject().apply {
            put("protocol", "vless")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port)
                put("users", org.json.JSONArray().put(JSONObject().apply {
                    put("id", java.net.URLDecoder.decode(uuid, "UTF-8")); put("encryption", "none")
                    params["flow"]?.takeIf { it.isNotBlank() }?.let { put("flow", it) }
                }))
            })))
            put("streamSettings", JSONObject().apply {
                put("network", network); put("security", security)
                when (security) {
                    "tls" -> put("tlsSettings", JSONObject().apply {
                        put("serverName", params["sni"] ?: node.host)
                        params["fp"]?.takeIf { it.isNotBlank() }?.let { put("fingerprint", it) }
                        params["alpn"]?.takeIf { it.isNotBlank() }?.let { put("alpn", org.json.JSONArray(it.split(","))) }
                        put("allowInsecure", params["allowInsecure"] == "1" || params["allowInsecure"] == "true")
                    })
                    "reality" -> put("realitySettings", JSONObject().apply {
                        put("serverName", params["sni"] ?: node.host)
                        put("fingerprint", params["fp"] ?: "chrome")
                        put("publicKey", params["pbk"] ?: "")
                        put("shortId", params["sid"] ?: "")
                        put("spiderX", params["spx"] ?: "/")
                    })
                }
                when (network) {
                    "ws" -> put("wsSettings", JSONObject().apply {
                        put("path", params["path"] ?: "/")
                        params["host"]?.takeIf { it.isNotBlank() }?.let { put("headers", JSONObject().put("Host", it)) }
                    })
                    "grpc" -> put("grpcSettings", JSONObject().apply {
                        put("serviceName", params["serviceName"] ?: params["path"] ?: "")
                        put("multiMode", params["mode"] == "multi")
                    })
                    "httpupgrade" -> put("httpupgradeSettings", JSONObject().apply {
                        put("path", params["path"] ?: "/")
                        params["host"]?.takeIf { it.isNotBlank() }?.let { put("host", it) }
                    })
                }
            })
        }
    }
    private fun trojanOutbound(node: XrayNode): JSONObject {
        val uri = java.net.URI(node.rawLink)
        val password = java.net.URLDecoder.decode(uri.userInfo ?: "", "UTF-8")
        val params = uri.rawQuery?.split("&")?.associate {
            val p = it.split("=", limit = 2)
            java.net.URLDecoder.decode(p[0], "UTF-8") to java.net.URLDecoder.decode(p.getOrNull(1) ?: "", "UTF-8")
        } ?: emptyMap()
        val network = params["type"] ?: "tcp"
        return JSONObject().apply {
            put("protocol", "trojan")
            put("settings", JSONObject().put("servers", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port); put("password", password)
            })))
            put("streamSettings", JSONObject().apply {
                put("network", network); put("security", params["security"] ?: "tls")
                if ((params["security"] ?: "tls") == "tls") put("tlsSettings", JSONObject().apply {
                    put("serverName", params["sni"] ?: node.host)
                    params["fp"]?.takeIf { it.isNotBlank() }?.let { put("fingerprint", it) }
                    put("allowInsecure", params["allowInsecure"] == "1" || params["allowInsecure"] == "true")
                })
                when (network) {
                    "ws" -> put("wsSettings", JSONObject().apply {
                        put("path", params["path"] ?: "/")
                        params["host"]?.takeIf { it.isNotBlank() }?.let { put("headers", JSONObject().put("Host", it)) }
                    })
                    "grpc" -> put("grpcSettings", JSONObject().put("serviceName", params["serviceName"] ?: params["path"] ?: ""))
                }
            })
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
        val json = JSONObject(String(Base64.decode(node.rawLink.removePrefix("vmess://"), Base64.DEFAULT), Charsets.UTF_8))
        val uuid = json.optString("id", "")
        val network = json.optString("net", "tcp")
        val tls = json.optString("tls", "")
        val host = json.optString("host", "")
        val path = json.optString("path", "/")
        return JSONObject().apply {
            put("protocol", "vmess")
            put("settings", JSONObject().put("vnext", org.json.JSONArray().put(JSONObject().apply {
                put("address", node.host); put("port", node.port)
                put("users", org.json.JSONArray().put(JSONObject().apply {
                    put("id", uuid); put("alterId", json.optInt("aid", 0)); put("security", json.optString("scy", "auto"))
                }))
            })))
            put("streamSettings", JSONObject().apply {
                put("network", network)
                put("security", if (tls == "tls") "tls" else "none")
                if (tls == "tls") put("tlsSettings", JSONObject().apply {
                    put("serverName", json.optString("sni", host.ifBlank { node.host }))
                })
                when (network) {
                    "ws" -> put("wsSettings", JSONObject().apply {
                        put("path", path.ifBlank { "/" })
                        if (host.isNotBlank()) put("headers", JSONObject().put("Host", host))
                    })
                    "grpc" -> put("grpcSettings", JSONObject().put("serviceName", path.removePrefix("/")))
                    "http" -> put("httpSettings", JSONObject().apply {
                        put("path", path.ifBlank { "/" })
                        if (host.isNotBlank()) put("host", org.json.JSONArray().put(host))
                    })
                }
            })
        }
    }
}
EOF

cat > "$BASE/MainViewModel.kt" <<'EOF'
package com.moon.vpn

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.UUID
import javax.inject.Inject

@HiltViewModel
class MainViewModel @Inject constructor(
    private val fetcher: SubscriptionFetcher,
    private val store: SubscriptionStore
) : ViewModel() {

    private val _uiState = MutableStateFlow(MainUiState())
    val uiState: StateFlow<MainUiState> = _uiState.asStateFlow()

    init {
        _uiState.update { it.copy(subscriptions = store.load(), selectedNode = store.loadSelected()) }
    }

    fun addSubscription(url: String) {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true, error = null) }
            try {
                val body = fetcher.fetch(url).getOrThrow()
                val nodes = SubscriptionParser.parseSubscription(body)
                if (nodes.isEmpty()) throw Exception("Не найдено узлов (возможно, формат не поддерживается)")
                val newSub = Subscription(UUID.randomUUID().toString(), "Подписка ${_uiState.value.subscriptions.size + 1}", url, nodes)
                val updatedSubs = _uiState.value.subscriptions + newSub
                store.save(updatedSubs)
                val selected = _uiState.value.selectedNode ?: nodes.firstOrNull()
                if (_uiState.value.selectedNode == null) store.saveSelected(selected)
                _uiState.update { it.copy(isLoading = false, subscriptions = updatedSubs, selectedNode = selected) }
            } catch (e: Exception) {
                _uiState.update { it.copy(isLoading = false, error = e.message) }
            }
        }
    }

    fun selectNode(node: XrayNode) { store.saveSelected(node); _uiState.update { it.copy(selectedNode = node) } }
    fun setConnectionState(state: ConnState) { _uiState.update { it.copy(connectionState = state) } }
    fun setError(error: String?) { _uiState.update { it.copy(error = error) } }
    fun setScreen(screen: String) { _uiState.update { it.copy(screen = screen) } }
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
        override fun startup(): Int = 0
        override fun shutdown(): Int = 0
        override fun onEmitStatus(code: Int, message: String?): Int {
            if (code != 0) sendError("Ошибка ядра Xray: $message")
            return 0
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
        tunFd = Builder().setSession("Moon VPN").setMtu(1500)
            // Keep the app/core's own sockets outside this VPN to prevent TUN routing loops.
            .addDisallowedApplication(packageName)
            .addAddress("10.255.0.2", 32)
            .addRoute("0.0.0.0", 0)
            .addAddress("fd00:6d6f:6f6e::2", 128)
            .addRoute("::", 0)
            .addDnsServer("1.1.1.1")
            .setBlocking(true).establish()
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
        if (!prefs.getBoolean("auto_connect", false)) return
        val node = SubscriptionStore(context).loadSelected() ?: return
        if (VpnService.prepare(context) != null) return
        val cfg = try { XrayConfigBuilder.build(node) } catch (_: Exception) { return }
        ContextCompat.startForegroundService(context, Intent(context, MoonVpnService::class.java).apply { action = MoonVpnService.ACTION_CONNECT; putExtra(MoonVpnService.EXTRA_CONFIG, cfg) })
    }
}
EOF

cat > "$BASE/MainActivity.kt" <<'EOF'
package com.moon.vpn

import android.net.VpnService
import android.content.*
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.*
import androidx.core.content.ContextCompat
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.moon.vpn.ui.*
import com.moon.vpn.vpn.MoonVpnService
import dagger.hilt.android.AndroidEntryPoint

@AndroidEntryPoint
class MainActivity : ComponentActivity() {
    private var pendingConfig: String? = null
    private var activeViewModel: MainViewModel? = null
    private var pendingImportUrl by mutableStateOf<String?>(null)

    private fun extractImportUrl(intent: Intent?): String? {
        val data = intent?.data ?: return null
        val scheme = data.scheme?.lowercase() ?: return null
        val host = data.host?.lowercase() ?: return null

        // Unwrap https://ssconnect.app/?q=happ%3A%2F%2Fadd%2Fhttps%3A...
        if (scheme == "https" && host == "ssconnect.app") {
            val q = data.getQueryParameter("q")?.trim().orEmpty()
            if (q.isBlank()) return null
            val decodedQ = android.net.Uri.decode(q)
            return when {
                decodedQ.startsWith("happ://add/", true) -> decodedQ.removePrefix("happ://add/")
                decodedQ.startsWith("incy://add/", true) -> decodedQ.removePrefix("incy://add/")
                decodedQ.startsWith("https://", true) || decodedQ.startsWith("http://", true) -> decodedQ
                else -> null
            }
        }

        if (scheme == "happ" && host == "crypt") return data.toString()
        if ((scheme == "happ" && host == "add") || (scheme == "incy" && (host == "add" || host == "import"))) {
            val prefix = "$scheme://$host/"
            val payload = data.toString().substringAfter(prefix, "").trim()
            if (payload.isBlank()) return null
            val decoded = android.net.Uri.decode(payload)
            return decoded.takeIf { it.startsWith("https://", true) || it.startsWith("http://", true) }
        }
        return null
    }

    private val vpnPermLauncher = registerForActivityResult(ActivityResultContracts.StartActivityForResult()) { result ->
        val cfg = pendingConfig
        pendingConfig = null
        if (result.resultCode == RESULT_OK && cfg != null) startVpn(cfg)
        else activeViewModel?.setConnectionState(ConnState.DISCONNECTED)
    }

    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(ctx: Context?, intent: Intent?) {
            when (intent?.action) {
                MoonVpnService.ACTION_ERROR -> {
                    activeViewModel?.setError(intent.getStringExtra(MoonVpnService.EXTRA_ERROR) ?: "Неизвестная ошибка VPN")
                    activeViewModel?.setConnectionState(ConnState.ERROR)
                }
                MoonVpnService.ACTION_STATE -> {
                    val state = intent.getStringExtra(MoonVpnService.EXTRA_STATE)
                    activeViewModel?.setConnectionState(if (state == "CONNECTED") ConnState.CONNECTED else ConnState.DISCONNECTED)
                    if (state == "CONNECTED") activeViewModel?.setError(null)
                }
            }
        }
    }

    private fun startVpn(config: String) {
        ContextCompat.startForegroundService(this, Intent(this, MoonVpnService::class.java).apply {
            action = MoonVpnService.ACTION_CONNECT
            putExtra(MoonVpnService.EXTRA_CONFIG, config)
        })
        activeViewModel?.setConnectionState(ConnState.CONNECTING)
        activeViewModel?.setError(null)
    }

    private fun toggleVpn(state: MainUiState, viewModel: MainViewModel) {
        if (state.connectionState == ConnState.CONNECTED || state.connectionState == ConnState.CONNECTING) {
            startService(Intent(this, MoonVpnService::class.java).setAction(MoonVpnService.ACTION_DISCONNECT))
            viewModel.setConnectionState(ConnState.DISCONNECTED)
            return
        }
        val node = state.selectedNode
        if (node == null) {
            viewModel.setError("Сначала импортируйте подписку и выберите сервер.")
            return
        }
        try {
            val config = XrayConfigBuilder.build(node)
            val permissionIntent = VpnService.prepare(this)
            if (permissionIntent != null) {
                pendingConfig = config
                viewModel.setConnectionState(ConnState.CONNECTING)
                vpnPermLauncher.launch(permissionIntent)
            } else startVpn(config)
        } catch (e: Exception) {
            viewModel.setConnectionState(ConnState.ERROR)
            viewModel.setError("Не удалось подготовить конфигурацию: ${e.message}")
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingImportUrl = extractImportUrl(intent)
        ContextCompat.registerReceiver(this, receiver, IntentFilter().apply {
            addAction(MoonVpnService.ACTION_ERROR)
            addAction(MoonVpnService.ACTION_STATE)
        }, ContextCompat.RECEIVER_NOT_EXPORTED)

        setContent {
            val viewModel: MainViewModel = hiltViewModel()
            activeViewModel = viewModel
            val uiState by viewModel.uiState.collectAsStateWithLifecycle()
            LaunchedEffect(pendingImportUrl) {
                val importUrl = pendingImportUrl
                if (!importUrl.isNullOrBlank()) {
                    pendingImportUrl = null
                    viewModel.addSubscription(importUrl)
                }
            }
            MaterialTheme(colorScheme = darkColorScheme(background = Moon.Bg, surface = Moon.Surface)) {
                if (uiState.screen == "settings") {
                    SettingsScreen(uiState, onNavigate = viewModel::setScreen)
                } else {
                    HomeScreen(
                        state = uiState,
                        onToggleConnect = { toggleVpn(uiState, viewModel) },
                        onAddSubscription = viewModel::addSubscription,
                        onSelectNode = viewModel::selectNode,
                        onNavigate = viewModel::setScreen
                    )
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingImportUrl = extractImportUrl(intent)
    }

    override fun onDestroy() {
        activeViewModel = null
        unregisterReceiver(receiver)
        super.onDestroy()
    }
}
EOF

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
import com.airbnb.lottie.compose.*
import com.moon.vpn.*
import com.moon.vpn.R

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(state: MainUiState, onToggleConnect: () -> Unit, onAddSubscription: (String) -> Unit, onSelectNode: (XrayNode) -> Unit, onNavigate: (String) -> Unit) {
    var showBottomSheet by remember { mutableStateOf(false) }
    val sheetState = rememberModalBottomSheetState()
    var inputUrl by remember { mutableStateOf("") }
    val clipboardManager = androidx.compose.ui.platform.LocalClipboardManager.current

    Scaffold(
        containerColor = Moon.Bg,
        floatingActionButton = {
            FloatingActionButton(onClick = { showBottomSheet = true }, containerColor = Moon.Surface2, contentColor = Moon.Accent, shape = CircleShape) {
                Icon(Icons.Default.Add, contentDescription = "Добавить")
            }
        }
    ) { padding ->
        Column(Modifier.padding(padding).fillMaxSize().padding(16.dp)) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("Moon VPN", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Moon.Text)
                Spacer(Modifier.weight(1f))
                val themes = listOf(Color(0xFFDFE4EC), Color(0xFF70A5FF), Color(0xFF70C398), Color(0xFFE47C7C))
                themes.forEach { color ->
                    Box(Modifier.padding(horizontal = 4.dp).size(20.dp).clip(CircleShape).background(color).border(if (Moon.Accent == color) 2.dp else 0.dp, Moon.Text, CircleShape).clickable { Moon.Accent = color })
                }
                Spacer(Modifier.width(8.dp))
                IconButton(onClick = { onNavigate("settings") }) {
                    Icon(Icons.Default.Settings, contentDescription = "Настройки", tint = Moon.Muted)
                }
            }
            
            Box(Modifier.fillMaxWidth().padding(vertical = 24.dp), contentAlignment = Alignment.Center) {
                val composition by rememberLottieComposition(LottieCompositionSpec.RawRes(R.raw.connect_anim))
                val progress by animateLottieCompositionAsState(composition, isPlaying = state.connectionState == ConnState.CONNECTING || state.connectionState == ConnState.CONNECTED)
                
                Box(Modifier.size(160.dp).clip(CircleShape).clickable(onClick = onToggleConnect), contentAlignment = Alignment.Center) {
                    LottieAnimation(composition, progress = { progress }, modifier = Modifier.size(160.dp))
                    Icon(Icons.Default.Shield, null, tint = Moon.Text, modifier = Modifier.size(48.dp))
                }
            }

            Column(Modifier.fillMaxWidth(), horizontalAlignment = Alignment.CenterHorizontally) {
                Text(when(state.connectionState) { ConnState.CONNECTED -> "Подключено"; ConnState.CONNECTING -> "Подключение..."; else -> "Отключено" }, fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = Moon.Text)
                state.error?.let { Text(it, color = Moon.Error, fontSize = 12.sp, modifier = Modifier.padding(top = 8.dp)) }
            }

            Spacer(Modifier.height(24.dp))

            if (state.subscriptions.isEmpty()) {
                Box(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
                    Text("Нет серверов\nНажмите + чтобы добавить", color = Moon.Dim, fontSize = 14.sp, textAlign = androidx.compose.ui.text.style.TextAlign.Center)
                }
            } else {
                LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    items(state.subscriptions.flatMap { it.nodes }, key = { it.rawLink }) { node ->
                        Row(Modifier.fillMaxWidth().clip(RoundedCornerShape(12.dp)).background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(12.dp)).clickable { onSelectNode(node) }.padding(12.dp), verticalAlignment = Alignment.CenterVertically) {
                            Text(node.name, fontSize = 14.sp, color = Moon.Text, modifier = Modifier.weight(1f))
                            Text("${node.ping} мс", fontSize = 12.sp, color = Moon.Success)
                        }
                    }
                }
            }
        }
    }

    if (showBottomSheet) {
        ModalBottomSheet(onDismissRequest = { showBottomSheet = false }, sheetState = sheetState, containerColor = Moon.Surface) {
            Column(Modifier.padding(24.dp).fillMaxWidth()) {
                Text("Добавить подписку", fontSize = 20.sp, fontWeight = FontWeight.Bold, color = Moon.Text)
                Spacer(Modifier.height(16.dp))
                OutlinedTextField(
                    value = inputUrl, onValueChange = { inputUrl = it }, modifier = Modifier.fillMaxWidth(), placeholder = { Text("https://...") },
                    colors = OutlinedTextFieldDefaults.colors(focusedContainerColor = Moon.Bg, unfocusedContainerColor = Moon.Bg),
                    trailingIcon = {
                        IconButton(onClick = {
                            val clipText = clipboardManager.getText()?.text
                            if (!clipText.isNullOrBlank()) inputUrl = clipText
                        }) {
                            Icon(Icons.Default.ContentPaste, contentDescription = "Вставить", tint = Moon.Muted)
                        }
                    }
                )
                Spacer(Modifier.height(16.dp))
                Button(onClick = { if (inputUrl.isNotBlank()) { onAddSubscription(inputUrl.trim()); inputUrl = ""; showBottomSheet = false } }, enabled = inputUrl.isNotBlank() && !state.isLoading, modifier = Modifier.fillMaxWidth(), colors = ButtonDefaults.buttonColors(containerColor = Moon.Accent)) { Text(if (state.isLoading) "Загрузка…" else "Импортировать", color = Moon.Bg) }
            }
        }
    }
}
EOF

cat > "$BASE/ui/SettingsScreen.kt" <<'EOF'
package com.moon.vpn.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.moon.vpn.MainUiState
import com.moon.vpn.Moon

@Composable
fun SettingsScreen(state: MainUiState, onNavigate: (String) -> Unit) {
    val context = LocalContext.current
    val prefs = remember(context) { context.getSharedPreferences("moon_vpn_prefs", android.content.Context.MODE_PRIVATE) }
    var autoConnect by remember { mutableStateOf(prefs.getBoolean("auto_connect", false)) }
    Column(Modifier.fillMaxSize().padding(16.dp)) {
        Row(Modifier.fillMaxWidth().padding(bottom = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            IconButton(onClick = { onNavigate("home") }) { Icon(Icons.AutoMirrored.Filled.ArrowBack, null, tint = Moon.Text) }
            Text("Настройки", fontSize = 22.sp, fontWeight = FontWeight.Bold, color = Moon.Text, modifier = Modifier.padding(start = 8.dp))
        }

        LazyColumn(verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                SettingsCard(title = "Соединение") {
                    SettingsToggleRow(Icons.Default.PowerSettingsNew, "Автоподключение", "Подключаться при загрузке телефона", autoConnect) { enabled ->
                        autoConnect = enabled
                        prefs.edit().putBoolean("auto_connect", enabled).apply()
                    }
                    SettingsToggleRow(Icons.Default.Security, "Kill Switch", "Не реализован — используйте Always-on VPN в настройках Android", false, enabled = false) {}
                }
            }
            item {
                SettingsCard(title = "Сеть и Безопасность") {
                    SettingsToggleRow(Icons.Default.Block, "Moon Shield", "Пока не реализован", false, enabled = false) {}
                    SettingsToggleRow(Icons.Default.VisibilityOff, "Stealth Mode", "Пока не реализован", false, enabled = false) {}
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
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(16.dp)).background(Moon.Surface).border(1.dp, Moon.Border, RoundedCornerShape(16.dp)).padding(horizontal = 16.dp, vertical = 4.dp), content = content)
    }
}

@Composable
fun SettingsToggleRow(icon: ImageVector, title: String, desc: String, checked: Boolean, enabled: Boolean = true, onCheckedChange: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth().padding(vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Box(Modifier.size(40.dp).clip(RoundedCornerShape(10.dp)).background(Moon.Surface2), contentAlignment = Alignment.Center) {
            Icon(icon, null, tint = Moon.Accent, modifier = Modifier.size(20.dp))
        }
        Spacer(Modifier.width(16.dp))
        Column(Modifier.weight(1f)) {
            Text(title, fontSize = 15.sp, color = Moon.Text)
            Text(desc, fontSize = 12.sp, color = Moon.Dim)
        }
        Switch(checked = checked, onCheckedChange = onCheckedChange, enabled = enabled, colors = SwitchDefaults.colors(
            checkedThumbColor = Color(0xFF101216), checkedTrackColor = Moon.Accent, uncheckedThumbColor = Moon.Dim, uncheckedTrackColor = Moon.Surface3
        ))
    }
}
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
    tail -100 gradle_build.log
    echo "=========================================="
    exit 1
fi

APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$APK" ]] || die "APK не найден"
# Только теперь заменяем предыдущий сгенерированный проект.
if [[ -e "$APP_FINAL" ]]; then
    rm -rf -- "$APP_FINAL"
fi
mv -- "$APP" "$APP_FINAL"
log "ГОТОВО: $APP_FINAL/app/build/outputs/apk/debug/app-debug.apk"
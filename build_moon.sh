#!/usr/bin/env bash
set -euxo pipefail   # -x для трассировки, -e для остановки при ошибке

G='\033[0;32m'; Y='\033[1;33m'; R='\033[0;31m'; B='\033[0;34m'; C='\033[0;36m'; NC='\033[0m'
log()  { echo -e "${G}[+]${NC} $*"; }
step() { echo -e "${C}[→]${NC} $*"; }
die()  { echo -e "${R}[x]${NC} $*" >&2; exit 1; }

# ─── 1. Проверка окружения ───
step "Проверяю окружение…"
command -v java >/dev/null || die "Нужен JDK 17+"
JAVA_VER=$(java -version 2>&1 | head -1 | sed -E 's/.*"([0-9]+).*/\1/')
[[ "$JAVA_VER" -ge 17 ]] || die "Нужен JDK 17+ (у тебя $JAVA_VER)"

if [[ -z "${ANDROID_HOME:-}" ]]; then
  for d in "$HOME/Android/Sdk" "$HOME/Library/Android/sdk" "/usr/local/android-sdk" "/opt/android-sdk"; do
    [[ -d "$d" ]] && { export ANDROID_HOME="$d"; break; }
  done
fi
[[ -n "${ANDROID_HOME:-}" && -d "$ANDROID_HOME" ]] || die "ANDROID_HOME не найден"

# Устанавливаем hpwnr для расшифровки happ://crypt
if ! command -v hpwnr >/dev/null; then
  step "Устанавливаю hpwnr (для расшифровки happ://crypt)…"
  # Предполагается, что Go уже установлен в окружении GitHub Actions
  go install github.com/Omegaplexx/hpwnr@latest
  export PATH="$PATH:$(go env GOPATH)/bin"
fi

# ─── 2. Рабочая директория ───
WORK="${MOON_WORK:-$HOME/MoonVPNBuild}"
APP="$WORK/MoonVPN"
step "Рабочая директория: $WORK"
rm -rf "$APP"
mkdir -p "$APP/app/libs" \
         "$APP/app/src/main/java/com/moon/vpn/ui" \
         "$APP/app/src/main/java/com/moon/vpn/vpn" \
         "$APP/app/src/main/java/com/moon/vpn/di" \
         "$APP/app/src/main/res/values" \
         "$APP/app/src/main/res/drawable" \
         "$APP/app/src/main/res/raw" \
         "$APP/app/src/main/res/mipmap-anydpi-v26" \
         "$APP/app/src/main/res/mipmap-anydpi"

AAR="$APP/app/libs/libv2ray.aar"
step "Скачиваю libv2ray.aar…"
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://github.com/2dust/AndroidLibXrayLite/releases/latest/download/libv2ray.aar" || \
curl -fL --retry 3 --progress-bar -o "$AAR" \
  "https://sourceforge.net/projects/androidlibxraylite.mirror/files/latest/download" || \
  die "Не удалось скачать libv2ray.aar"

# ─── 3. Gradle wrapper ───
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

# ─── 4. Gradle-файлы ───
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
    // Hilt
    implementation("com.google.dagger:hilt-android:2.51.1")
    kapt("com.google.dagger:hilt-compiler:2.51.1")
    implementation("androidx.hilt:hilt-navigation-compose:1.2.0")
    // Compose & Lifecycle
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.activity:activity-compose:1.9.0")
    implementation(platform("androidx.compose:compose-bom:2024.06.00"))
    implementation("androidx.compose.ui:ui")
    implementation("androidx.compose.ui:ui-graphics")
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended:1.6.8")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.2")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.2")
    // Coroutines & OkHttp
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
    // Lottie
    implementation("com.airbnb.android:lottie-compose:6.5.2")
}
EOF

# ─── 5. Ресурсы (иконки, стили) ───
step "Генерирую иконку и анимацию Lottie…"
# ... (код для иконок и Lottie, как в предыдущем сообщении, без изменений)

# ─── 6. Kotlin-код ───
step "Генерирую Kotlin-код…"
BASE="$APP/app/src/main/java/com/moon/vpn"

# ... (MoonApplication, AppModule, MoonTheme, XrayNode, MainUiState, SubscriptionStore, SubscriptionFetcher, XrayConfigBuilder, MainViewModel, MoonVpnService, BootReceiver, MainActivity, HomeScreen — без изменений, кроме SubscriptionParser)

cat > "$BASE/SubscriptionParser.kt" <<'EOF'
package com.moon.vpn

import android.util.Base64
import java.net.URI
import java.net.URLDecoder
import java.io.BufferedReader
import java.io.InputStreamReader

object SubscriptionParser {
    fun parseSubscription(body: String): List<XrayNode> {
        val decoded = tryDecodeBase64(body).trim()
        return decoded.lineSequence()
            .map { it.trim() }.filter { it.isNotEmpty() }
            .mapNotNull { parseLink(it) }
            .filter { it.host != "0.0.0.0" && it.host != "127.0.0.1" && !it.name.contains("App not supported", true) && !it.name.contains("blocked", true) }
            .toList()
    }

    fun parseAdvancedLink(link: String): XrayNode? {
        // Расшифровка happ://crypt через hpwnr
        if (link.startsWith("happ://crypt")) {
            val decrypted = decryptHappLink(link)
            if (decrypted != null) {
                // Рекурсивно парсим расшифрованную ссылку
                return parseLink(decrypted)
            }
            return null
        }
        // Обработка happ://add (просто вырезаем URL)
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

    private fun decryptHappLink(cryptLink: String): String? {
        return try {
            val process = ProcessBuilder("hpwnr", cryptLink).redirectErrorStream(true).start()
            val reader = BufferedReader(InputStreamReader(process.inputStream))
            val output = reader.readText().trim()
            process.waitFor()
            // Предполагается, что hpwnr выводит чистую ссылку в stdout
            if (output.startsWith("http")) output else null
        } catch (e: Exception) {
            e.printStackTrace()
            null
        }
    }

    // ... (остальные методы parseLink, parseVless, parseTrojan, parseShadowsocks, parseVmess — без изменений)
}
EOF

# ... (Остальные файлы генерируются как в предыдущем сообщении)

# ─── 7. Сборка ───
step "Собираю APK…"
cd "$APP"
set +e
gradle assembleDebug --no-daemon > gradle_build.log 2>&1
BUILD_EXIT_CODE=$?
set -e

if [ $BUILD_EXIT_CODE -ne 0 ]; then
    echo -e "\n${R}🔴 СБОРКА НЕ УДАЛАСЬ${NC}"
    echo "=========================================="
    echo "ПОСЛЕДНИЕ 100 СТРОК ЛОГА:"
    echo "=========================================="
    tail -100 gradle_build.log
    echo "=========================================="
    echo "ПОИСК ОШИБОК:"
    echo "=========================================="
    grep -iE "error|failed|exception|e: " gradle_build.log || true
    echo "=========================================="
    exit 1
fi

APK="$APP/app/build/outputs/apk/debug/app-debug.apk"
[[ -f "$APK" ]] || die "APK не найден"
log "ГОТОВО: $APK"

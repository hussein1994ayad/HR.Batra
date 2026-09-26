# =========================================================================
# HR Pro — إنشاء مفتاح التوقيع الرسمي لتطبيق Android (مرة واحدة فقط)
# =========================================================================
# الاستعمال (من مجلد المشروع):
#     powershell -ExecutionPolicy Bypass -File mobile\scripts\create_release_key.ps1
#
# ماذا يفعل:
#   1. يقرأ كلمات السر والاسم المستعار من mobile\android\key.properties إذا كان
#      موجوداً، وإلا يسألك عنها (لا تظهر على الشاشة).
#   2. ينشئ mobile\android\app\release.jks بنفس القيم.
#   3. يكتب key.properties (إذا لم يكن موجوداً) ونسخة base64 من المفتاح
#      لإضافتها في GitHub Secrets باسم ANDROID_KEYSTORE_BASE64.
#
# مهم جداً: احفظ release.jks وكلمات السر في مكان آمن خارج الحاسبة
# (فلاش + مدير كلمات سر). ضياع المفتاح = لا يمكن تحديث التطبيق بعد الآن.
# الملفات الثلاثة مستبعدة من git ولن تُرفع.
# =========================================================================

$ErrorActionPreference = 'Stop'
$android = Join-Path $PSScriptRoot '..\android' | Resolve-Path
$props = Join-Path $android 'key.properties'
$jks = Join-Path $android 'app\release.jks'

if (Test-Path $jks) {
    Write-Host "المفتاح موجود مسبقاً: $jks" -ForegroundColor Yellow
    Write-Host 'لن نستبدله (استبداله يمنع تحديث النسخ المنصّبة). احذفه يدوياً إذا كنت متأكداً.'
    exit 1
}

# keytool: من Android Studio أو من JAVA_HOME
$keytool = @(
    "$env:ProgramFiles\Android\Android Studio\jbr\bin\keytool.exe",
    "$env:JAVA_HOME\bin\keytool.exe"
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $keytool) { $keytool = (Get-Command keytool -ErrorAction SilentlyContinue).Source }
if (-not $keytool) { throw 'لم أجد keytool. نصّب Android Studio أو Java ثم أعد المحاولة.' }

function Read-Secret([string]$prompt) {
    $s = Read-Host -Prompt $prompt -AsSecureString
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($s))
}

$values = @{}
$rewriteProps = $false
if (Test-Path $props) {
    Get-Content $props | ForEach-Object {
        if ($_ -match '^\s*([^#=]+?)\s*=\s*(.*)$') { $values[$Matches[1]] = $Matches[2] }
    }
    # قالب key.properties فيه نص توضيحي بدل كلمات السر؛ نتجاهله ونسأل.
    $isPlaceholder = { param($v) -not $v -or $v -match '[<>()\[\]]|[؀-ۿ]' }
    if ((& $isPlaceholder $values['storePassword']) -or (& $isPlaceholder $values['keyPassword'])) {
        $values.Remove('storePassword'); $values.Remove('keyPassword')
        $rewriteProps = $true
    } else {
        Write-Host 'استعملت القيم الموجودة في key.properties.' -ForegroundColor Cyan
    }
}
if (-not $values['keyAlias']) { $values['keyAlias'] = 'batra' }
if (-not $values['storePassword']) {
    $p1 = Read-Secret 'اختر كلمة سر للمفتاح (6 خانات على الأقل)'
    $p2 = Read-Secret 'أعد كتابتها'
    if ($p1 -ne $p2 -or $p1.Length -lt 6) { throw 'كلمتا السر غير متطابقتين أو قصيرة.' }
    $values['storePassword'] = $p1
    $values['keyPassword'] = $p1
}
if (-not $values['keyPassword']) { $values['keyPassword'] = $values['storePassword'] }
$values['storeFile'] = 'release.jks'

$org = Read-Host -Prompt 'اسم الشركة بالإنجليزي (مثلاً Batra)'
if (-not $org) { $org = 'Batra' }

& $keytool -genkeypair -v -keystore $jks -storetype JKS -keyalg RSA -keysize 2048 -validity 10000 `
    -alias $values['keyAlias'] -storepass $values['storePassword'] -keypass $values['keyPassword'] `
    -dname "CN=HR Pro, O=$org, C=IQ" | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'فشل إنشاء المفتاح.' }

if ($rewriteProps -or -not (Test-Path $props)) {
    @(
        "storeFile=$($values['storeFile'])",
        "storePassword=$($values['storePassword'])",
        "keyAlias=$($values['keyAlias'])",
        "keyPassword=$($values['keyPassword'])"
    ) | Set-Content -Encoding ascii $props
}

$b64 = Join-Path $android 'app\release.jks.base64'
[Convert]::ToBase64String([IO.File]::ReadAllBytes($jks)) | Set-Content -Encoding ascii $b64

Write-Host ''
Write-Host 'تم إنشاء مفتاح التوقيع الرسمي.' -ForegroundColor Green
Write-Host "  المفتاح:   $jks"
Write-Host "  للـ GitHub: انسخ محتوى $b64 إلى Secret باسم ANDROID_KEYSTORE_BASE64"
Write-Host '  وأضف ANDROID_KEYSTORE_PASSWORD و ANDROID_KEY_PASSWORD و ANDROID_KEY_ALIAS بنفس القيم.'
Write-Host 'احفظ نسخة من release.jks وكلمات السر خارج الحاسبة الآن.' -ForegroundColor Yellow

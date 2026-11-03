"""يظبط ملفات أندرويد اللي بيولدها flutter create: الاسم، صلاحيات اللوكيشن والكاميرا، minSdk."""
import pathlib, re

app = pathlib.Path('android/app')
manifest = app / 'src/main/AndroidManifest.xml'
m = manifest.read_text()
m = re.sub(r'android:label="[^"]*"', 'android:label="أورد على السريع"', m)
perms = ['android.permission.INTERNET',
         'android.permission.ACCESS_FINE_LOCATION',
         'android.permission.ACCESS_COARSE_LOCATION',
         'android.permission.CAMERA',
         'android.permission.FOREGROUND_SERVICE',
         'android.permission.FOREGROUND_SERVICE_LOCATION',
         'android.permission.POST_NOTIFICATIONS',
         'android.permission.WAKE_LOCK']
add = ''.join(f'    <uses-permission android:name="{p}"/>\n' for p in perms if p not in m)
m = re.sub(r'(<manifest[^>]*>\n)', r'\1' + add, m, count=1)
queries = '''
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="https"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="geo"/></intent>
        <intent><action android:name="android.intent.action.VIEW"/><data android:scheme="google.navigation"/></intent>
        <intent><action android:name="android.intent.action.DIAL"/><data android:scheme="tel"/></intent>
        <package android:name="com.whatsapp"/>
        <package android:name="com.whatsapp.w4b"/>
        <package android:name="com.google.android.apps.maps"/>'''
if '<queries>' in m:
    m = m.replace('<queries>', '<queries>' + queries, 1)
else:
    m = m.replace('</manifest>', '    <queries>' + queries + '\n    </queries>\n</manifest>')
manifest.write_text(m)

for name in ['build.gradle.kts', 'build.gradle']:
    g = app / name
    if not g.exists():
        continue
    s = g.read_text()
    s = re.sub(r'minSdk(Version)?\s*(=\s*)?flutter\.minSdkVersion', 'minSdk = 23', s)
    s = re.sub(r'ndkVersion\s*(=\s*)?flutter\.ndkVersion', 'ndkVersion = "27.0.12077973"', s)
    g.write_text(s)
    print('patched', g)

for name in ['settings.gradle.kts', 'settings.gradle']:
    st = pathlib.Path('android') / name
    if not st.exists():
        continue
    s = st.read_text()
    s = re.sub(r'(org\.jetbrains\.kotlin\.android"\)?\s*version\s*)"[^"]+"', r'\1"2.1.0"', s)
    st.write_text(s)
    print('patched', st)

print(manifest.read_text())

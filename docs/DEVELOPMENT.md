# 开发文档

本文面向项目维护者，记录本地构建、发布和 Android 签名相关流程。不要在公开文档、Issue、日志或提交中暴露真实签名密码、keystore 内容或 GitHub Secret 值。

## Android 签名配置

为避免 GitHub Release 之间、以及本地开发包与 Release 包之间出现“签名冲突”，正式发包必须使用同一份稳定 keystore。

- `flutter build apk --release` 要求存在 `android/key.properties`，否则会直接失败，不再退回 debug 签名。
- 本地配置了 `android/key.properties` 后，`debug` / `profile` / `release` 构建都会使用同一份 keystore，方便直接覆盖 GitHub Release 版本做真机调试。
- 如果没有配置 `android/key.properties`，普通 `flutter run` / debug 构建仍会使用 Android 默认 debug 签名，但不能覆盖正式 Release 包。
- `android/key.properties`、`*.jks` 和 `private_backups/` 已被 `.gitignore` 排除，不要提交到仓库。

### 本地文件

维护者本地需要保存：

```text
android/app/upload-keystore.jks
android/key.properties
```

`android/key.properties` 示例：

```properties
storePassword=<store-password>
keyPassword=<key-password>
keyAlias=upload
storeFile=upload-keystore.jks
storeType=PKCS12
certSha256=<release-certificate-sha256>
```

其中 `storeFile` 相对于 `android/app/`，例如上面的文件路径是 `android/app/upload-keystore.jks`。

> 注意：已经正式发布后不要重新生成或更换 keystore，否则用户需要卸载旧版后重新安装新版。

### 复用已有本地 debug 签名

如果维护者手机上已经安装了大量本地开发构建数据，并且这些构建一直使用本机 Android debug keystore，则可以把本机 debug keystore 固定为后续发布签名，避免维护者本人迁移数据。

本机 debug keystore 默认位置：

```powershell
$env:USERPROFILE\.android\debug.keystore
```

默认参数：

```properties
storePassword=android
keyPassword=android
keyAlias=androiddebugkey
storeFile=upload-keystore.jks
storeType=PKCS12
```

复制到项目签名位置：

```powershell
Copy-Item "$env:USERPROFILE\.android\debug.keystore" android/app/upload-keystore.jks -Force
```

再读取 SHA-256 并写入 `android/key.properties` 的 `certSha256`：

```powershell
keytool -list -v -keystore "$env:USERPROFILE\.android\debug.keystore" -storepass android -alias androiddebugkey -keypass android | findstr /C:"SHA256"
```

当前维护者本机 debug 签名 SHA-256：

```text
5383db4b85af2b86c769577135609e0c937557887fc8d77d18b08d28a0036e38
```

> 风险：debug keystore 的默认密码是公开约定值，安全性主要依赖 keystore 文件本身不泄露。若该文件泄露，其他人可以签出可覆盖安装的 APK。对公开生产项目更推荐单独 release keystore；对需要保留现有本地数据的维护者设备，可以选择复用本机 debug keystore。

### 生成新 keystore

仅在首次建立发布签名时执行。已经使用某个 keystore 发版后，应继续复用同一份文件。

```powershell
keytool -genkeypair -v `
  -keystore android/app/upload-keystore.jks `
  -storetype PKCS12 `
  -keyalg RSA `
  -keysize 2048 `
  -validity 10000 `
  -alias upload
```

查看证书指纹，填入 `key.properties` 的 `certSha256`，并同步到 GitHub Secret：

```powershell
keytool -list -v -keystore android/app/upload-keystore.jks -alias upload | findstr /C:"SHA256"
```

### 生成 GitHub Secrets

GitHub Actions 需要配置这些 Secrets：

- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_KEYSTORE_PASSWORD`
- `ANDROID_KEY_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_SIGNING_CERT_SHA256`

从本地文件读取参数：

```powershell
$props = ConvertFrom-StringData (Get-Content android/key.properties -Raw)
$props.storePassword
$props.keyPassword
$props.keyAlias
$props.certSha256
```

生成 `ANDROID_KEYSTORE_BASE64`：

```powershell
[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | Set-Clipboard
```

如果安装了 GitHub CLI，可以直接写入 Secrets：

```powershell
$props = ConvertFrom-StringData (Get-Content android/key.properties -Raw)

[Convert]::ToBase64String([IO.File]::ReadAllBytes("android/app/upload-keystore.jks")) | gh secret set ANDROID_KEYSTORE_BASE64 --body-file -
$props.storePassword | gh secret set ANDROID_KEYSTORE_PASSWORD --body-file -
$props.keyPassword | gh secret set ANDROID_KEY_PASSWORD --body-file -
$props.keyAlias | gh secret set ANDROID_KEY_ALIAS --body-file -
$props.certSha256 | gh secret set ANDROID_SIGNING_CERT_SHA256 --body-file -
```

### 校验签名配置

```powershell
cd android
.\gradlew.bat :app:validateReleaseSigning :app:validateSigningRelease
```

成功时会输出当前证书 SHA-256。若 `certSha256` 与 keystore 实际证书不一致，构建会失败。

### 本地覆盖安装建议

如果设备上已经装过较高 `versionCode` 的构建，签名一致后仍可能因为版本号回退导致安装失败。可以临时构建一个高 `versionCode` 的 debug 包覆盖安装：

```powershell
flutter build apk --debug --build-number=999999
```

生成文件：

```text
build/app/outputs/flutter-apk/app-debug.apk
```

GitHub Release 的用户可见版本号始终来自 tag，例如 `v1.2.3` 会构建为 `versionName=1.2.3`。Android 还要求一个整数 `versionCode`，工作流会从 tag 派生：

```text
versionCode = major * 1000000 + minor * 1000 + patch
```

例如 `v1.2.3` 对应 `versionCode=1002003`，可以继续覆盖上面的本地调试包。

### 旧签名版本升级说明

由于早期 GitHub APK 已经存在签名不一致的问题，修复签名后的第一个稳定版本仍无法覆盖旧签名版本。旧用户需要先在旧版中导出备份，再卸载旧版、安装新签名版本并导入备份；从新签名版本开始，后续 GitHub 更新才可以直接覆盖安装。

## 发布检查清单

发布 tag 前建议确认：

- 本地和 GitHub Actions 使用同一份 release keystore。
- `ANDROID_SIGNING_CERT_SHA256` 与 `android/key.properties` 中的 `certSha256` 一致。
- `flutter analyze` 通过。
- `flutter test` 通过。
- `dart run tool/i18n_audit.dart --check` 通过。

# Nashi mimari inceleme raporu (salt okuma, a43b956)

## Özet
1. SwiftPM: `NashiCore` (motorlar + katalog) ← `NashiApp` (AppKit/SwiftUI arayüz) ve `NashiCLI`; `NashiUpdates` (Sparkle + GitHub aktarımı) yalnız `NashiApp`'e bağlı. `UpdateCredentialBroker`, Package.swift'te target değil; ayrı bir XPC servisi olarak derleniyor.
2. 27 araç / 46 girdi / 276 rota sayısı doğrulandı: `FeatureCatalog.swift:4` ve paylaşılan `Resources/FeatureCatalog.json` (Windows bu dosyayı gömülü kaynak olarak okuyor). Harici araçlar argüman dizisiyle `Process` üzerinden çağrılıyor, shell kullanılmıyor.
3. Araç kurulumu sabitlenmiş URL ve SHA-256 ile yapılıyor, dosyalar `~/Library/Application Support/Nashi/Tools` altına geçici bir klasörden atomik taşınıyor. macOS ffmpeg/ffprobe resmî olmayan bir aynadan (osxexperts.net) geliyor ve zip hash kontrolünden önce açılıyor.
4. Credential broker, projenin eskiden **özel** bir repodan (orkunisitmak/tangerine, PAT ile) güncelleme almasından kalma. Bundle ID hâlâ `local.tangerine.replica`; proje "Tangerine replica" olarak başlamış. Repoda Tangerine'e ait ikili dosya ya da artwork bulamadım. Kod içeriğinin türetilip türetilmediğini kaynak karşılaştırmasıyla doğrulamadım.
5. Windows aynı katalogla uyumlu. Farklar: AirDrop yerine Windows Share, OCR için dil paketi gerekiyor, güncelleyici Sparkle değil kendi Ed25519 doğrulaması, PAT/broker yok. Araçlar resmî GitHub kaynaklarından geliyor ve arşiv hash'i açmadan önce kontrol ediliyor.

**Yöntem notu:** REA kullanılmadı. Repoda gönderilen bir uygulama ikilisi yok (`file` taramasında yalnız görsel, ses ve fixture çıktı), kaynak kod ise mevcut. Bu yüzden tüm bulgular doğrudan kod okumasına dayanıyor. Hiçbir betik, build ya da test çalıştırılmadı.

---

## 1. Modül haritası ve harici araçlar
**Doğrulanmış:**
- `Package.swift:15-23`:
  - `NashiCore` kaynaklarla birlikte bir kütüphane.
  - `NashiUpdates` yalnız Sparkle 2.10.0'a bağlı (exact). `path: "Sources"` kullanıyor ve dışarıdaki `TangerineUpdates/UpdateCredentialBrokerProtocol.swift` dosyasını içeri derliyor; yorumda bunun "frozen XPC wire protocol" olduğu yazıyor.
  - `NashiApp` → Core + Updates; `NashiCLI` → yalnız Core.
- Dönüştürme dağıtımı `ConversionEngine.swift:33-73`: dosya kategorisine göre `ImageEngine`, `MediaEngine`, `PDFEngine`, `DocumentEngine`, `QRCodeEngine`.
- Araçların bulunma sırası `ProcessRunner.swift:84-112`:
  1. env `NASHI_<AD>` (eski `TANGERINE_<AD>` adı da kabul ediliyor)
  2. bundle `Resources/Tools`
  3. Application Support/Nashi/Tools
  4. DEBUG derlemede repo kökü
  5. `/opt/homebrew/bin`, `/usr/local/bin`, `/usr/bin`, `/Applications/LibreOffice.app`
- Çağrı şekli `ProcessRunner.swift:13-19`: `executableURL` + `arguments` dizisi kullanılıyor, shell yok. ffmpeg/ffprobe'a otomatik `-protocol_whitelist file,pipe,crypto,data` ekleniyor; bu, uzak playlist segmentlerinin çekilmesini engelliyor. `/bin/sh` veya `-c` kullanımı yok (grep ile kontrol edildi).
- Ortam değişkeni çakışması: `ProcessRunner.swift:19`'da ebeveyn ortamı ile `environment:` parametresi birleştiriliyor ve çakışmada parametredeki değer kazanıyor. Ebeveyn ortamı yine alt sürece aktarılıyor.
- Çıkarım (doğrulanmadı): `NASHI_FFMPEG` gibi bir env değişkeni ayarlanırsa, bundle içindeki imzalı aracın yerine o ikili çalışır. Yerel bir saldırgan modeli için düşük risk.

## 2a. Finder'dan sürükle → çark → dönüştürme → çıktı
**Doğrulanmış:**
1. `NashiApplication.swift:178`: `DragMonitor` kuruluyor.
2. `Wheel.swift:232-260`: Global event monitor yerine 25 ms'lik bir zamanlayıcı fare tuşu durumunu (`CGEventSource.buttonState`) ve `NSPasteboard(name:.drag)` içeriğini yokluyor. Basılı modifier tuşu çark modunu seçiyor (convert/tools/actions).
3. `WheelController.show` (`Wheel.swift:30`) panelin içine bırakılan dosyayı `performDragOperation` ile alıyor (`:224`) ve `apply` çağrılıyor (`:86-99`). Ardından `state.perform(action)` ya da `state.select(op)` çalışıyor.
4. `AppState.swift:74-99` (`select`) → `ConversionEngine.run`.
5. `ConversionEngine.swift:8-30`: `ExportTransaction` hedef klasörde bir geçici alan açıyor, motor çıktıyı oraya yazıyor, `OutputFiles.validate` boş çıktıyı reddediyor, `transaction.publish` dosyaları `unique` adla ("ad 2.ext") taşıyor. Varsayılan hedef girdinin klasörü.

## 2b. "Download missing tools"
**Doğrulanmış** (`ExternalToolSetup.swift`):
- **Kaynaklar** (`:36-39`, `:73`):
  - ffmpeg/ffprobe: `www.osxexperts.net/ffmpeg9arm.zip` ve `ffprobe9arm.zip` (resmî değil, üçüncü taraf ayna)
  - yt-dlp 2026.08.19 ve deno v2.9.7: resmî GitHub release
  - LibreOffice 26.8.1 DMG: `download.documentfoundation.org`
  - Tüm paketler arm64. Intel Mac için yol yok.
- **Hash doğrulaması** (`:86-91`): akışlı SHA-256, sabit hex ile karşılaştırılıyor.
  - deno, yt-dlp ve DMG'de hash, açmadan ya da mount etmeden önce kontrol ediliyor.
  - ffmpeg/ffprobe ("binary" türü, `:47`, `:55`): zip **önce açılıyor**, sonra yalnız içinden çıkan ikili doğrulanıyor. Yani doğrulanmamış bir zip `ArchiveCodec.extract` tarafından ayrıştırılıyor.
  - Bunu hafifleten korumalar var: `..` / dışarı işaret eden link reddi (`ArchiveCodec.swift:142,226,262`), 100k giriş ve 20 GB sınırı.
- **İndirme** (`:94-127`): ephemeral `URLSession`, yalnız HTTPS yönlendirmesi, 400 MB tavan, 2xx kontrolü.
- **Kurulum ve yazma yeri:**
  - `stage=.media-<UUID>` → `ToolInstallation.publish` → `~/Library/Application Support/Nashi/Tools/media-v1` ya da `office-26.8.1` (`:9`, `:62-63`, `:82-83`).
  - LibreOffice: `hdiutil attach -nobrowse -readonly` ile mount, `ditto` ile kopya (`:77-80`).
  - Kurulan ikililerin kod imzası ya da quarantine kontrolü yok.
- **Çıkarım:** Gerçek bütünlük güvencesi sabitlenmiş hash'ten geliyor. Hash'ler repo commit'iyle geldiği için güven kökü repo/imzalı bundle.

## 3. TangerineUpdates / UpdateCredentialBroker / Reference
**Doğrulanmış:**
- **Broker'ın amacı:**
  - `UpdateBrandMigration.swift:6-24`: eski kanal `orkunisitmak/tangerine`, yeni kanal `orkunisitmak/nashi`. Keychain hesabı bilerek eski isimde tutuluyor; amaç rebrand sonrası PAT'in yeniden sorulmaması (`:3-4`, `:9`).
  - `AppUpdater.swift:36-41`: `TangerineUpdateGitHub*` tercihleri, `requiresToken`.
  - `GitHubUpdateTransport.swift:228`: token varsa `Authorization: Bearer` başlığı ekleniyor.
  - Sonuç: uygulama başlangıçta **özel** bir GitHub reposundan, PAT ile güncelleme çekiyordu. Broker bu PAT'i Keychain'de tutan, karşılıklı kimlik doğrulamalı bir XPC servisi.
- **Broker'ın güvenlik tasarımı:**
  - Çağıran gereksinimi: `identifier` + `certificate leaf` SHA-1 (`UpdateCredentialBroker.swift:18-24`).
  - Info.plist'ten servis ikilisi ve bundle'ı için SHA-256 pin'leri.
  - UID eşleşmesi (`Sources/UpdateCredentialBroker/main.swift:10-12`).
  - Token için CLI ya da stdout arayüzü yok.
  - Keychain servisi `local.tangerine.replica.github-updates` (`main.swift:38`).
- **Bugünkü durum:**
  - Info.plist'te `NashiPublicUpdateRepository` + `SUFeedURL` varsa `PublicUpdateChannel` resmî **anonim** kanalı sabitliyor ve eski `tangerine`/`nashi` özel kanal tercihlerini siliyor; Keychain'e dokunmuyor (`PublicUpdateChannel.swift:3-28`).
  - Kullanıcı yine de "özel kanal" bağlayabiliyor (`requiresToken`). Broker bu amaçla ve geriye dönük uyumluluk için duruyor.
  - Sparkle tarafında `SUPublicEDKey` var, `SURequireSignedFeed` ve `SUVerifyUpdateBeforeExtraction` zorunlu (`UpdateConfiguration.swift:22-47`).
- **Köken:**
  - Broker ve protokol dosyalarının başında "Adapted from the Tendedero personal fork credential broker" yazıyor.
  - Lisans: `Resources/licenses/Tendedero-MIT.txt`, MIT, © 2026 Alejandro Buján. Yani bu kod üçüncü taraf, MIT lisanslı bir projeden geliyor; Tangerine'den değil.
- **Tangerine izleri:**
  - `Info.plist:33` `CFBundleIdentifier = local.tangerine.replica`
  - `@objc(TangerineUpdateCredentialBrokerProtocol)` (`UpdateCredentialBrokerProtocol.swift:6`)
  - XPC servis kimliği `local.tangerine.replica.credentials.v1`
  - imza anahtarı hesabı `local.tangerine.replica` (`scripts/prepare-public-release.sh:16`)
  - Tangerine'den geçiş kullanıcılarına mesaj (`Views.swift:131`)
  - Bunlar adlandırma izleri; "replica" kelimesi projenin Tangerine kopyası olarak başladığını gösteriyor.
- **Reference/ klasörü:**
  - `archive-fixtures`: libarchive test RAR dosyaları; kaynak URL ve sha256 `sources.json` içinde, yanında `COPYING.libarchive` var.
  - `document-fixtures/rich.pdf`: 2 sayfalık bir PDF, kaynağı belirtilmemiş.
  - Tangerine ile ilgili bir şey yok.
- **"Proprietary binary/artwork yok" iddiası:**
  - Repodaki tüm metin dışı dosyalar `file` ile tarandı: Nashi markalı PNG/ICNS/ICO, demo medya, fixture'lar. Mach-O ya da başka bir uygulama ikilisi yok.
  - `Resources/Tools` repoda değil; build sırasında ekleniyor (`build-app.sh:80-83`).
  - İddia ikili dosyalar ve artwork için **tutarlı**.
- **Doğrulanmadı / varsayım:**
  - Kaynak kodun Tangerine ikilisinin tersine mühendisliğinden türeyip türemediği. Tangerine ikilisiyle bir karşılaştırma yapılmadı (REA ile yapılabilir).
  - Git geçmişi 2026-10-19'da başlıyor (538 commit, ilk commit zaten olgun bir Windows işi). Erken geçmiş muhtemelen ayıklanmış ya da squash edilmiş, bu yüzden kökeni geçmişten izleyemedim.
  - `Info.plist:39`'da sürüm 0.7.14 görünüyor, tag ise v0.7.9-40. Uyuşmazlığın nedenini kontrol etmedim.

## 4. macOS ↔ Windows parite
**Doğrulanmış:**
- **Ortak katalog:** `windows/Nashi.Core/Nashi.Core.csproj:12` aynı `FeatureCatalog.json`'u gömüyor. Seçeneklerin aynı olması bu dosyayla güvence altında. Davranışın aynı olduğu ise ayrı testlere dayanıyor (`FEATURE-PARITY.md:5`).
- **Belgelenmiş farklar** (`FEATURE-PARITY.md:26`):
  - AirDrop yok, yerine Windows Share.
  - OCR için Windows dil paketi gerekiyor.
  - Önizleme Windows codec'leriyle, gerekirse FFmpeg proxy ile yapılıyor.
  - Modifier tuşları farklı: Ctrl araçlar, Shift dönüştürme, Alt dosya işlemleri.
- **Kodda görülen, belgede olmayan farklar:**
  - *Güncelleyici:* Windows Sparkle kullanmıyor. `windows-update.json` + BouncyCastle Ed25519 doğrulaması, 64 KB manifest ve 3 GB açılma sınırı (`PublicUpdates.cs:8-46`). PAT ya da credential broker yok; sadece anonim kanal (grep'te `Authorization`/`Bearer` çıkmadı).
  - *Araç kaynakları:*
    - Windows ffmpeg resmî GyanD build'i (GitHub). LibreOffice MSI için iki kaynak var: stable ve arşiv (`Toolchain.cs:43-45`, `OfficeRuntime.cs:39`).
    - Hash her zaman arşiv açılmadan önce kontrol ediliyor (`Toolchain.cs:51-52`). Bu macOS'tan daha sıkı.
    - Windows x64, macOS arm64-only.
  - *Shell:*
    - Terminal aksiyonu powershell/terminal'i `UseShellExecute=false` ile açıyor (`FileActions.cs:29`).
    - `OpenUrl` `UseShellExecute=true` kullanıyor (`MainWindow.cs:120`). Dışarıdan gelen bir URL buraya ulaşırsa şema kontrolü gerekir; çağıranları kontrol etmedim.
    - `Reveal` yolu tırnaklıyor (`MainWindow.cs:121`).

## Önerilen takip (opsiyonel)
- `MainWindow.OpenUrl`'ün çağıranlarını ve şema kısıtını kontrol et.
- macOS ffmpeg kaynağını resmî bir yayına taşı ya da zip hash'ini açmadan önce doğrula.
- Kaynak kodda Tangerine'den türetme olup olmadığı önemliyse, Tangerine.app ile REA karşılaştırması yap (`compare_artifacts` / `analyze_swift_types`).

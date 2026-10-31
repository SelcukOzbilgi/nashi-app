# Nashi fork planı

Taban: upstream `main` @ `5d2cbfc` (2026-10-31). İnceleme `a43b956` üzerinde yapıldı; arada 120 commit var.
Bu taban sabit; iş bitene kadar upstream'i çekme.

## Kararlar

- **Ad:** Nashi (değişmiyor).
- **Bundle ID:** varsayılan olarak `local.tangerine.replica` kalıyor. XPC servis adı, Keychain hesapları ve
  `UpdateBrandMigration` buna bağlı; upstream Nashi bu Mac'te kurulu değil, çakışma yok. Değiştirmek ancak build
  sistemi bunu tek yerden parametreleştiriyorsa yapılır.
- **Güncellemeler:** Fork build'i upstream'in appcast'inden güncelleme almamalı (aksi halde upstream sürümü fork'un
  üzerine yazar). Önce `scripts/build-app.sh`, `scripts/signing-configuration.sh`, `scripts/configure-updates.py`
  ve `Sources/NashiUpdates/UpdateConfiguration.swift` içinde mevcut geliştirici/ad-hoc modunu bul; yeni mekanizma
  icat etme. Upstream'den yenilik almak = `git merge upstream/main` + yeniden build.
- **Hedef:** macOS arm64, yerel build, `/Applications/Nashi.app`.
- **Harici araçlar:** Uygulamanın kendi kurulum ekranı (ffmpeg, yt-dlp, deno, LibreOffice). Homebrew ffmpeg
  `/opt/homebrew/bin/ffmpeg` zaten kurulu ve `ProcessRunner` bunu yedek olarak buluyor.

## Aşama 0: fork hijyeni ve build

1. `.github/workflows/owner-auto-merge.yml`, `scripts/owner-auto-merge.py` (+ testi) ve `.mergify.yml` fork'tan
   kaldırılır. `public-update.yml` fork'ta çalışmamalı (sil ya da repo koşulu ekle).
2. `source.yml` filtreli `swift test` yerine tam `swift test` koşar.
3. Güncelleme kanalı yukarıdaki karara göre kapatılır.
4. Build: `scripts/setup-exiftool.sh`, `swift build --product Nashi`, `swift test`, `scripts/build-app.sh release`.

## Aşama 1: düzeltmeler (her biri ayrı commit + test)

Önce her bulguyu `5d2cbfc` üzerinde yeniden doğrula; upstream düzeltmişse atla ve not et.

| # | Bulgu | Düzeltme |
|---|---|---|
| 1 | `PDFOfficeCodec.rasterPNG`: `Int(ceil(...))` sınır kontrolünden önce; PDF→ODT yolları (`PDFDocumentReconstruction.swift` preservePages + editable) devasa MediaBox'ta çöküyor | Sonluluk + üst sınır kontrolünü `rasterPNG` içine taşı; 1e20 MediaBox fikstürüyle iki yolu da test et |
| 2 | Sınırsız bellek ayırma: `PDFOfficeCodec` OCR yolu (`recognizedCells`), `PDFEngine` compress (`shown.width*dpi/72`) | Aynı üst sınır |
| 3 | `ProcessRunner`: iptal yalnız doğrudan çocuğa gidiyor, `group.wait()` süresiz; `terminateAll` beklemiyor | `WebDownloadProcess`'teki deseni uygula: süreç grubu (`POSIX_SPAWN_SETPGROUP`), `kill(-pid)`, zaman aşımlı bekleme |
| 4 | `ExternalToolSetup`: osxexperts ffmpeg/ffprobe zip'i hash kontrolünden önce açılıyor | Arşivin kendi SHA-256'sını sabitle ve açmadan önce doğrula. Hash'i belirlerken: zip'i indir, aç, içindeki ikilinin mevcut sabit hash'le eşleştiğini doğrula, sonra zip hash'ini sabitle |
| 5 | `WebDownloadEngine` (macOS) loopback/özel IP adreslerini ve oraya yönlendirmeleri kabul ediyor; Windows reddediyor | Windows'taki kuralla eşitle |
| 6 | Windows `DocumentConversion.cs`: HTML/EPUB → png/jpg/Pages/sabit EPUB dalları `SanitizedHtml`'i atlıyor | Temizliği tüm dallardan önce uygula; `\\` ve `file:` ile başlayan kaynakları reddet. Doğrulama fork CI'ında |
| 7 | Windows `UpdateInstaller`/`PublicUpdates`: imza kontrolü ile çıkarma arasında TOCTOU | Tek handle, `FileShare.None` (fork CI) |
| 8 | ExifTool `t/` test klasörü (4.4 MB, örnek ikililer) .app içine giriyor | `build-app.sh`'te hariç tut |

Kapsam dışı (not edildi): Windows'ta LibreOffice'i ağsız çalıştırma (AppContainer), HTML→PDF yan dosya gömme
(bilinçli tasarım), kalite slider aralıklarının platformlar arası eşitlenmesi.

## Teslim

- Fork'ta PR (`efe/fork-setup` → `main`), CI yeşil.
- `build/Nashi.app` → `/Applications/Nashi.app`. Yerelde derlendiği için quarantine bayrağı yok, Gatekeeper uyarısı çıkmaz.

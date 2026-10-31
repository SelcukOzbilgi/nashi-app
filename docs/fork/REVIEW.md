# Nashi (orkunisitmak/nashi-app) — birleşik inceleme

Kaynak: commit a43b956 · dağıtım: v0.7.14-45 · 2026-10-31
Statik inceleme: repodaki hiçbir betik, build, test ya da uygulama çalıştırılmadı.

## Ürün
Tangerine'in sürükle-çark etkileşimini örnek alan, MIT lisanslı dosya dönüştürme/düzenleme uygulaması.
macOS (Swift, ~15.8k satır, yalnız arm64) ve Windows (C#, .NET 10, self-contained). 27 araç, 46 girdi formatı,
276 rota (README ile tutarlı). "Tangerine replica" olarak başlamış: bundle id `local.tangerine.replica`.
Repoda Tangerine'e ait ikili ya da görsel yok. Kodun tersine mühendislikle türetilip türetilmediği kontrol edilmedi.

## Bulgular (önem sırasıyla)

| # | Önem | Bulgu | Yer |
|---|---|---|---|
| 1 | Orta | Windows: HTML/EPUB → png/jpg/Pages/sabit EPUB dalları `SanitizedHtml`'i atlıyor, LibreOffice ağ kısıtı olmadan çalışıyor (macOS'ta sandbox-exec ile ağ engelli). IP, NetNTLM ya da yerel dosya sızabilir | windows/Nashi.Windows/DocumentConversion.cs:40-49, windows/Nashi.Core/OfficeDocuments.cs:28-35 |
| 2 | Orta | Owner PR'ları değişen dosyalara bakılmadan auto-merge ediliyor; Mergify'daki hassas yol kuralı yalnız gözlem yapıyor. AI dalları da bu yoldan merge ediliyor | scripts/owner-auto-merge.py, .mergify.yml |
| 3 | Orta | macOS CI 368 testin yalnız 116'sını koşuyor; ersinkoc fix PR'larının 7 regresyon testi hiç koşmuyor | .github/workflows/source.yml:56-67 |
| 4 | Orta | Düzeltilmemiş çökme: `rasterPNG` içindeki `Int(ceil(...))` sınır kontrolünden önce çalışıyor; PDF→ODT yollarından devasa MediaBox'lı bir PDF çökertir | Sources/NashiCore/PDFOfficeCodec.swift:22, PDFDocumentReconstruction.swift:17,169 |
| 5 | Orta | Dağıtım dosyaları OS düzeyinde imzasız: macOS kendinden imzalı, hardened runtime ve notarization yok; Windows'ta Authenticode yok. Windows ikilisi açık repoda bulunmayan bir commit'ten (681c4fe2) derlenmiş | release v0.7.14-45 |
| 6 | Düşük | `ProcessRunner` iptalde alt süreçleri öldürmüyor ve süresiz bekliyor (LibreOffice Cancel takılabilir). Çözüm deseni WebDownloadProcess'te var | Sources/NashiCore/ProcessRunner.swift:10-70 |
| 7 | Düşük | macOS ffmpeg resmî olmayan aynadan (osxexperts.net) iniyor; zip hash kontrolünden önce açılıyor | ExternalToolSetup.swift:35-55 |
| 8 | Düşük | Sınırsız bellek ayırma (OCR ve compress yolları) | PDFOfficeCodec.swift:69-105, PDFEngine.swift:131 |
| 9 | Düşük | Windows güncellemesinde TOCTOU; macOS web indirmesi loopback/özel IP'leri kabul ediyor; HTML→PDF yandaki dosyaları gömebiliyor | UpdateInstaller.cs:16-18, WebDownloadEngine.swift:26-34, HTMLPDFRenderer.swift:119-136 |
| 10 | Düşük | Test/smoke kodu üretim binary'sinde; kalite slider'ı iki platformda farklı aralığa eşleniyor; ExifTool test klasörü (4.4 MB) ve .pdb pakette | NashiApp/*Smoke.swift, MediaEngine.swift:598 / MediaEngine.cs:369 |

## Sağlam olanlar
- Güncelleme zinciri: Sparkle 2.10.0 imzalı feed zorunlu, arşiv çıkarılmadan önce doğrulanıyor, downgrade yok. Windows'ta Ed25519 + sürüm eşleşmesi. Canlı release'deki üç Ed25519 imzası geçerli, SHA256SUMS tutuyor.
- Shell kullanılmıyor. yt-dlp `--ignore-config` ve `--`, ffmpeg `-protocol_whitelist`, exiftool `-config ""`, LibreOffice'te makro güvenliği 3.
- Arşivlerde zip-slip ve symlink koruması, EPUB'da XXE kapalı. Repoda ya da 538 commit'lik geçmişte sızmış sır yok.
- CI'da `pull_request_target` yok, `secrets.*` kullanılmıyor, action'lar SHA ile sabitlenmiş. İmzalama CI dışında.

## Bağlam
Repo 12 günlük, 538 commit; erken geçmiş sıkıştırılmış. Commit'lerin 150'si ersinkoc'tan. İnsan incelemesi yok,
46 PR yaklaşık 15 dakikada birleştirilmiş.

## Doğrulanmayanlar
Testler çalıştırılmadı (çökme senaryoları kod okumasından). LibreOffice/WebKit çalışma zamanı davranışı denenmedi.
Authenticode zinciri ve notarization sunucu tarafı sorgulanmadı. Tangerine.app ile kod karşılaştırması yapılmadı.

Ajan raporları: ~/.claude/plans/act-as-the-research-streamed-sundae.md (mimari),
~/.claude/plans/act-as-the-review-soft-trinket.md (güvenlik). Release dosyaları: artifacts/v0.7.14-45/

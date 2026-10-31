# Efe'nin Nashi fork'u

Upstream `orkunisitmak/nashi-app` (MIT), Tangerine'den esinlenen dosya dönüştürme uygulaması. Bu fork, Efe'nin kendi Mac'inde kullanacağı sürüm: inceleme raporundaki sorunlar düzeltilmiş, upstream'den kendiliğinden güncellenmeyen bir Nashi.

## Repo ve remote'lar

- `origin` = `SelcukOzbilgi/nashi-app` (fork, public). `gh` varsayılanı bu repo.
- `upstream` = `orkunisitmak/nashi-app`; push kapalı. Upstream'e PR açma.
- PR'lar her zaman `--repo SelcukOzbilgi/nashi-app --base main` ile. Çalışma dalları `efe/<konu>`.
- Upstream çok hızlı ilerliyor (dakikada birkaç PR). Upstream'i iş ortasında takip etme; `git merge upstream/main` ayrı ve bilinçli bir adım.

## Belgeler

- `docs/fork/PLAN.md`: kararlar, aşamalar, build komutları.
- `docs/fork/REVIEW.md`: birleşik inceleme raporu (upstream a43b956). Satır numaraları eski olabilir; her bulguyu güncel kodda yeniden doğrula.
- `docs/fork/security-review.md`, `docs/fork/architecture.md`: ajan raporlarının tamamı.

## Kurallar

- Uygulama adı **Nashi** kalır; "EFE" gibi ekler yok.
- Fork değişiklikleri küçük ve ayrı commit'ler halinde; upstream ile merge kolay kalsın.
- Hedef macOS (Apple Silicon). Windows düzeltmeleri yalnız fork CI'ında doğrulanabilir (yerelde dotnet yok).
- Yerelde Xcode araç zinciri `DEVELOPER_DIR` ile seçilir (aktif dizin CommandLineTools, orada XCTest yok):
  `export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`
- Değişiklikten sonra `swift test` (tam paket). Sonucu söyle; geçmeyen testi gizleme.
- Commit mesajı `<tür>: <açıklama>`; attribution satırı yok.
- Sırlar `.env`'de ya da Keychain'de; koda, loga, commit'e girmez.

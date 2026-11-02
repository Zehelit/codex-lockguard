# Yapı ve ayar yaşam döngüsü

## İki görev, iki yardımcı süreç

Windows Görev Zamanlayıcısı ana görevi paketli uygulama açılışındaki AppModel-Runtime/Admin 201 olayıyla veya kullanıcı oturum açılışıyla tetikler. Olay filtresi iki desteklenen AUMID'yi içerir. Görev aynı kullanıcının `InteractiveToken` bağlamında, `HighestAvailable` düzeyinde çalışır. Olaydaki kimlik sürüm içermez; uygulama EXE'sinin yerini çözmek gerekmez.

Ana süreç aynı Windows oturumundaki süreçleri native paket API'leriyle inceler. Aile adı yanında AUMID de doğrulanır; uygulamadan uzun yaşayabilen bir RuntimeBroker, uygulama açıkmış gibi sayılmaz. PID'nin yeniden kullanımını ayırt etmek için süreç başlangıç zamanı da tutulur.

Ayrı Watchdog süreci ana sürecin gerçek process nesnesinin çıkışını bekler. Yedek hâlâ o ana sürece aitse geri yükler. İki süreç aynı kullanıcı/oturum mutex'iyle çakışmayı önler. Kilitli oturumda bazı ekran koruyucu API işlemleri bekleyebilir; yedek korunur. Kurtarmada doğrulanan tamamlanma olmadan yedek silinmez.

İkinci görev normal yetkiyle kimlik denetimi yapar. Daha geniş uygulama açılış olaylarını ve oturum açılışını izler; böylece dar ana filtre artık eşleşmiyorsa desteklenen adlar üzerinden değişiklik fark edilebilir. Kurulumda mevcut olan desteklenen uygulamalar `installation.json` içinde beklenen listeye alınır. Sadece tek uygulama kurulmuşsa diğerinin eksikliği hata değildir. Beklenen uygulama sonradan bilerek kaldırıldıysa kurulumu yenilemek bu listeyi günceller.

## Yönetilen değerler

| Konum | Uygulama açıkken istenen değer | Geri yükleme |
| --- | --- | --- |
| Kullanıcı `Control Panel\Desktop\DelayLockInterval` | DWORD `0xffffffff` | Varlık, tür ve asıl içerik |
| Kullanıcı `Control Panel\Desktop\ScreenSaverIsSecure` | REG_SZ `0` | Varlık, tür ve asıl içerik |
| Kullanıcı Winlogon `EnableGoodbye` | DWORD `0` | Varlık, tür ve asıl içerik |
| Çalışma zamanı `SPI_SETSCREENSAVESECURE` | Parola gereksinimi kapalı | Önceki çalışma zamanı değeri |
| Aktif güç planı `CONSOLELOCK` AC/DC | `0` / `0` | Her karşılaşılan plan için ayrı yedek |

`CONSOLELOCK` Windows'un uykudan dönüşte parola gereksinimi ayarıdır; tek başına bütün otomatik kilit yollarını kapatan evrensel bir anahtar değildir. Ayrı kullanıcı ayarları bu yüzden birlikte yönetilir. `DelayLockInterval` özel değerinin her Windows sürümünde aynı sonucu vereceği varsayılmaz. [Microsoft CONSOLELOCK açıklaması](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/no-subgroup-settings-prompt-for-password-on-resume).

Kullanıcı kayıtları doğrudan mevcut SID altından okunur/yazılır. Paketli uygulama bağlamındaki farklı HKCU görünümlerinin yanlış doğrulama üretmesini azaltmak için Windows StdRegProv kullanılır. Makine politikaları okunur; değiştirilmez. Ayar yazıldıktan sonra okuma ile doğrulanır.

## Başlatma, izleme ve çıkış

İlk değişiklikten önce `settings-backup.json` atomik yazılır. Uygulama açıkken yaklaşık her 10 saniye ve işlem süresi sonunda ayarlar, süreçler ve oturum durumu yeniden değerlendirilir. Yeni güç planında eski planın yedeği ezilmez. Değişiklik gerekmiyorsa gereksiz güç ayarı yazımı yapılmaz.

Son hedefin kapandığı görüldüğünde ek tolerans beklenmez. Önce bütün yedeklenen ayarlar geri yüklenir, sonuç okunarak doğrulanır; ardından controller çıkar. Bekleyen veya başarısız geri yükleme, başarılı gibi sunulmaz. Güncelleme sırasında uygulama tamamen kapanmış görünürse aynı davranış uygulanır; sonraki açılış olayı yeniden başlatır.

Ekranın kapanma süresi, ekran koruyucu etkinliği/dosyası/zaman aşımı yalnız değişmezlik kontrolü için okunur. Bu değerler yazılmaz. Script sisteme uyanık kalma isteği veya sahte kullanıcı girdisi göndermez.

## Durum ve veri sınırı

`controller.json` süreç ve yapılandırmayı, `health.json` son ana süreç gözlemini, `events.jsonl` geçiş ve hataları içerir. `Status` çağrısı ayrıca canlı sorgu yapar; eski sağlık dosyasını tek başına güncel durum saymaz. `LockPreventionProven` otomatik doğru yapılmaz.

Kurulum kodu Program Files altında, yalnız yönetici/SYSTEM tarafından değiştirilebilen bir konumda tutulur. Görev normal kullanıcıya sabit görevi okuma/başlatma hakkı verir; değiştirme hakkı vermez. Çalışma yedeği kullanıcının LocalAppData alanındadır ve aynı kullanıcı tarafından değiştirilebilir. Bu tasarım, aynı kullanıcının kötü niyetli yerel koduna karşı ayrı bir güvenlik sınırı oluşturduğu iddiasını taşımaz.

Günlükler olay ve hata oluşunca büyür; otomatik günlük döndürme henüz yoktur. Aktif controller/yedek dosyalarını temizlemeyin. Uzun süreli kullanımlarda günlük boyutunu takip edip paylaşım öncesi kişisel değerleri silin.

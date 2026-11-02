# codex-lockguard

Windows'ta paketli Codex veya ChatGPT masaüstü uygulaması açıkken otomatik kilitle ilgili belirli ayarları geçici yöneten bir PowerShell yardımcısıdır. Ekranın kapanmasına ve ekran koruyucuya izin verir. Son desteklenen uygulama kapandığında kaydettiği eski ayarları geri yükler ve çıkar.

## Neden bu scripte ihtiyaç duyuldu?

Codex'i telefondan kullanırken bilgisayar başında klavye ve fare hareketi olmayabilir. Bilgisayar çalışıyor ve internete bağlı olsa bile Windows, boşta kalan masaüstü oturumunu kilitleyebilir. Böyle bir durumda sohbet sürerken masaüstü uygulamalarını kullanan otomasyonlar kilit ekranında kalabilir.

Burada birbirinden farklı üç durum var: ekranın güç tasarrufu için kapanması, ekran koruyucunun devreye girmesi ve Windows oturumunun kilitlenmesi. İhtiyaç, ekranı sürekli açık tutmak değil; uygulama açıkken otomatik kilitle ilgili ayarları geçici olarak yönetmekti. `codex-lockguard` bu ihtiyaçtan doğdu.

Bu proje OpenAI'nin resmî bir bileşeni değildir. İlk uygulaması kişisel bir Windows bilgisayarında geliştirilip kullanıldı; farklı Windows sürümleri, cihaz yönetimi politikaları ve uygulama dağıtımları için evrensel başarı iddiası yoktur.

## Ne yapar?

- Codex ve ChatGPT süreçlerini sürümsüz paket ailesi ve uygulama kimliğiyle tanır. Uygulamanın her güncellemede değişebilen EXE klasörünü izlemez.
- Yönetilecek ayarların ilk değerlerini diske kaydeder; ardından uygulama çalıştığı sürece bu değerleri denetler ve sapmaları düzeltir.
- Aktif güç planı değişirse yeni planın ilgili değerlerini de değiştirmeden önce yedekler.
- Gerçek Windows oturumunun kilitli olup olmadığını ayrıca sorgular. Ayarların doğru olmasıyla oturumun açık olması ayrı ayrı raporlanır.
- Son hedef uygulama kapandığında kayıtlı ayarları geri yükler. Ek kapanış toleransı varsayılan olarak **0 saniyedir**.
- Ana süreç beklenmedik şekilde kapanırsa ayrı kurtarma süreci geri yüklemeyi dener.
- Uygulama kimliği kaybolursa veya tanınmayan bir Codex/ChatGPT kimliği görünürse Türkçe bir uyarı penceresi gösterir.

Ana kontrol döngüsünün varsayılan beklemesi **10 saniyedir**; Windows API işlemlerinin süresi buna eklenir. Bu kontrolleri yerel PowerShell süreci yapar. Her döngüde bir dil modeli veya internet servisi çağrılmaz. Ayarlar döngüler arasında da uygulanmış kalır. Uygulamanın kapanması ve ayar sapması bir sonraki kontrolde algılandığından, 0 saniye ek tolerans anında algılama anlamına gelmez.

Script ekran kapanma süresini, ekran koruyucu dosyasını, etkinliğini veya başlama süresini değiştirmez. Ekranı açık tutma isteği göndermez, yapay klavye/fare hareketi üretmez. Uyku modunu da kapatmaz; bilgisayar gerçekten uyursa uzaktan çalışma durabilir.

## Kapsamı ve sınırları

Bu yardımcı açık bir kilidi çözmez; PIN, parola veya Windows Hello bilgisini saklamaz. Win+L ile elle kilitlemeyi ya da TeamViewer gibi başka bir programın açıkça kilitleme çağrısı yapmasını engelleme garantisi vermez. Örneğin uzaktan erişim uygulamasının bağlantı sonunda kilitleme tercihi ayrı değerlendirilmelidir.

Koruma, bir sohbetin çalışmasına değil **desteklenen masaüstü uygulamasının açık olmasına** bağlıdır. Uygulamayı saatlerce açık bırakırsanız ayarlar da o süre boyunca uygulanabilir. Kilit gereksiniminin azaltılması, bilgisayarın başına fiziksel olarak gelen birinin açık oturuma erişebilmesi anlamına gelir. Kendi kullanım koşullarınıza göre karar verin.

Zorunlu GPO/MDM kilit politikası saptanırsa script bunu hata olarak bildirir; kurum politikasını değiştirmez. Denetlenen politikaların listesi tüm olası Windows kilit nedenlerini kapsadığı iddiasını taşımaz. Tek kullanıcının etkileşimli oturumu hedeflenmiştir. Çok kullanıcılı eşzamanlı oturumlarda kullanılması önerilmez; güç planı ayarı diğer oturumları da etkileyebilir.

## Gereksinimler

- 64 bit Windows ve **Windows PowerShell 5.1** (`powershell.exe`). Paket Windows 11 üzerinde geliştirildi; Windows 10 için ayrıca uçtan uca doğrulama yapılmadı.
- Aşağıdaki paketli uygulamalardan en az biri. İkisinin birlikte kurulu olması gerekmez.
- Aynı Windows kullanıcısı için yönetici yükseltmesine izin veren bir hesap. Standart kullanıcıdan başka bir yönetici hesabının parolasını girerek kurulum bu tasarımda desteklenmez; kullanıcı SID'si değişirse işlem reddedilir.
- Çalışır Windows Görev Zamanlayıcısı ve etkin `Microsoft-Windows-AppModel-Runtime/Admin` olay kanalı.
- Uyarı penceresini derlemek için Windows'un .NET Framework / Windows Forms bileşenleri. Python, Node.js veya ücretli bir servis gerekmez.

| Uygulama | Desteklenen AUMID |
| --- | --- |
| Codex | `OpenAI.Codex_2p2nqsd0c76g0!App` |
| ChatGPT masaüstü | `OpenAI.ChatGPT-Desktop_2p2nqsd0c76g0!ChatGPT` |

Normal sürüm güncellemeleri bu kimlikleri koruduğunda EXE yolunun değişmesi sorun oluşturmaz. Üretici paket ailesini, AUMID'yi veya açılış olayı mekanizmasını değiştirirse tanımın güncellenmesi gerekir. Kimlik denetimi, desteklenen adlar üzerinden fark edebildiği değişiklikleri uyarır; her olası ürün adı değişimini tanıyamaz.

## İnsanlar için kurulum

1. Bu reponun **Code → Download ZIP** seçeneğiyle kaynaklarını indirin ve ZIP'i bir klasöre çıkarın. Git kullanıyorsanız aşağıdaki komutlarla alabilirsiniz.
2. Kodları ve bu açıklamayı inceleyin. Paketli Codex veya ChatGPT uygulamasını kurup en az bir kez açın. İlk doğrulama için uygulamayı açık bırakmanız yararlı olur.
3. Çıkardığınız klasörde **`Install.cmd`** dosyasını çalıştırın. PowerShell için gelen Windows UAC isteğini **aynı Windows hesabıyla** onaylayın. Windows'un güvenlik uyarısını otomatik olarak aşmaya çalışmayın.
4. Kurulumdan sonra **`Status.cmd`** dosyasını çalıştırın. Başarıyı yalnız pencerenin kapanmasıyla değerlendirmeyin; aşağıdaki durum alanlarını kontrol edin.

```powershell
git clone https://github.com/Zehelit/codex-lockguard.git
cd codex-lockguard
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Elevate
```

`ExecutionPolicy Bypass` yalnız bu PowerShell çağrısına aittir; sistemin kalıcı yürütme politikası değiştirilmez. Kurulum sırasında UAC atlatılmaz. Codex'in “Tam erişim” seçeneği Windows yönetici token'ı sağlamaz.

Kurulum, dosyaları `%ProgramFiles%\CodexLockGuard` altına kopyalar ve uyarı penceresini `IdentityAlert.cs` kaynağından burada derler. Repoda hazır EXE bulunmaz. Kullanıcıya özel iki görev oluşturulur: yükseltilmiş ana koruma görevi ve normal yetkili kimlik denetimi görevi. Görevler parola saklamayan `InteractiveToken` kullanır; ana görevin çalışması için kullanıcı oturumunun açılmış olması gerekir.

Uygulama açılış olayları ve kullanıcı oturum açılışı başlangıcı tetikler. Ana görev, uygulama yoksa kısa başlangıç beklemesinin ardından çıkar. Görev Zamanlayıcısı yeni olayı bekler; sürekli açık kalan bir uygulama arama süreci yoktur. Uygulama açıldığında koruma birkaç saniyelik başlatma ve doğrulama işlemlerinden sonra uygulanır.

### Durumu doğrulama

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramFiles\CodexLockGuard\Codex-LockGuard.ps1" -Mode Status
```

Uygulama açıkken `Running=true`, `Health.ConfigurationMatches=true` ve `LastControllerObservation.LastError=null` beklenir. `Controller.PollSeconds` kontrol beklemesini gösterir. `LastControllerObservation.WindowsAdministrator=true` ve `ResumePolicyWriteAccessCode=0`, ana sürecin korumalı güç ayarına erişimini gösterir. Durum komutunu normal yetkiyle çağırdıysanız `Health.WindowsAdministrator=false` ve bu sorgu sürecinin erişim kodu 5 olabilir; ana sürecin kaydı ayrı değerlendirilmelidir.

`SessionState=unlocked`, oturumun o anda açık olduğunu belirtir. `ConfiguredButSessionLocked`, ayarlar uygulanmış olsa bile oturumun kilitli olduğunu söyler. `LockPreventionProven=false` bilerek korunur; tek bir başarılı durum sorgusu uzun süreli kilit önleme kanıtı sayılmaz.

İlk kullanımda ekranın normal süresinde kapanmasına izin verip oturum durumunu uzaktan yeniden sorgulayın. Ekranın fiziksel olarak kapandığını yalnız bu JSON çıktısından çıkarmayın. Bilgisayarda yapılan fare/klavye hareketi boşta kalma gözlemini etkileyebilir.

### Kontrol sıklığını değiştirme ve güncelleme

Aynı kurulumu yeniden çalıştırmak dosyaları ve görevleri günceller. Örneğin 20 saniyelik bekleme için:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Elevate -PollSeconds 20
```

İzin verilen aralık 1–60 saniyedir. Daha uzun bekleme ayar sapmasını ve uygulama kapanışını daha geç algılar. Güncelleme sırasında önceki ayarlar normal şekilde geri yüklenir; yeni yardımcı başlayana kadar kısa bir korumasız aralık oluşabilir. Önceki dosyalar korumalı kurulum dizinindeki `.rollback-*` klasöründe tutulur. Kurulum hatasında eski dosya ve görev tanımları geri alınmaya çalışılır; geri alma başarısı da ayrı raporlanır.

### Durdurma ve kaldırma

Otomatik başlangıcı kaldırmak için **`Uninstall.cmd`** çalıştırın ve aynı hesabın UAC isteğini onaylayın. Kurulum klasöründeki `Uninstall.ps1` ile de kaldırabilirsiniz:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramFiles\CodexLockGuard\Uninstall.ps1" -Elevate
```

Kaldırıcı görevleri devre dışı bırakır, ana yardımcıyı normal şekilde durdurur, ayarların geri yüklendiğini doğrular ve görevleri kaldırır. Dosyalar teşhis ve elle kurtarma için diskte bırakılır. Geri yükleme bekliyorsa görevler devre dışı ve yedek korunmuş kalır; oturumu açıp işlemi yeniden deneyin. Geri yükleme doğrulanmadan yedekleri silmeyin.

Yalnız `-Mode Stop` çağırmak kurulu otomatik başlangıç görevlerini kaldırmaz. Sonraki uygulama açılışı korumayı yeniden başlatabilir.

## Agentlar için kurulum rehberi

Agentın önce [AGENTS.md](AGENTS.md) ve [ayrıntılı agent rehberini](docs/AGENT-KURULUMU.md) okuması gerekir. Önerilen sıra:

1. Kullanıcının kurulumu ve otomatik kilit ayarlarının değişmesini istediğini doğrulayın. Durum sorgusu ile kurulumu ayırın.
2. `Install.ps1 -PrepareOnly` ile kullanıcı, uygulama kimlikleri, hedef konum ve görev planını değiştirmeden inceleyin.
3. `tests\Test-GuardLogic.ps1` ile çevrimdışı kontrolleri; etkileşimli Windows oturumunda `-ReadOnlyNative` ekleyerek salt okunur yerel kontrolleri çalıştırın.
4. Yetkili kurulum için `Install.ps1 -Elevate` kullanın. Kullanıcının Windows UAC onayı gereklidir. Başka hesabın parolasını istemeyin, onayı otomasyonla aşmayın.
5. `%LOCALAPPDATA%\CodexLockGuard\install-result.json` içindeki `Passed=true` sonucunu ve bağımsız canlı `-Mode Status` çıktısını birlikte kontrol edin.
6. Kullanıcının açık uygulamasını test için kapatmayın. Ekran kapanma ve gerçek kilit davranışı testini ayrı bir kullanıcı adımı olarak yürütün; yalnız ayar kontrolünü uçtan uca başarı diye raporlamayın.

## Scriptin yapısı

| Dosya | Görevi |
| --- | --- |
| `Codex-LockGuard.ps1` | Süreç algılama, ayar yedeği, denetim, onarım, geri yükleme ve durum raporu |
| `Install.ps1` / `Install.cmd` | Ön kontrol, UAC başlatma, korumalı kopya, görev kurulumu ve doğrulama |
| `Uninstall.ps1` / `Uninstall.cmd` | Görevleri kapatma, geri yüklemeyi doğrulama ve görevleri kaldırma |
| `Check-AppIdentity.ps1` | Başlat menüsü kimliklerini kontrol etme ve değişiklik uyarısı |
| `IdentityAlert.cs` | Türkçe uyarı penceresinin C# kaynağı |
| `Build-IdentityAlert.ps1` | Windows Forms yardımcısını yerel olarak derleme |
| `Protection.ps1` | Kurulum konumundaki yazma izinlerinin salt okunur denetimi |
| `Status.cmd` | Kurulu yardımcıya durum sorgusu gönderme |
| `tests/Test-GuardLogic.ps1` | Ayar değiştirmeyen kaynak, kimlik ve isteğe bağlı Windows kontrolleri |

PowerShell içindeki C# bölümü; paket kimliği, WTS oturum durumu, güç planı ve ekran koruyucu API'lerini çağırır. Ana süreç `Run`, ayrı kurtarma süreci `Watchdog` modundadır. Kurtarma süreci normalde ana sürecin çıkışını bekler; sürekli yoğun bir yoklama yapmaz. Başarısız geri yükleme tekrarlarının beklemesi ana kontrol aralığından ayrıdır.

Yönetilen ayarların listesi ve geri yükleme ayrıntıları [mimari belgesinde](docs/MIMARI.md) bulunur.

## Kayıtlar ve gizlilik

`%LOCALAPPDATA%\CodexLockGuard` altında ayar yedeği, controller bilgisi, sağlık kaydı, olay günlüğü, kimlik durumu ve kurulum sonucu tutulur. Bu kayıtlar kullanıcı SID'si, yerel yollar ve süreç kimlikleri içerebilir. Scriptin kendisi bunları bir sunucuya göndermez. Issue açarken çıktıları gözden geçirip kişisel değerleri temizleyin.

Repodaki `.gitignore`, çalışma kayıtlarını ve derlenmiş dosyaları dışarıda bırakır. Canlı kayıtlar, kişisel teşhis arşivleri ve kullanıcıya özel görev XML'leri bu repoya dahil değildir.

## Hata durumunda

| Belirti | Kontrol edilecek nokta |
| --- | --- |
| Win32 5 / erişim reddedildi | Ana süreç gerçekten yükseltilmiş mi? Codex tam erişimi Windows yükseltmesi değildir. |
| `BlockedByPolicy` | Raporlanan GPO/MDM kuralını inceleyin; script bunu aşmaya çalışmaz. |
| `PendingRuntimeAfterUnlock` | Windows kilidi açıkken yeniden değerlendirmeyi bekleyin. Script mevcut kilidi açmaz. |
| `RestoreFailed` / `PendingRestoreAfterUnlock` | Yedeği tutun, oturumu açın; kaldırıcıyı veya yükseltilmiş `-Mode Restore` işlemini yeniden deneyin. |
| Uygulama açık ama yardımcı yok | Görev geçmişi, AppModel olay kanalı ve beklenen AUMID'yi kontrol edin. |
| Uygulama kimliği uyarısı | Bilerek kaldırılan uygulama için kurulumu yenileyin; yeni kimliği kaynaktan doğrulamadan güvenilir listeye eklemeyin. |

Elektrik kesilmesi veya iki yardımcı sürecin birlikte sonlandırılması o anda geri yüklemeyi engelleyebilir. Yedek diskte kalır; sonraki başlangıç kurtarmayı dener. Elle kurtarma öncesinde otomatik görevleri devre dışı bırakın ve ana sürecin çalışmadığını doğrulayın. `-Mode Restore` yönetici yetkisi ister; tamamlanmadığında yedek korunur.

## Doğrulama durumu

Önceki yerel sürümde yönetici API erişimi, ayar geri yükleme, uygulamaya bağlı başlangıç ve bilgisayar yeniden açıldıktan sonraki çalışma gözlendi. Kullanıcının ekran kapalı bildirdiği bir kontrolde oturum açık kaldı. Bu geçmiş gözlem bütün bilgisayarlarda başarı garantisi değildir.

Bu repoya hazırlanırken yapılan kontrollerin kapsamı ve yeni kurulum dosyasının henüz gerçek bir temiz makinede çalıştırılmadığı sınırı [doğrulama belgesinde](docs/DOGRULAMA.md) açıkça yazılıdır.

## Teknik kaynaklar ve lisans

- [Microsoft: uykudan dönüşte parola gereksinimi / CONSOLELOCK](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/no-subgroup-settings-prompt-for-password-on-resume)
- [Microsoft: görevlerin kullanıcı ve yükseltme bağlamı](https://learn.microsoft.com/en-us/windows/win32/taskschd/security-contexts-for-running-tasks)
- [Microsoft: SystemParametersInfoW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-systemparametersinfow)
- [Microsoft: paket ailesi sorgusu](https://learn.microsoft.com/en-us/windows/win32/api/appmodel/nf-appmodel-getpackagefamilyname)

`DelayLockInterval=0xffffffff` uygulamada kullanılan bir yaklaşımdır; belgelenmiş ve değişmez bir Win32 sözleşmesi olarak sunulmaz. Script bu değere tek başına güvenmez ve gerçek oturum durumunu ayrıca raporlar.

Proje [MIT lisansı](LICENSE) ile yayımlanmıştır. Lisansın standart hukuk metni İngilizcedir; kullanım ve kurulum belgeleri Türkçedir.

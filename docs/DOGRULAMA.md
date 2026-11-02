# Doğrulama kapsamı

Bu belge, yerel gözlemlerle yayımlanan paketin kontrollerini ayırır. Gerçek kullanıcıya ait günlükler, SID'ler, görev XML'leri ve ayar yedekleri repoya eklenmez.

## Önceki yerel kurulum

Windows 11 üzerindeki önceki yardımcı sürümünde korumalı güç API erişimi, ayar yazma/okuma ve geri yükleme, uygulama kimliğiyle otomatik başlangıç, 0 saniye ek kapanış toleransı ve 10 saniyelik kontrol beklemesi doğrulandı. Bilgisayar yeniden açıldıktan sonra uygulama açılışıyla otomatik çalışma gözlendi. Kullanıcının ekranı kapalı bildirdiği bir anda yaklaşık 39 dakikalık kesintisiz açık oturum kaydı vardı. Monitörün fiziksel güç durumu bağımsız ölçülmedi.

Bu gözlemler farklı Windows sürümlerini, bütün uyku/dönüş senaryolarını, MDM/GPO ortamlarını veya çok kullanıcılı oturumları kapsamaz.

## Public paket hazırlanırken

- PowerShell dosyalarının sözdizimi denetlendi.
- Korunan konumda Users yazma hakkı, yalnız ACL değiştirme hakkı ve Windows'un SYSTEM/yönetici/TrustedInstaller izinleri için ayrı senaryolar denetlendi.
- Yalnız Codex, yalnız ChatGPT, ikisi birlikte, beklenen uygulamanın kaybolması, bilinmeyen aile/AUMID, bilinen ek Başlat menüsü kaydı ve ilgisiz uygulama senaryoları denetlendi.
- `Install.ps1 -PrepareOnly` gerçek yerel envanterle çalıştırıldı. Oluşan XML'lerin ayrıştırılması, parola saklamayan oturum türü, görevlerin yükseltme düzeyleri ve sürümsüz açılış filtresi kontrol edildi.
- Native C# bölümünün derlenmesi ve gerçek Windows oturum/ayar sorgusu ayrı geçici durum klasöründe yapıldı. Ayar uygulanmadı; üretim controller'ı durdurulmadı.
- Uyarı yardımcısı kaynak koddan derlendi; uyarı penceresi açılmadı.
- Yayın ağacı kişisel SID, kişisel profil yolu ve kimlik bilgisi örüntüleri açısından tarandı. Hazır ikili dosyalar ve yerel çalışma kayıtları dışarıda bırakıldı.

**Bu repodaki yeniden düzenlenmiş kurucu gerçek kurulum modunda mevcut bilgisayara uygulanmadı.** Temiz Windows makinesinde kurulum/kaldırma, kurulum hatasında geri alma ve gerçek yeni uygulama kimliğiyle uyarı davranışı uçtan uca henüz doğrulanmış değildir. Salt okunur test başarısı bunların yerine geçmez.

## Tekrar çalıştırılabilir kontroller

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuardLogic.ps1
```

Bu komut Windows ayarlarını değiştirmez. Etkileşimli Windows oturumunda desteklenen uygulama kuruluysa:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuardLogic.ps1 -ReadOnlyNative
```

Derleme kontrolü:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Build-IdentityAlert.ps1
```

Son komut yalnız kaynak klasöründe `IdentityAlert.exe` üretir. Bu dosya `.gitignore` ile dışarıda bırakılır. Otomatik CI, etkileşimli uygulama envanterine ihtiyaç duymayan testleri ve derlemeyi yürütür; gerçek masaüstü kilit davranışını test etmez.

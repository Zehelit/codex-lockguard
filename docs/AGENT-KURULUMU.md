# Agentlar için ayrıntılı kurulum rehberi

## Önce kapsamı belirleyin

Kullanıcının isteği yalnız durum kontrolüyse `-Mode Status` çalıştırın. Kurulum, güncelleme veya kaldırma istemiyorsa bu işlemleri yapmayın. Desteklenen hesap, aynı kullanıcı adına yükseltme yapabilen bir Windows yönetici hesabıdır. Bir standart kullanıcının oturumunda başka yöneticinin hesabıyla çalıştırmak desteklenmez.

İncelenen kaynak klasörüyle `%ProgramFiles%\CodexLockGuard` altındaki çalışan kopya farklı olabilir. Önce hangi kopyaya müdahale ettiğinizi yazın. Agentın dosya sistemi erişimi ile Windows token yetkisi ayrı kavramlardır.

## 1. Salt okunur hazırlık

Kaynak klasöründe Windows PowerShell 5.1 ile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -PrepareOnly
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuardLogic.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Test-GuardLogic.ps1 -ReadOnlyNative
```

Son komut etkileşimli oturum ve desteklenen kurulu uygulama ister. İlk komut görev XML'lerini yalnız çıktı olarak üretir; görev kaydetmez veya ayar değiştirmez. Kullanıcı SID'sini, desteklenen AUMID listesini ve görev argümanlarını kontrol edin. Başka kullanıcı adına bir değer üretmeyin. Makinede sadece Codex veya sadece ChatGPT bulunması yeterlidir.

## 2. Kurulum ve Windows onayı

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1 -Elevate -PollSeconds 10
```

Bu çağrı aynı hesabın SID'sini yükseltilmiş sürece geçirir. UAC bekleniyorsa kullanıcıya hangi işlem için onay gerektiğini söyleyin. Onay yokken kurulmuş gibi rapor vermeyin. UAC reddini dosya izni veya API hatasıyla karıştırmayın. Kurucu, kaynakları sabit korumalı klasöre kopyalar; bu klasöre normal kullanıcı yazma hakkı eklemeyin.

Kurulum ana hedef uygulamayı kapatmaz. Mevcut yardımcı varsa ayarları normal şekilde geri yükleyerek durdurur; yeni sürümü başlatır. Değişim aralığında eski ayarlar geçerli olabilir. Uygulamanın kendisini kapatıp açma testini ancak kullanıcı ayrıca istediğinde yapın.

## 3. Bağımsız doğrulama

```powershell
Get-Content -Raw "$env:LOCALAPPDATA\CodexLockGuard\install-result.json" | ConvertFrom-Json
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$env:ProgramFiles\CodexLockGuard\Codex-LockGuard.ps1" -Mode Status
Get-ScheduledTask | Where-Object TaskName -like 'CodexLockGuard*'
```

`Passed=true`, tek başına uzun süreli kilit önleme kanıtı değildir. Uygulama açıkken çalışan PID ve başlangıç kimliği, güncel ana süreç sağlık zamanı, ayar uyumu, hata alanı, yükseltilmiş ana süreç ve güç ayarı erişimini birlikte değerlendirin. Uygulama yokken yardımcının başlangıç beklemesinden sonra çıkması normaldir.

Durum sorgusundaki `Health` o sorguyu çalıştıran sürece aittir. Ana yardımcının yetki bilgisi için `LastControllerObservation` alanını kullanın. Normal yetkili durum sorgusunun yazma erişimi 5 olabilir; bu, yükseltilmiş ana sürecin başarısız olduğu anlamına gelmez.

`Controller.PollSeconds=10` ve görevde `-PollSeconds 10` birlikte doğrulanmalıdır. Görev XML'inde sürümlü WindowsApps EXE yolu olmamalıdır. Oturum açıkken `SessionState=unlocked` görülür. Kilitli oturumda “ayarlar eşleşiyor” sonucu kilidin çözüldüğü anlamına gelmez.

## 4. Gerçek davranış kontrolü

Kullanıcı ekranın normal süresinde kapanmasına izin verir. Yerel klavye/fare ile boşta kalmayı sıfırlamadan oturum durumunu yeniden sorgulayın. Monitörün fiziksel durumunu bağımsız ölçmediyseniz ekran kapalı bilgisinin kullanıcı bildirimine dayandığını yazın. Önceki sağlık kaydı, yeni bir kilit olayı veya elektrik kesilmesi sonrasındaki duruma kanıt değildir.

Bilgisayarı uyandırma, kilidi açma, uyku modunu kapatma, ekran süresini kısaltma veya TeamViewer ayarını değiştirme bu kurulumun zorunlu adımı değildir. Bunları otomatik eklemeyin.

## 5. Hata ve geri alma

`install-result.json` içinde `Error` ve varsa `RollbackError` alanlarını okuyun. Yalnız işlem çıkış koduna güvenmeyin. `settings-backup.json` duruyorsa geri yüklemenin tamamlandığını varsaymayın. Kilit açılmasını gerektiren bir Windows API işlemi bekliyorsa oturum açıldıktan sonra yeniden değerlendirin.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Uninstall.ps1 -Elevate
```

Kaldırma sonucunu görevlerin yokluğu, çalışmayan controller ve geri yükleme yedeğinin kapanmasıyla doğrulayın. Kaldırıcı program dosyalarını ve geçmiş günlükleri bilerek bırakır. Otomatik olarak tüm klasörü silmeyin.

## Raporlama ve yayın

Kısa raporda işlem, saat, kullanılan kopya, çalışan PID, ayar uyumu, oturum durumu ve henüz yapılmayan davranış kontrolünü belirtin. Ham günlükler kullanıcı SID'si ve profil yolu içerebilir. GitHub'a aktarırken kişisel değerleri temizleyin; gerçek kullanıcı yedeğini örnek dosya olarak kullanmayın.

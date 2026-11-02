# Agentlar için çalışma kuralları

Bu repo Windows oturumunun otomatik kilit ayarlarını değiştirir. Önce README.md ve docs/AGENT-KURULUMU.md dosyalarını okuyun.

- Doğrulanmayan bir davranışı çalışıyor diye bildirmeyin. Kaynak kontrolü, salt okunur durum sorgusu, kurulum ve gerçek boşta kalma davranışı ayrı kanıtlardır.
- Kod inceleme, commit veya dokümantasyon isteği yerel bilgisayara kurulum izni sayılmaz. Kurulumu yalnız kullanıcı istediğinde yapın.
- Çalışan Codex/ChatGPT uygulamasını veya üretim yardımcısını test amacıyla kapatmayın.
- Windows UAC isteğini kullanıcı onaylar. Başka hesapla yükseltme, onay atlatma, parola saklama veya geniş ACL izni verme eklemeyin.
- PowerShell 5.1 Türkçe metinleri doğru okusun diye .ps1 dosyalarını UTF-8 BOM ile kaydedin. Sözdizimi ve kimlik testlerini değişikliklerden sonra çalıştırın.
- tests/Test-GuardLogic.ps1 ayar değiştirmez. -ReadOnlyNative seçeneği etkileşimli Windows ve desteklenen kurulu uygulama gerektirir. Bu seçeneği CI başarısı için zorlamayın.
- Kişisel SID, profil yolu, olay günlüğü, canlı JSON yedeği, kimlik bilgisi veya derlenmiş EXE commit etmeyin.
- Public repo hazırlığını yerel çalışan kurulumla karıştırmayın. Güncelleme yaptığınızda görev argümanı, kurulu dosya ve canlı controller verisini ayrı doğrulayın.
- Yeni bağımlılık gerekmiyor. Native Windows API sınırlarını ve hata/geri yükleme davranışını koruyun.

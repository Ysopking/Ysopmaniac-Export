import 'dart:math';

class MirrorLogic {
  // HOCHWERTIGE MOBILE USER-AGENTS (Premium Devices)
  static const List<String> _userAgents = [
    'Mozilla/5.0 (iPhone; CPU iPhone OS 17_3_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Mobile/15E148 Safari/604.1',
    'Mozilla/5.0 (Linux; Android 14; Pixel 8 Pro Build/UQ1A.240205.002) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.6167.164 Mobile Safari/537.36',
    'Mozilla/5.0 (Linux; Android 14; Samsung SM-S928B) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.6167.164 Mobile Safari/537.36',
  ];

  static String getRandomUserAgent() {
    return _userAgents[Random().nextInt(_userAgents.length)];
  }

  // MOBILE STEALTH SHIELD: Tarnung optimiert für Handheld-Geräte
  static String getStealthShieldJs() {
    return """
      (function() {
        // 1. WebDriver & Automation Flags löschen
        Object.defineProperty(navigator, 'webdriver', { get: () => undefined });
        window.chrome = { runtime: {} };

        // 2. Mobile Hardware Simulation (Touch-Support emulieren)
        Object.defineProperty(navigator, 'maxTouchPoints', { get: () => 10 });

        // 3. Hardware Fingerprint (Verschleierung der App-Umgebung)
        Object.defineProperty(navigator, 'platform', { get: () => 'iPhone' });
        Object.defineProperty(navigator, 'vendor', { get: () => 'Apple Computer, Inc.' });

        // 4. Client Hints (Moderne Anti-Bot Umgehung)
        if (navigator.userAgentData) {
          Object.defineProperty(navigator, 'userAgentData', {
            get: () => ({
              mobile: true,
              brands: [
                { brand: 'Google Chrome', version: '121' },
                { brand: 'Chromium', version: '121' },
                { brand: 'Not A(Brand', version: '99' }
              ]
            })
          });
        }

        // 5. UI Cleanup (Consent Killer)
        const selectors = ['[id*="cookie"]', '[class*="cookie"]', '[id*="consent"]', '[class*="consent"]'];
        selectors.forEach(s => document.querySelectorAll(s).forEach(el => el.style.display = 'none'));
      })();
    """;
  }
}

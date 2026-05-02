class GeoLocation {
  final String country;
  final String region;
  final String city;
  final String zip;

  GeoLocation({
    required this.country,
    required this.region,
    required this.city,
    required this.zip,
  });
}

class GeoDataService {
  static final GeoDataService _instance = GeoDataService._internal();
  factory GeoDataService() => _instance;
  GeoDataService._internal();

  // Beispielhafte Struktur für die lokale Datenbank
  // In einer finalen Version würde dies aus einer JSON-Datei geladen
  final Map<String, dynamic> _mockData = {
    'Deutschland': {
      'Baden-Württemberg': {
        'Freiburg': ['79098', '79100', '79102'],
        'Stuttgart': ['70173', '70174'],
      },
      'Bayern': {
        'München': ['80331', '80333'],
      }
    },
    'USA': {
      'California': {
        'San Francisco': ['94102', '94103'],
        'Los Angeles': ['90001', '90002'],
      }
    }
  };

  List<String> getCountries() => _mockData.keys.toList();

  List<String> getRegions(String country) {
    if (!_mockData.containsKey(country)) return [];
    return (_mockData[country] as Map<String, dynamic>).keys.toList();
  }

  List<String> getCities(String country, String region) {
    if (!_mockData.containsKey(country) ||
        !_mockData[country].containsKey(region)) {
      return [];
    }
    return (_mockData[country][region] as Map<String, dynamic>).keys.toList();
  }

  List<String> getZipCodes(String country, String region, String city) {
    if (!_mockData.containsKey(country) ||
        !_mockData[country].containsKey(region) ||
        !_mockData[country][region].containsKey(city)) {
      return [];
    }
    return List<String>.from(_mockData[country][region][city]);
  }

  String optimizeQuery(String query, GeoLocation? location) {
    if (location == null) return query;

    String optimized = query;
    if (location.zip.isNotEmpty) {
      optimized += " ${location.zip}";
    } else if (location.city.isNotEmpty) {
      optimized += " ${location.city}";
    } else if (location.country.isNotEmpty) {
      optimized += " ${location.country}";
    }
    return optimized;
  }
}

import 'package:hive/hive.dart';

part 'provider.g.dart';

@HiveType(typeId: 4)
class Provider extends HiveObject {
  @HiveField(0)
  String name;

  @HiveField(1)
  String? contact;

  @HiveField(2)
  String rubro;

  @HiveField(3)
  DateTime createdAt;

  Provider({
    required this.name,
    this.contact,
    required this.rubro,
    required this.createdAt,
  });

  // Helper method to get formatted contact info
  String get formattedContact {
    if (contact == null || contact!.isEmpty) {
      return 'Sin contacto';
    }
    
    // Check if it looks like a phone number
    final cleanContact = contact!.replaceAll(RegExp(r'[^\d+]'), '');
    if (cleanContact.length >= 8) {
      return '📱 $contact';
    }
    
    return '📞 $contact';
  }

  // Helper method to check if contact can use WhatsApp
  bool get canUseWhatsApp {
    if (contact == null || contact!.isEmpty) return false;
    
    // Check if it's a phone number (at least 8 digits)
    final cleanContact = contact!.replaceAll(RegExp(r'[^\d+]'), '');
    return cleanContact.length >= 8;
  }

  // Helper method to get clean phone number for WhatsApp
  String? get whatsappNumber {
    if (!canUseWhatsApp) return null;
    return contact;
  }

  // Helper method to get display info
  String get displayInfo {
    if (contact == null || contact!.isEmpty) {
      return name;
    }
    return '$name • ${formattedContact}';
  }

  // Helper method to check if contact is WhatsApp-like
  bool get hasWhatsApp {
    if (contact == null) return false;
    final lower = contact!.toLowerCase();
    return lower.contains('whatsapp') ||
           lower.contains('wsp') ||
           lower.contains('wa');
  }

  // Helper method to check if the free-text contact field is actually a
  // website/social-media link (some providers give a link instead of a
  // phone number, e.g. an Instagram page or a catalog site).
  bool get hasWebsiteLink {
    if (contact == null || contact!.isEmpty) return false;
    final trimmed = contact!.trim();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://');
  }

  // Helper method to get the raw website/social link, if any -- exactly
  // what the user typed into the "Contacto" field, unvalidated.
  String? get websiteLink {
    if (!hasWebsiteLink) return null;
    return contact!.trim();
  }

  // Helper method to get rubro with emoji
  String get rubroWithEmoji {
    switch (rubro) {
      case 'Ropa':
        return '👗 Ropa';
      case 'Bijouterie':
        return '💎 Bijouterie';
      case 'Pedicura':
        return '💅 Pedicura';
      case 'Manicura':
        return '💅 Manicura';
      case 'Belleza':
        return '✨ Belleza';
      case 'Accesorios':
        return '👜 Accesorios';
      case 'Calzado':
        return '👠 Calzado';
      case 'Cosméticos':
        return '💄 Cosméticos';
      case 'Herramientas':
        return '🔧 Herramientas';
      case 'Otros':
        return '📦 Otros';
      default:
        return '📦 $rubro';
    }
  }

  // Static method to get all available rubros
  static List<String> get availableRubros => [
    'Ropa',
    'Bijouterie',
    'Pedicura',
    'Manicura',
    'Belleza',
    'Accesorios',
    'Calzado',
    'Cosméticos',
    'Herramientas',
    'Otros',
  ];

  @override
  String toString() => name;

  /// Convert provider to JSON for backup
  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'rubro': rubro,
      'createdAt': createdAt.toIso8601String(),
      'contact': contact,
    };
  }

  /// Create provider from JSON for restore
  static Provider fromJson(Map<String, dynamic> json) {
    return Provider(
      name: json['name'] as String,
      rubro: json['rubro'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
      contact: json['contact'] as String?,
    );
  }
}
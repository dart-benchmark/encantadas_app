/// Helpers para búsqueda y filtrado tolerante a acentos / mayúsculas.
library;

const Map<String, String> _accentMap = {
  'á': 'a', 'à': 'a', 'ä': 'a', 'â': 'a', 'ã': 'a',
  'é': 'e', 'è': 'e', 'ë': 'e', 'ê': 'e',
  'í': 'i', 'ì': 'i', 'ï': 'i', 'î': 'i',
  'ó': 'o', 'ò': 'o', 'ö': 'o', 'ô': 'o', 'õ': 'o',
  'ú': 'u', 'ù': 'u', 'ü': 'u', 'û': 'u',
  'ñ': 'n',
  'Á': 'A', 'À': 'A', 'Ä': 'A', 'Â': 'A', 'Ã': 'A',
  'É': 'E', 'È': 'E', 'Ë': 'E', 'Ê': 'E',
  'Í': 'I', 'Ì': 'I', 'Ï': 'I', 'Î': 'I',
  'Ó': 'O', 'Ò': 'O', 'Ö': 'O', 'Ô': 'O', 'Õ': 'O',
  'Ú': 'U', 'Ù': 'U', 'Ü': 'U', 'Û': 'U',
  'Ñ': 'N',
};

/// Normaliza un texto para búsqueda: lowercase + sin acentos + trim.
/// "Pulsera Ñandú" -> "pulsera nandu"
String normalizeForSearch(String input) {
  final lower = input.toLowerCase().trim();
  final buffer = StringBuffer();
  for (var i = 0; i < lower.length; i++) {
    final ch = lower[i];
    buffer.write(_accentMap[ch] ?? ch);
  }
  return buffer.toString();
}

/// True si `query` aparece como substring en cualquiera de los campos
/// (todos normalizados).
bool matchesQuery(String query, Iterable<String?> fields) {
  if (query.isEmpty) return true;
  final q = normalizeForSearch(query);
  if (q.isEmpty) return true;
  for (final f in fields) {
    if (f == null) continue;
    if (normalizeForSearch(f).contains(q)) return true;
  }
  return false;
}

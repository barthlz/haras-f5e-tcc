/// Formato visual brasileiro; o banco Supabase continua recebendo YYYY-MM-DD.
String formatDateBr(Object? date) {
  if (date == null) return '—';
  final raw = date.toString().trim();
  if (raw.isEmpty) return '—';
  final match = RegExp(r'^(\d{4})-(\d{2})-(\d{2})(?:$|[T ])').firstMatch(raw);
  if (match == null) return raw; // Não modificar valores desconhecidos.
  return '${match.group(3)}/${match.group(2)}/${match.group(1)}';
}

/// Aceita somente DD/MM/AAAA válido e devolve a data ISO para enviar ao banco.
/// Também aceita ISO de dados legados, sem alterar seu significado.
String? dateBrToIso(String input) {
  final raw = input.trim();
  final br = RegExp(r'^(\d{2})/(\d{2})/(\d{4})$').firstMatch(raw);
  final iso = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(raw);
  final dateMatch = br ?? iso;
  if (dateMatch == null) return null;
  final day = int.parse(dateMatch.group(br != null ? 1 : 3)!);
  final month = int.parse(dateMatch.group(2)!);
  final year = int.parse(dateMatch.group(br != null ? 3 : 1)!);
  if (year < 1 ||
      year > 9999 ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  final parsed = DateTime(year, month, day);
  if (parsed.year != year || parsed.month != month || parsed.day != day) {
    return null;
  }
  return '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-'
      '${day.toString().padLeft(2, '0')}';
}

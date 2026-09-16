/// Turns raw exceptions into short Portuguese messages for the UI.
String userFacingError(Object error) {
  final raw = error.toString();
  final lower = raw.toLowerCase();

  if (lower.contains('socketexception') ||
      lower.contains('failed host lookup') ||
      lower.contains('network') ||
      lower.contains('connection')) {
    return 'Sem conexão com a internet. Tente de novo.';
  }
  if (lower.contains('jwt') ||
      lower.contains('session') ||
      lower.contains('não autenticado') ||
      lower.contains('401')) {
    return 'Sessão expirada. Entre novamente.';
  }
  if (lower.contains('perfil incompleto')) {
    return 'Perfil incompleto. Atualize sua prescrição.';
  }
  if (lower.contains('openai') || lower.contains('estimar')) {
    return 'Não foi possível estimar os carboidratos. Tente de novo.';
  }
  if (lower.contains('timeout')) {
    return 'A operação demorou demais. Tente de novo.';
  }

  return raw
      .replaceFirst(RegExp(r'^Exception:\s*'), '')
      .replaceFirst(RegExp(r'^Error:\s*'), '');
}

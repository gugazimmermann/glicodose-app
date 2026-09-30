/// In-app notice of what GlicoDose does not do. Not a legal opinion.
class ClinicalDisclaimer {
  ClinicalDisclaimer._();

  /// Bump when the accepted wording changes. Older acceptances show the gate again.
  static const version = 2;

  static const title = 'Este aplicativo não é um dispositivo médico';

  static const points = <String>[
    'Não diagnostica, não prescreve e não é um serviço de emergência.',
    'A dose é uma estimativa a partir da meta, do FSI, da relação I:C, da '
        'duração e da insulina ativa que você cadastrou, e do que foi informado '
        'da refeição. Um número errado, um sensor atrasado ou uma foto mal lida '
        'mudam o resultado.',
    'A estimativa de carboidratos por IA pode errar. A sugestão para '
        'hipoglicemia e os alertas do Libre são lembretes. Não substituem o '
        'alarme do sensor nem o tratamento definido com a sua equipe.',
    'Gráficos, GMI, o pet e o arquivo exportado são apoio. Não são laudo.',
    'Quem aplica a insulina é você, conforme o plano da sua equipe. Em '
        'mal-estar grave, confusão, vômito ou cetona, procure atendimento na '
        'hora, sem esperar este aplicativo.',
  ];

  static const acceptLabel =
      'Li este aviso e confiro a dose antes de aplicar.';

  static const banner =
      'Estimativa. Confira antes de aplicar. '
      'Não é orientação médica nem um dispositivo médico.';

  static const confirmHint =
      'Estimativa. Confira o número antes de aplicar. Não é orientação médica.';

  static const exportFooter =
      'Apoio ao registro. Não é dispositivo médico, não diagnostica, não '
      'prescreve e não substitui orientação da equipe. Confira a dose antes de '
      'aplicar. Em emergência, procure atendimento.';
}

# Teste fechado e acesso à produção (Google Play)

Conta pessoal de desenvolvedor criada depois de 13 de novembro de 2023 só libera **Produção** e **Pré-registro** depois de um teste **fechado** com pelo menos **12 testadores inscritos de forma contínua nos 14 dias anteriores** ao pedido. A faixa interna não entra nessa conta. A análise do pedido costuma levar até 7 dias e pode pedir para continuar o teste se houver menos de 12 inscritos ou engajamento fraco.

Referências: [requisitos de teste para contas pessoais](https://support.google.com/googleplay/android-developer/answer/14151465) e [como configurar um teste aberto, fechado ou interno](https://support.google.com/googleplay/android-developer/answer/9845334). Pacote do app: `app.glicodose`. Política para publicar: [play-privacy-policy.md](play-privacy-policy.md). Produtos de apoio: [iap-store-setup.md](iap-store-setup.md).

O texto das partes 1 e 3 do formulário sai do registro deste teste. Não preencha com números, bugs ou notas que não tenham acontecido.

## 1. Antes de abrir a faixa fechada

- [ ] App criado no Play Console com o pacote `app.glicodose`.
- [ ] Colar no Play Console a URL `https://glicodose.app/privacidade` (texto em [play-privacy-policy.md](play-privacy-policy.md)). O link também está no login e no perfil do app.
- [ ] Ficha da loja no mesmo tom do aviso em `lib/content/clinical_disclaimer.dart`: estimativa, não diagnostica, não prescreve, não é dispositivo médico. Apoio opcional, sem a palavra “doação”.
- [ ] Público-alvo: só **Maiores de 18 anos** (13–15 e 16–17 desmarcados). O app não é criado para crianças e não exibe anúncios. Classificação de conteúdo preenchida.
- [ ] Data safety: conta, saúde (glicose, insulina, refeição), fotos, áudio, e compartilhamento com o médico quando a pessoa vincula. Declaração de app de saúde / Health Connect (leitura e gravação de glicose e nutrição).
- [ ] **Acesso do app:** conta de revisão pronta (seção abaixo) e os campos em inglês colados no Play Console. E-mail e senha só lá. Não commitar.
- [ ] AAB enviado com a configuração do app concluída.
- [ ] Relatório de pré-lançamento gerado e os erros que quebram fluxo anotados.
- [ ] Testadores de licença (Gmail) se alguém for exercitar a aba Apoiar. A compra de apoio no beta não substitui os 12 inscritos na faixa fechada.

### Acesso do app (login do revisor)

O revisor não cria conta, não entra com a própria e não pode usar o teste grátis de `support_10`. Crie a conta antes de preencher o Console.

1. No Supabase Auth, um usuário com o e-mail já confirmado.
2. No perfil: meta de dia e de noite, FSI, relação I:C e nome da insulina rápida. `disclaimer_accepted_at` preenchido e `disclaimer_version` = 2 (texto atual em `lib/content/clinical_disclaimer.dart`).
3. Apoio já ativo (`supporter_status` = `active`), por entitlement promocional no RevenueCat. Sem isso a caixa de “acesso total, inclusive pago” fica falsa: LibreLinkUp, widget e Health Connect ficam atrás da assinatura.

Campos para colar, em inglês. A senha é a da conta do passo 1; não a escreva neste arquivo.

| Campo | Texto |
| --- | --- |
| Nome | `Patient demo account` |
| Nome de usuário | e-mail da conta |
| Senha | senha da conta |
| Outras informações | o bloco abaixo |

```
Sign in with Entrar. UI is Portuguese. Email is confirmed. Profile is complete and the clinical notice is accepted, so the app opens on Dose. Tabs: Dose, Historico (history), Apoiar (support), Perfil (profile). Support is already active: do not trial or purchase. LibreLinkUp, home widget, and Health Connect are unlocked. Sensor link still needs a LibreLinkUp follower login. Health Connect shows a device permission. Do not inject insulin.
```

Marque a declaração de acesso total (recursos premium inclusos) só depois do passo 3. Ligar o sensor Libre ainda exige uma conta de seguidor da Abbott; o parágrafo acima diz isso ao revisor.

## 2. Faixas de teste

Regras que valem para todas as faixas:

- Cada testador precisa de uma Conta do Google ou do Google Workspace.
- Mudança de preço ou de países e regiões vale para todas as faixas.
- O GlicoDose é gratuito. A assinatura de apoio continua cobrando, salvo conta incluída em License testing.
- Deixe desligado o Google Play gerenciado (Testar e lançar > Configurações avançadas). Ativar torna o app particular e ele some da busca da loja pública.
- A primeira publicação de um teste e as mudanças seguintes podem levar algumas horas até o link ficar disponível.

### Teste interno (opcional)

Até 100 testadores, para um controle inicial. Pode começar antes da ficha do app estar completa e pode rodar ao mesmo tempo que o fechado, com outro AAB. É o caminho do primeiro AAB de Billing em [iap-store-setup.md](iap-store-setup.md). Essa faixa não conta para os 12 testadores nem para os 14 dias.

### Teste fechado (o que conta para a produção)

1. Play Console → Testar e lançar → Teste → Teste fechado. Use a faixa fechada inicial. Crie outra faixa nomeada só se um time precisar de um build separado.
2. Inclua os testadores por lista de e-mail ou por Grupo do Google. Mínimo de 12, com folga para quem sair. Quem entra por grupo precisa já estar no grupo antes de aceitar o teste.
3. Envie o AAB para essa faixa. Teste aberto fica para depois do acesso à produção, em conta pessoal nova.
4. Compartilhe o link de ativação. Ele só aparece com o app em status Publicado. Rascunho e publicação pendente não mostram o link. A primeira vez pode levar algumas horas.
5. Cada pessoa abre o link, lê a explicação e confirma a participação. Estar na lista de e-mail sem esse aceite não conta.
6. Peça para permanecerem inscritas os 14 dias. Desinstalar o app não cancela a inscrição. Sair é em “Sair do programa” na página do app na Play Store.
7. Acompanhe o painel: o pedido de produção fica indisponível até 12 inscritos contínuos nos 14 dias anteriores.

Em teste interno ou fechado, antes de teste aberto ou produção, o app não aparece na busca da Play Store. O caminho é o URL que você envia. Depois de instalar, a versão de teste chega em minutos. O feedback dessa versão não altera a nota pública, e a versão de teste não aceita avaliação pública.

Recrutamento fica com você: rede pessoal, pessoas com diabetes ou quem cuida de alguém, grupos do público do app. Serviço pago de teste também serve; o restante do formulário tem de descrever o que essas pessoas fizeram.

### Pausar uma faixa

Testar e lançar > Teste > a faixa (aberta, fechada ou interna) > Gerenciar faixa, se a tela pedir > Pausar faixa, no canto superior direito. Quem já instalou permanece com o app e deixa de receber atualização daquela faixa. Pausar o fechado no meio da janela de 14 dias interrompe a inscrição contínua exigida para o pedido de produção.

## 3. Roteiro para copiar aos testadores

Substitua `[e-mail]`.

> Obrigado por testar o GlicoDose no Android. É um registro e uma estimativa de dose. Não é orientação médica. Confira qualquer número e não aplique insulina só por causa do app.
>
> 1. Abra o link de teste que eu enviar (pode levar algumas horas depois da publicação). Toque em aceitar / ser testador. O app não aparece na busca da Play Store nesta fase. Instale por esse link, não por APK solto.
> 2. Fique inscrito pelo menos 14 dias. Pode desinstalar se precisar; isso não sai do teste. Só saia do programa se for parar de vez, e me avise.
> 3. Crie uma conta, complete o perfil com os números que você já usa com a sua equipe (meta, FSI, relação I:C) e aceite o aviso.
> 4. Registre uma refeição por texto, outra por foto e outra por voz. Leia a estimativa e a dose. Não precisa aplicar.
> 5. Abra o histórico e exporte CSV ou PDF.
> 6. Se tiver sensor Libre, Health Connect ou quiser ver a aba Apoiar, teste esses caminhos também e diga o que aconteceu. Apoiar é assinatura opcional; a calculadora continua gratuita. Use uma conta de teste de licença se eu tiver te passado uma.
>
> Escreva o que quebrou, em qual tela e em qual aparelho. Mande aqui: feedback particular na Play Store (página do app → feedback de teste) e também para [e-mail]. Quanto mais funções você abrir, mais útil o retorno.

## 4. Registro de feedback

Uma linha por achado. Essa tabela vira as respostas das partes 1 e 3.

| Data | Achado | Canal (Play, e-mail, conversa) | Versão em que saiu, ou “em aberto” | Como foi conferido |
| --- | --- | --- | --- | --- |
| | | | | |

Anote à parte, com a fonte de cada número (relato dos testadores, Play Console ou os dois):

- Quantas pessoas estavam inscritas em cada dia da janela de 14 dias, e se alguém saiu.
- Quais fluxos cada uma completou: conta, perfil, aviso, refeição por texto, foto, voz, leitura da dose, histórico, exportação, Libre, Health Connect, Apoiar.
- Em quais dias o app foi aberto, se você souber.
- Versão do AAB no fim da janela.

Desinstalar não é sair. O que conta para o Play é a inscrição contínua.

## 5. Pedido de produção

Quando o painel mostrar 12 inscritos nos 14 dias contínuos anteriores: Painel → Solicitar a produção. Há “Visualizar perguntas” antes de enviar. Responda no seu formulário; o texto e o limite de caracteres são os do Console. Grave as respostas noutro lugar: sair sem avançar pode descartar o que foi digitado.

Confira a política antes de enviar: conteúdo e monetização, faixa etária, app estável, e as credenciais de revisão no Acesso do app.

### Parte 2 — pode colar agora

O Play informa que estas respostas não aparecem na ficha pública. Encurte se o campo estourar o contador.

**Público**

Adultos com diabetes que usam insulina rápida e já têm meta, FSI e relação insulina:carboidrato definidos com a equipe. Usam o app na refeição, para estimar a dose, e no registro do dia.

**Valor**

Estima carboidratos e a dose de insulina rápida a partir do perfil prescrito. A pessoa confere o número antes de aplicar. Histórico e exportação servem à consulta. A calculadora é gratuita; o apoio opcional libera sensor, widget e Health Connect.

**Instalações no primeiro ano**

Escolha a faixa que você consegue sustentar. Para um app novo, **0–10 mil** ou **Não sei**. Não aumente o número para parecer maior.

### Parte 1 — preencher depois do 14º dia

**Como recrutou**

Recrutei [N] testadores por [canal: rede pessoal, grupos de diabetes, serviço de teste]. [Quantos] se inscreveram e permaneceram inscritos de [data] a [data]. Eu passei o roteiro, li o feedback e [lancei a versão X / não lancei mudança].

**Dificuldade de recrutar**

Marque a opção que aconteceu (muito difícil até muito fácil). O texto livre acima tem de bater com essa escolha.

**Engajamento**

Nos 14 dias, [N] testadores inscritos completaram conta, perfil e o aviso. [N] registraram refeição por texto, [N] por foto, [N] por voz e leram a dose. [N] abriram histórico ou exportaram. [Libre / Health / Apoiar: quem testou, ou “ninguém tinha sensor”]. A fonte desses números é [relato / Console]. Uso de produção esperado: registro na refeição, não o dia inteiro no app. [Diferença observada, se houver].

**Resumo do feedback**

O retorno chegou por [Play Console e e-mail]. Os temas foram: [tema 1], [tema 2]. [O que saiu na versão X]. [O que ficou em aberto].

Se o retorno foi só positivo, diga isso e cite os fluxos que cobriu. Não invente um defeito.

### Parte 3 — preencher depois do 14º dia

**O que mudou com o teste**

[Versão]: [correção] por causa de [achado]. Conferi com [quem reportou / novo teste]. [Item] continua em aberto porque [motivo].

Se nada mudou no código:

Não lancei mudança neste teste. Os testadores percorreram conta, perfil, refeição (texto, foto e voz), leitura da dose e histórico/exportação em [aparelhos ou versões do Android]. O resultado foi [o que eles relataram e o que o relatório de pré-lançamento / Android vitals mostrou]. [Item] ficou em aberto e não bloqueia esses fluxos.

**Por que está pronto**

Critérios: os fluxos acima foram concluídos por testadores reais na janela de 14 dias; [correções conferidas, se houve]; [itens em aberto] não impedem conta, registro e leitura da dose. A mesma conta de revisão do Acesso do app chega na dose com o aviso aceito.

## 6. Se o Play pedir para continuar o teste

Menos de 12 inscritos que aceitaram, ou uso insuficiente na janela. Mantenha a faixa fechada, reponha quem saiu e peça de novo o roteiro. No novo pedido, diga o que mudou em relação à tentativa anterior, com fatos do registro.

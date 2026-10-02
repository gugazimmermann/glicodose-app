# Política de privacidade do GlicoDose

Página publicada para colar no Google Play Console (e, se for o caso, na App Store):

**https://glicodose.app/privacidade**

O texto no ar está em `diabetes-site` (`/privacidade`). Este arquivo descreve o mesmo conteúdo. Não é parecer jurídico.

- **App:** GlicoDose (`app.glicodose`)
- **Responsável:** GlicoDose
- **Contato:** contato@glicodose.app
- **URL:** https://glicodose.app/privacidade
- **Vigência:** outubro de 2026

O GlicoDose é um registro de glicose e alimentação, com estimativa de insulina rápida a partir do perfil que a pessoa cadastrou. Não é dispositivo médico, não diagnostica e não prescreve. O público é de adultos. O app não é dirigido a crianças.

## Dados da conta e do perfil

No cadastro, o Supabase Auth guarda e-mail e senha. O perfil guarda nome, tipo de diabetes, meta de glicose, fator de sensibilidade, relação insulina:carboidrato, nome da insulina rápida, passo da dose, duração da insulina, janela noturna, fuso horário, tema, código de compartilhamento com o médico, limites de alerta e a data em que o aviso clínico foi aceito.

## Registros de saúde que você cria

Cada registro pode incluir glicose, texto da refeição, carboidratos, dose sugerida e dose aplicada, insulina basal, receitas e anotações ligadas ao histórico. Fotos de refeição ficam num armazenamento privado, na pasta da sua conta. O áudio da refeição é enviado para transcrição; o que permanece no registro é o texto resultante, não um arquivo de áudio.

Gráficos, GMI, o pet e os arquivos CSV/PDF são gerados a partir desses registros. A exportação fica no seu aparelho até você compartilhar o arquivo.

## Foto, voz e estimativa

Quando você pede uma estimativa, o texto da refeição, a foto ou o áudio seguem para a OpenAI (modelos de visão, texto e transcrição) por uma função no servidor. O servidor registra uso da chamada (identificador da conta, modelo, quantidade de tokens, latência, sucesso e custo estimado) para operação. Esse log não é a resposta clínica.

## Health Connect

Com a sua permissão, o app lê e grava glicose e nutrição no Health Connect do aparelho, inclusive histórico e leitura em segundo plano quando você autoriza. Esses dados também podem ser copiados para o seu histórico no servidor. O Health Connect tem a própria política do Google.

## LibreLinkUp e alertas

Se você ligar o sensor, o app guarda o e-mail e a região da conta LibreLinkUp e os tokens usados para sincronizar a glicose. As leituras (valor, tendência, horário) entram no seu histórico. Com alertas ligados, um token de notificação do aparelho (Firebase Cloud Messaging) permite avisar hipoglicemia, hiperglicemia ou sensor parado. Você desliga os alertas no perfil.

## Médico vinculado

Se você passar o código de 6 caracteres, o profissional vinculado pode ler o histórico e dados do perfil necessários ao acompanhamento. O vínculo vale enquanto existir na sua conta.

## Apoio (assinatura)

A calculadora é gratuita. A assinatura opcional de apoio é cobrada pelo Google Play (ou pela App Store no iOS). O RevenueCat confirma o estado da assinatura (produto, loja, validade). O app guarda só esse estado, para liberar LibreLinkUp, o widget e o Health Connect. O pagamento em si fica na loja. Na ficha da loja o produto se chama apoio, sem a palavra “doação”.

## O que não fazemos

Não vendemos esses dados. Não há SDK de analytics de terceiros no app. Firebase entra para entregar notificações. O widget e o serviço em primeiro plano de insulina ativa guardam no aparelho o necessário para mostrar o status.

## Quem processa

| Quem | Para quê |
| --- | --- |
| Supabase | Conta, banco, fotos, funções do servidor |
| OpenAI | Estimar carboidratos, descrever foto, transcrever voz |
| Google (Play, Health Connect, Firebase) | Loja, assinatura, saúde no aparelho, push |
| RevenueCat | Estado da assinatura de apoio |
| LibreLinkUp (Abbott), se você conectar | Leituras do sensor |

## Retenção e exclusão

A conta e os registros permanecem enquanto a conta existir. A exclusão da conta é pelo contato contato@glicodose.app: peça a remoção e apagamos a conta e os dados ligados a ela no servidor, salvo o que a lei obrigar a guardar. Cancelar a assinatura é na loja (Play → pagamentos e assinaturas). Sair do app não apaga o histórico.

## Segurança

Acesso aos registros exige a sua sessão. Fotos não são públicas. Credenciais do LibreLinkUp e tokens de notificação ficam no servidor com acesso restrito à sua conta e às funções que sincronizam e alertam.

## Alterações

Mudanças neste texto passam a valer na data publicada no topo da página. O aviso dentro do app, quando o texto clínico mudar, pede novo aceite.

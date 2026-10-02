# Apoio recorrente via IAP (Apple + Google + RevenueCat)

Checklist operacional para criar os produtos nas lojas, configurar o RevenueCat
e testar antes de produção. O app espera os IDs abaixo.

No Android, conta pessoal criada depois de 13 de novembro de 2023 ainda passa
pelo teste fechado (12 testadores por 14 dias) antes da produção:
[play-closed-test.md](play-closed-test.md). Política para colar na ficha:
[play-privacy-policy.md](play-privacy-policy.md).

## Identificadores do app

| Plataforma | ID |
| ---------- | -- |
| Android (Play / RevenueCat) | `app.glicodose` |
| iOS (App Store / RevenueCat) | `app.glicodose` |
| App Group (widget iOS) | `group.app.glicodose` |

## Product IDs (iguais nas duas lojas e no RevenueCat)

| Product ID         | Plano aproximado | Tipo                         |
| ------------------ | ---------------- | ---------------------------- |
| `support_10`       | R$ 10 / mês      | Auto-renewable subscription  |
| `support_20`       | R$ 20 / mês      | Auto-renewable subscription  |
| `support_50`       | R$ 50 / mês      | Auto-renewable subscription  |
| `support_100`      | R$ 100 / mês     | Auto-renewable subscription  |
| `support_10_annual`| R$ 100 / ano     | Auto-renewable subscription  |

- **Subscription group (Apple):** um único grupo, ex. `Apoio ao projeto` (os cinco produtos juntos, para upgrade/downgrade)
- **Entitlement (RevenueCat):** `supporter` (ligado aos 5 produtos)
- **Offering:** current offering com os 5 packages
- **Trial:** 7 dias grátis só em `support_10` (oferta introdutória). O app mostra “7 dias grátis” quando a loja devolve `introductoryPrice` com preço 0. No iOS some se o usuário já usou o trial.
- **Anual:** `support_10_annual` a R$ 100 (dez meses de R$ 10 — dois meses a menos). Sem trial.

Copy sugerida nas lojas: “Apoiar o GlicoDose” / “Apoiador” — **não** use a palavra “doação”. Descrição: a calculadora de dose continua gratuita; o apoio libera LibreLinkUp, o widget da tela inicial e Apple Health / Health Connect.

## 1. App Store Connect

1. Agreements → Paid Apps ativo + dados bancários/fiscais.
2. Criar o app com Bundle ID **`app.glicodose`** (Apple Developer → Identifiers, se ainda não existir).
3. App Groups: criar **`group.app.glicodose`** e habilitar no App ID + no extension do widget.
4. App → Subscriptions → criar o grupo **Apoio ao projeto**.
5. Criar 4 assinaturas mensais (`support_10` … `support_100`) e a anual `support_10_annual` (~R$ 100).
6. Em `support_10` → Introductory Offers: **Free**, duração **7 days**, 1 período, para new subscribers.
7. Localização PT-BR: nome “Apoio R$X/mês” (anual: “Apoio R$100/ano”). Descrição: dose gratuita; o apoio libera LibreLinkUp, widget e Apple Health.
8. App Store Server Notifications V2 → URL do RevenueCat (dashboard RC → Integrations → Apple).

## 2. Google Play Console

1. Criar o app com package name **`app.glicodose`** (não dá para mudar depois).
2. Upload de um AAB (Internal testing) que já inclua o Billing (via `purchases_flutter`).
3. Monetize with Play → Products → Subscriptions:
   - Criar assinaturas mensais `support_10` … `support_100` e a anual `support_10_annual` (~R$ 100/ano).
   - Em `support_10`, base plan mensal com oferta **Free trial** de 7 dias (novos assinantes). A anual não tem trial.
4. Setup → API access → criar/vincular conta de serviço com permissão financeira → baixar JSON.
5. Monetize → Monetization setup → Real-time developer notifications:
   - Pub/Sub topic apontando para o RevenueCat (URL/tópico que o RC mostra em Integrations → Google).
6. License testing: adicionar Gmails de teste antes de cobrar de verdade.
7. Faixa interna valida o Billing. A contagem de 12 testadores por 14 dias é na faixa fechada: [play-closed-test.md](play-closed-test.md). URL da política: [play-privacy-policy.md](play-privacy-policy.md).

## 3. RevenueCat

1. Criar projeto GlicoDose.
2. **Add app → Google Play**
   - Package name: **`app.glicodose`**
   - Colar o JSON da conta de serviço do Play Console.
3. **Add app → App Store**
   - Bundle ID: **`app.glicodose`**
   - Shared secret / App Store Connect API key conforme o assistente do RC.
4. Importar / cadastrar os 5 produtos (`support_10` … `support_100` e `support_10_annual`).
5. Entitlement `supporter` → anexar os 5 produtos.
6. Offering default (current) com os 5 packages. O trial vem da loja; o app não cria a oferta.
7. Copiar as **public SDK keys** (`appl_…` / `goog_…`) para o `.env` do app.
8. Webhooks → URL da Edge Function:

   `https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook`

   Authorization: o mesmo valor de `REVENUECAT_WEBHOOK_AUTH` (secret no Supabase).

9. No app, `Purchases.logIn(supabaseUserId)` amarra a compra ao UUID do perfil.

## 4. Supabase

```bash
# SQL Editor: rode supabase/migrations/009_supporter_billing.sql
# e supabase/migrations/040_support_annual_mrr.sql (MRR do plano anual)

supabase secrets set REVENUECAT_WEBHOOK_AUTH='um-segredo-longo'
# SUPABASE_SERVICE_ROLE_KEY já existe no ambiente das functions

supabase functions deploy revenuecat-webhook
```

No dashboard RevenueCat, envie um evento **TEST** e confira os logs da function.

## 5. App (Flutter)

```env
REVENUECAT_IOS_API_KEY=appl_...
REVENUECAT_ANDROID_API_KEY=goog_...
```

```bash
flutter run --dart-define-from-file=.env
```

UI: aba **Apoiar** (somente Android/iOS com keys configuradas). Lista Libre, widget e Health, destaca `support_10` (“Mais escolhido”, com a linha de trial quando a loja manda) e mostra o anual separado. Também pelo atalho no Perfil. Na Dose, “Linkar Sensor” e “Health” abrem o pedido só quando a pessoa toca. O widget bloqueado abre o app na aba Apoiar.

## 6. Testes (sandbox)

### iOS

1. App Store Connect → Users and Access → Sandbox Testers.
2. No device: Settings → App Store → Sandbox Account.
3. TestFlight ou debug build → comprar cada plano; renovação sandbox é acelerada.
4. Confirmar: sheet nativa → status “Apoiador” no perfil → linha em `profiles.supporter_*` após webhook.
5. **Restaurar compras** e **Gerenciar assinatura**.

### Android

1. Play Console → License testing (contas Gmail).
2. Internal testing track com o AAB (`app.glicodose`).
3. Comprar com conta de teste (não cobra de verdade).
4. Mesmos checks de UI + `profiles` + restore.

### Checklist rápido

- [ ] Ofertas aparecem com preço da loja (não só fallback)
- [ ] Compra `support_20` marca entitlement `supporter`
- [ ] `support_10` novo assinante mostra “7 dias grátis” e a sheet da loja não cobra na hora
- [ ] Quem já usou o trial no iOS não vê a linha de grátis
- [ ] `support_10_annual` concede o mesmo entitlement `supporter`
- [ ] Upgrade `support_20` → `support_50` no mesmo grupo
- [ ] Cancelamento na loja → status `canceled`/`expired` via webhook
- [ ] Logout/login + restore recupera o plano
- [ ] Web não mostra a seção de IAP

## Review notes (Apple)

> A calculadora de dose é gratuita e não exige assinatura. A aba “Apoiar” vende uma assinatura opcional (`support_10` com 7 dias grátis, e outros valores) que libera LibreLinkUp, o widget da tela inicial e a sincronização com Apple Health / Health Connect — funções com custo de servidor. Não use a palavra “doação”.

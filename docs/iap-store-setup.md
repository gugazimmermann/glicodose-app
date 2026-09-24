# Apoio recorrente via IAP (Apple + Google + RevenueCat)

Checklist operacional para criar os produtos nas lojas, configurar o RevenueCat
e testar antes de produção. O app espera os IDs abaixo.

## Identificadores do app

| Plataforma | ID |
| ---------- | -- |
| Android (Play / RevenueCat) | `app.glicodose` |
| iOS (App Store / RevenueCat) | `app.glicodose` |
| App Group (widget iOS) | `group.app.glicodose` |

## Product IDs (iguais nas duas lojas e no RevenueCat)

| Product ID     | Plano aproximado | Tipo                         |
| -------------- | ---------------- | ---------------------------- |
| `support_10`   | R$ 10 / mês      | Auto-renewable subscription  |
| `support_20`   | R$ 20 / mês      | Auto-renewable subscription  |
| `support_50`   | R$ 50 / mês      | Auto-renewable subscription  |
| `support_100`  | R$ 100 / mês     | Auto-renewable subscription  |

- **Subscription group (Apple):** um único grupo, ex. `Apoio ao projeto`
- **Entitlement (RevenueCat):** `supporter` (ligado aos 4 produtos)
- **Offering:** current offering com os 4 packages

Copy sugerida nas lojas: “Apoiar o GlicoDose” / “Apoiador” — **não** use a palavra “doação”.

## 1. App Store Connect

1. Agreements → Paid Apps ativo + dados bancários/fiscais.
2. Criar o app com Bundle ID **`app.glicodose`** (Apple Developer → Identifiers, se ainda não existir).
3. App Groups: criar **`group.app.glicodose`** e habilitar no App ID + no extension do widget.
4. App → Subscriptions → criar o grupo **Apoio ao projeto**.
5. Criar 4 assinaturas mensais com os Product IDs acima e preços BRL ~10/20/50/100.
6. Localização PT-BR: nome “Apoio R$X/mês”, descrição explicando que o app continua gratuito e o valor ajuda a manter o serviço (IA/API).
7. App Store Server Notifications V2 → URL do RevenueCat (dashboard RC → Integrations → Apple).

## 2. Google Play Console

1. Criar o app com package name **`app.glicodose`** (não dá para mudar depois).
2. Upload de um AAB (Internal testing) que já inclua o Billing (via `purchases_flutter`).
3. Monetize with Play → Products → Subscriptions:
   - Criar assinatura(s) / base plans mensais com Product IDs `support_10` … `support_100` e preços BRL.
4. Setup → API access → criar/vincular conta de serviço com permissão financeira → baixar JSON.
5. Monetize → Monetization setup → Real-time developer notifications:
   - Pub/Sub topic apontando para o RevenueCat (URL/tópico que o RC mostra em Integrations → Google).
6. License testing: adicionar Gmails de teste antes de cobrar de verdade.

## 3. RevenueCat

1. Criar projeto GlicoDose.
2. **Add app → Google Play**
   - Package name: **`app.glicodose`**
   - Colar o JSON da conta de serviço do Play Console.
3. **Add app → App Store**
   - Bundle ID: **`app.glicodose`**
   - Shared secret / App Store Connect API key conforme o assistente do RC.
4. Importar / cadastrar os 4 produtos (`support_10` … `support_100`).
5. Entitlement `supporter` → anexar os 4 produtos.
6. Offering default (current) com packages `support_10` … `support_100`.
7. Copiar as **public SDK keys** (`appl_…` / `goog_…`) para o `.env` do app.
8. Webhooks → URL da Edge Function:

   `https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook`

   Authorization: o mesmo valor de `REVENUECAT_WEBHOOK_AUTH` (secret no Supabase).

9. No app, `Purchases.logIn(supabaseUserId)` amarra a compra ao UUID do perfil.

## 4. Supabase

```bash
# SQL Editor: rode supabase/migrations/009_supporter_billing.sql

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

UI: aba **Apoiar** (somente Android/iOS com keys configuradas). Também acessível pelo atalho no Perfil e pelo banner no topo da Dose.

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
- [ ] Upgrade `support_20` → `support_50` no mesmo grupo
- [ ] Cancelamento na loja → status `canceled`/`expired` via webhook
- [ ] Logout/login + restore recupera o plano
- [ ] Web não mostra a seção de IAP

## Review notes (Apple)

> O app é gratuito. A aba “Apoiar” oferece assinaturas opcionais de apoio ao projeto (manutenção de infraestrutura/IA). Não bloqueia funcionalidades. Benefício: badge de apoiador e continuidade do serviço.

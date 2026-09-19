# Apoio recorrente via IAP (Apple + Google + RevenueCat)

Checklist operacional para criar os produtos nas lojas, configurar o RevenueCat
e testar antes de produção. O app espera os IDs abaixo.

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
2. App → Subscriptions → criar o grupo **Apoio ao projeto**.
3. Criar 4 assinaturas mensais com os Product IDs acima e preços BRL ~10/20/50/100.
4. Localização PT-BR: nome “Apoio R$X/mês”, descrição explicando que o app continua gratuito e o valor ajuda a manter o serviço (IA/API).
5. App Store Server Notifications V2 → URL do RevenueCat (dashboard RC → Integrations → Apple).

## 2. Google Play Console

1. Upload de um AAB (Internal testing) que já inclua o Billing (via `purchases_flutter`).
2. Monetize → Subscriptions: criar assinatura(s) / base plans mensais com os mesmos Product IDs e preços BRL.
3. Conta de serviço com permissão financeira → conectar no RevenueCat.
4. Real-time developer notifications (Pub/Sub) → RevenueCat.

## 3. RevenueCat

1. Criar projeto e apps iOS + Android (package `com.diabetes.diabetes_app` / bundle id do iOS).
2. Importar os 4 produtos.
3. Entitlement `supporter` → anexar os 4 produtos.
4. Offering default com packages `support_10` … `support_100`.
5. Copiar as **public SDK keys** (`appl_…` / `goog_…`) para o `.env` do app.
6. Webhooks → URL da Edge Function:

   `https://<PROJECT_REF>.supabase.co/functions/v1/revenuecat-webhook`

   Authorization: o mesmo valor de `REVENUECAT_WEBHOOK_AUTH` (secret no Supabase).

7. No app, `Purchases.logIn(supabaseUserId)` amarra a compra ao UUID do perfil.

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

UI: aba Perfil → seção **Apoiar o GlicoDose** (somente Android/iOS com keys configuradas).

## 6. Testes (sandbox)

### iOS

1. App Store Connect → Users and Access → Sandbox Testers.
2. No device: Settings → App Store → Sandbox Account.
3. TestFlight ou debug build → comprar cada plano; renovação sandbox é acelerada.
4. Confirmar: sheet nativa → status “Apoiador” no perfil → linha em `profiles.supporter_*` após webhook.
5. **Restaurar compras** e **Gerenciar assinatura**.

### Android

1. Play Console → License testing (contas Gmail).
2. Internal testing track com o AAB.
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

> O app é gratuito. A seção “Apoiar” oferece assinaturas opcionais de apoio ao projeto (manutenção de infraestrutura/IA). Não bloqueia funcionalidades. Benefício: badge de apoiador e continuidade do serviço.

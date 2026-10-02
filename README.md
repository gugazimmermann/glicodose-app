# GlicoDose — App do paciente (Flutter + Supabase)

App híbrido Android/iOS para registro de glicose, alimentação (texto, foto ou voz) e estimativa de insulina rápida com base no perfil prescrito e ChatGPT (via Edge Function).

> **Aviso:** a recomendação é estimativa e **não substitui orientação médica**.

## Funcionalidades

- Dose híbrida: IA estima carboidratos (com **confiança** baixa/média/alta); fórmula do perfil − IOB calcula a insulina
- Ajuste de carbs na tela de resultado e recálculo local
- Avisos de hipoglicemia / dose 0 por IOB
- Insulina basal: registro separado (não entra no IOB rápido) + lembretes locais
- Histórico com gráficos, exportação **CSV/PDF** e relatório para consulta
- Linkar Sensor (LibreLinkUp) com glicose atual na Dose
- Alertas de hipo/hiper/sensor parado via **push FCM** (cron LibreLinkUp)
- Importação de glicose via **Health Connect** (Android) / **HealthKit** (iOS)
- Widget de status na home (IOB / glicose) em Android e iOS
- Fuso horário e tema (sistema/claro/escuro) no perfil, sincronizados no Supabase
- Vínculo com médico por código de 6 caracteres
- Apoiar (IAP via RevenueCat)

## Pré-requisitos

- Flutter SDK
- Projeto no [Supabase](https://supabase.com)
- Chave da [OpenAI](https://platform.openai.com)
- Projeto [Firebase](https://firebase.google.com) (FCM) com `google-services.json` / `GoogleService-Info.plist`
- CLI do Supabase (para deploy das funções)

## 1. Banco e Storage

No SQL Editor do Supabase (ou `supabase db push` a partir desta pasta), execute as migrations na ordem:

1. [`001_init.sql`](supabase/migrations/001_init.sql) … até
2. [`040_support_annual_mrr.sql`](supabase/migrations/040_support_annual_mrr.sql)

Resumo das migrations recentes:

| Migration | Conteúdo |
| --- | --- |
| `014` | `profiles.timezone` (IANA) |
| `015` | `profiles.theme` (`system` / `light` / `dark`) |
| `016` | Alertas Libre + `device_tokens` + estado de debounce |
| `017` | Insulina basal (`basal_doses` + campos no perfil) |
| `018` | Sync Health Connect / HealthKit (metadados em `entries`) |
| `019` | Debounce de alerta no mesmo sample Libre |

## 2. Edge Functions

```bash
supabase login
supabase link --project-ref SEU_PROJECT_REF
supabase secrets set OPENAI_API_KEY=sk-sua-chave
supabase secrets set LIBRELINKUP_CRON_SECRET='um-segredo-longo'
supabase secrets set FIREBASE_SERVICE_ACCOUNT_JSON="$(cat service-account.json)"
supabase functions deploy recommend-insulin
supabase functions deploy transcribe-food
supabase functions deploy describe-food
supabase functions deploy revenuecat-webhook
supabase functions deploy librelinkup-connect
supabase functions deploy librelinkup-sync
supabase functions deploy librelinkup-cron
```

| Função | Papel |
| --- | --- |
| `recommend-insulin` | Carbs (GPT-4o + TACO / Vision) + confiança; dose = fórmula do perfil (`dose_step`) − IOB; log em `ai_usage_logs` |
| `transcribe-food` | Áudio → texto (Whisper, `language: pt`) |
| `describe-food` | Foto da refeição → frase em português (GPT-4o mini); log em `ai_usage_logs` |
| `revenuecat-webhook` | Espelha status de apoiador (IAP) em `profiles` |
| `librelinkup-connect` / `sync` | Credenciais e sync sob demanda do LibreLinkUp |
| `librelinkup-cron` | Sync periódico + push FCM de alertas hipo/hiper/stale |

## 3. Variáveis de ambiente (`.env`)

```bash
cp .env.example .env
```

```env
SUPABASE_URL=https://xxxx.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOi...
REVENUECAT_IOS_API_KEY=appl_...
REVENUECAT_ANDROID_API_KEY=goog_...
```

```bash
flutter pub get
flutter run --dart-define-from-file=.env
```

O `flutter run` acima escolhe um dispositivo sozinho. Para o emulador ou o celular, use as seções abaixo. Os `--dart-define-from-file=.env` são obrigatórios em todos os casos.

**Não** coloque `OPENAI_API_KEY` nem a service account do Firebase no `.env` do app — só nos secrets do Supabase.

## Emulador Android

AVD já criado nesta máquina: **Pixel_10** (Android com Play Store). Confira os disponíveis:

```bash
flutter emulators
```

Suba o emulador e espere a home do Android abrir:

```bash
flutter emulators --launch Pixel_10
```

Quando ele aparecer em `flutter devices` (normalmente como `emulator-5554`), rode o app:

```bash
flutter devices
flutter run --dart-define-from-file=.env -d emulator-5554
```

Se o `Pixel_10` já estiver aberto, não lance de novo — o segundo processo falha. Encerre o que está no ar e abra outra vez:

```bash
adb -s emulator-5554 emu kill
flutter emulators --launch Pixel_10
```

## Celular físico

Celular usado neste projeto: **Samsung SM-G990E** (`RXCW20156GV`, Android 16). O app exige Android 8+ (`minSdk` 26).

No telefone, uma vez:

1. **Configurações → Sobre o telefone** → toque 7 vezes em **Número da versão** para ativar as Opções do desenvolvedor.
2. **Opções do desenvolvedor → Depuração USB** ligada.
3. Conecte o cabo USB. Na notificação de USB, escolha **Transferência de arquivos** (não “Só carregar”).
4. Aceite o diálogo **Permitir depuração USB?** (marque “sempre permitir neste computador”).

Confira se o aparelho entrou e rode:

```bash
adb devices -l
flutter devices
flutter run -d RXCW20156GV --dart-define-from-file=.env
```

O status em `adb devices` precisa ser `device`. `unauthorized` significa que o diálogo de depuração ainda não foi aceito; se o celular não aparecer, reconecte o cabo, troque a porta USB e rode `adb kill-server && adb start-server`. Com o telefone visível, o id também funciona assim:

```bash
flutter run -d android --dart-define-from-file=.env
```

Use `-d android` só quando houver um único aparelho Android conectado (emulador ou celular). Com os dois ligados, informe o id (`emulator-5554` ou `RXCW20156GV`).

### Firebase / FCM

1. Gere os arquivos do app no Firebase Console (ou `flutterfire configure`).
2. Confirme `android/app/google-services.json` e `ios/Runner/GoogleService-Info.plist`.
3. No cron: `FIREBASE_SERVICE_ACCOUNT_JSON` (conta de serviço do mesmo projeto).

### Apoio (IAP)

Guia: [`docs/iap-store-setup.md`](docs/iap-store-setup.md)

```bash
supabase secrets set REVENUECAT_WEBHOOK_AUTH='um-segredo-longo'
supabase functions deploy revenuecat-webhook
```

## Teste interno (Google Play)

Pacote: `app.glicodose`. O release lê `android/key.properties` (keystore e senhas ficam fora do git). Sem esse arquivo, o AAB sai assinado com a chave de debug e o Play rejeita o envio.

O número depois do `+` em `pubspec.yaml` (`version: 1.0.0+2`) é o código de versão. Cada upload precisa de um código maior que o anterior; o código **1** já foi usado. O nome que a pessoa vê no Play é o `1.0.0`.

```bash
flutter build appbundle --release --dart-define-from-file=.env
```

O arquivo sai em `build/app/outputs/bundle/release/app-release.aab`.

No Play Console: **Testar e lançar → Teste → Teste interno → Criar nova versão**. O upload fica em **Pacotes de apps**, acima das notas. No formulário de **ID de publicidade** (**Monitorar e aprimorar → Política e programas → Conteúdo do app**), responda **Não**: o app não declara `AD_ID`.

A faixa interna aceita até 100 testadores e não conta para os 12 inscritos nem para os 14 dias da produção. Roteiro e ficha: [`docs/play-closed-test.md`](docs/play-closed-test.md). Política: [`docs/play-privacy-policy.md`](docs/play-privacy-policy.md).

## Fluxo do usuário

1. Cadastro / login (Supabase Auth)
2. Perfil: tipo de diabetes, meta dia/noite, FSI, I:C, insulina rápida, basal, fuso, tema, alertas Libre, Health
3. Dose: glicose (manual / Libre / Health) + alimento (texto/foto/**Falar**) → calcular
4. Revisar carbs (confiança IA), confirmar insulina aplicada; registrar basal se for o caso
5. Histórico: lista, gráficos, exportar CSV/PDF
6. Widget / badge / foreground task: IOB ao vivo
7. Perfil: Linkar Sensor, Apoiar, sair

## Roadmap

Specs em [`docs/releases/`](docs/releases/).

| Release | Status |
| --- | --- |
| R0 IOB / disclaimer | Feito |
| R1 híbrido (IA = carbs) | Feito |
| R2 gráficos | Feito |
| R3 export CSV/relatório | Feito |
| R4 LibreLinkUp (Linkar Sensor) | Feito |
| R5 timezone, tema, basal, alertas FCM, Health, widget iOS | Feito |

## Estrutura

```
lib/
  config/          # Supabase + RevenueCat
  models/          # Profile, Entry, BasalDose, InsulinRecommendation, LibreGlucose
  services/        # Auth, Entry, Insulin, IOB, Basal, Libre, Health, FCM, Export, Widget…
  screens/         # Dose, Histórico, Perfil, Health import, Linkar Sensor, Apoiar…
supabase/
  migrations/      # 001 … 040
  functions/       # recommend-insulin, transcribe-food, describe-food, revenuecat-webhook, librelinkup-*
docs/
  iap-store-setup.md
  play-closed-test.md
  play-privacy-policy.md
  releases/
```

## Projetos irmãos

| Repo | Papel |
| --- | --- |
| `diabetes-medicos` | Portal do médico |
| `diabetes-admin` | KPIs + doações + uso de IA |
| `diabetes-site` | Landing + Apoiar (Stripe público) |

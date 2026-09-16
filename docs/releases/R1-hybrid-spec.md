# R1 — Cálculo híbrido (fórmula + IA só nos carbs)

**Status:** Implementado  
**Pré-requisito:** R0 (IOB)

## Objetivo

- GPT (ou usuário) informa **apenas carboidratos (g)**
- Dose = `max(0, round((correção + bolus_comida) − IOB))` com fatores do perfil
- Modo **sem IA**: carbs manuais → mesma fórmula local (barato e offline-friendly)

## Fórmula

```
correção     = max(0, (glicose - alvo) / FSI)
bolus_comida = carboidratos_g / I:C
dose_bruta   = correção + bolus_comida
dose_final   = max(0, round_to_step(dose_bruta - IOB, dose_step))
```

## Arquivos

- [`lib/services/bolus_calculator.dart`](../../lib/services/bolus_calculator.dart)
- [`lib/services/insulin_service.dart`](../../lib/services/insulin_service.dart)
- [`supabase/functions/recommend-insulin/index.ts`](../../supabase/functions/recommend-insulin/index.ts)
- [`lib/screens/home_screen.dart`](../../lib/screens/home_screen.dart)
- [`test/bolus_calculator_test.dart`](../../test/bolus_calculator_test.dart)

## Deploy

```bash
supabase functions deploy recommend-insulin
```

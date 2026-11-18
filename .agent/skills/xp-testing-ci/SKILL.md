---
name: xp-testing-ci
description: Asegura pruebas unitarias y de integración continuas bajo Extreme Programming (XP) compatibles con GitHub Actions.
---

# Skill: Pruebas Automatizadas XP y CI

Para respaldar la metodología ágil **Extreme Programming (XP)** y los flujos de **GitHub Actions**:
1. Cada vez que implementes o modifiques un `Model` o `Controller`, crea o actualiza su correspondiente archivo de prueba en `test/unit/`.
2. **Pruebas Críticas Obligatorias:**
   - `settlement_calculator_test.dart`: Validar exactitud matemática de litros acumulados por productor, multiplicación por tarifa vigente de la quincena, manejo de decimales, exclusión de entregas anuladas y prevención de doble liquidación sobre un mismo rango de fechas.
   - `offline_sync_test.dart`: Validar que un registro guardado en Hive sin conexión conserve su `UUID`, cambie de `isSynced: false` a `true` tras sincronizar y no genere duplicados si la sincronización se ejecuta dos veces.
   - `rbac_permissions_test.dart`: Verificar que el rol `productor` no tenga acceso a métodos de escritura de entregas ni cierres de quincena.
3. Mantén el código libre de advertencias de análisis estático (`flutter analyze` debe pasar con 0 issues).

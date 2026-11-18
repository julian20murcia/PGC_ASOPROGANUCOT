---
name: Historia de Usuario XP
about: Plantilla oficial de Historia de Usuario bajo Extreme Programming (XP) para ASOPROGANUCOTT
title: "[HU-XX] Título corto de la historia"
labels: ["historia-usuario", "xp"]
---

## Identificación XP
- **Código HU:** `HU-XX`
- **Requerimientos relacionados:** `RF-XX` / `RNF-XX`
- **Iteración / Rama XP:** `iteracion-X-...`
- **Prioridad:** Alta / Media / Baja
- **Estimación (Puntos XP):** 1 / 2 / 3 / 5

## Historia de Usuario
**Como** `<Administrador Central / Operario de Recepción / Productor Ganadero>`  
**Quiero** `<descripción de la capacidad operativa>`  
**Para** `<beneficio medible en ASOPROGANUCOTT>`

## Criterios de Aceptación (Verificables)
- [ ] Criterio 1: ...
- [ ] Criterio 2: ...
- [ ] Restricción RBAC / Legal (Ley 1581 de 2012 / Ley 527 de 1999) verificada.
- [ ] Persistencia Offline-First en Hive / sincronización Firebase validada.

## Evidencia y Pruebas Automatizadas XP
- Archivo de prueba asociado: `test/unit/...`
- `flutter analyze`: 0 issues.
- `flutter test`: aprobado en CI (`flutter_ci.yml`).

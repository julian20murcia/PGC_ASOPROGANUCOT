# ASOPROGANUCOTT — Sistema de Registro y Control de Recepción de Leche Cruda

> **Proyecto de grado:** *Sistema de registro y control de recepción de leche cruda para la asociación lechera ASOPROGANUCOT en el municipio de Susa (Valle de Ubaté, Cundinamarca).*  
> **Stack:** Flutter (Windows Desktop & Android/iOS) · Arquitectura **MVC** · Cliente–Servidor · **Offline-First** (Hive cifrado AES-256 + Firebase Firestore / Auth / FCM HTTP v1) · Metología **XP** · GitHub Actions CI.

---

## Módulos y Alcance Principal

- **Panel Administrativo y Operación en Planta (Escritorio):**
  - Autenticación y control de acceso por roles (`ADMIN`, `OPERARIO`, `PRODUCTOR`).
  - Captura rápida de recepción de leche 100% por teclado (`< 10 s`), detección de duplicados y operación continua Offline-First en Hive AES-256.
  - Gestión de productores con unicidad por cédula/código, vinculación móvil y consentimiento obligatorio **Ley 1581 de 2012 (Habeas Data)**.
  - Tarifas históricas por litro, cierre quincenal atómico sin doble liquidación, confirmación de pagos y comprobantes PDF con huella criptográfica SHA-256 (**Ley 527 de 1999**).
  - Dashboard operativo, reportes individuales y consolidados (**CSV** UTF-8 BOM + **PDF**), bitácora inmutable `auditoria_logs` y emisor de comunicados institucionales.
- **Portal Móvil del Productor (Android / iOS):**
  - Aislamiento estricto por UID en `firestore.rules` y vista solo lectura optimizada para campo (`>= 15px` en tipografía local `Inter` offline).
  - Pestañas **Resumen**, **Mis Entregas** y **Liquidaciones y Avisos** (comprobantes PDF descargables, alertas FCM en 4 eventos clave y comunicados masivos).
  - Perfil personal con flujo de **solicitud de rectificación de datos (Ley 1581 de 2012)**.

---

## Ejecución, Pruebas e Integración Continua

```bash
# 1. Instalar dependencias y assets locales (fuentes Inter empaquetadas sin red)
flutter pub get

# 2. Análisis estático (0 issues requeridos)
flutter analyze

# 3. Ejecutar suite completa de pruebas unitarias, E2E y de widgets
flutter test --reporter expanded

# 4. Ejecutar aplicación de escritorio o móvil
flutter run -d windows
```

- **CI/CD:** [.github/workflows/flutter_ci.yml](.github/workflows/flutter_ci.yml)
- **Reglas e Índices Firebase (`asoproganucott-d2a07`):** [firestore.rules](firestore.rules) · [firestore.indexes.json](firestore.indexes.json) · [functions/index.js](functions/index.js)

---

## Documentación Técnica y Evidencias del Proyecto

- [Plan Maestro de Desarrollo (56/56 — 100%)](PLAN_MAESTRO_DESARROLLO.md)
- [Manual Técnico del Sistema](docs/MANUAL_TECNICO.md)
- [Manual de Usuario (Administrador, Operario y Productor)](docs/MANUAL_USUARIO.md)
- [Tablero Kanban e Historias de Usuario XP (`HU-01` a `HU-14`)](docs/KANBAN_HISTORIAS_USUARIO_XP.md)
- [Instrumentos de Recolección en Campo (`OE1`)](docs/INSTRUMENTOS_CAMPO_OE1.md)
- [Actas de Validación (`CHK-03`, `CHK-04`, `CHK-05`)](docs/ACTAS_VALIDACION_CAMPO_CHK03_CHK04_CHK05.md)
- [Evaluación Cuantitativa de Usabilidad TAM (`OE3`, `CHK-07`)](docs/EVALUACION_USABILIDAD_TAM_OE3.md)

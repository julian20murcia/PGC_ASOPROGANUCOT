# ASOPROGANUCOTT — Sistema de Registro y Control de Recepción de Leche Cruda

> **Proyecto de grado:** *Sistema de registro y control de recepción de leche cruda para la asociación lechera ASOPROGANUCOT en el municipio de Susa (Valle de Ubaté, Cundinamarca).*  
> **Stack:** Flutter (Windows Desktop & Android/iOS) · Arquitectura **MVC** · Cliente–Servidor · **Offline-First** (Hive cifrado AES-256 + Firebase Firestore / Auth / FCM HTTP v1) · Metodología **XP** · GitHub Actions CI.

---

## Módulos y Alcance Principal

- **Panel administrativo de escritorio (Windows):**
  - Menú agrupado (**Operación**, **Gestión**, **Inteligencia**) con atajos `Ctrl+1` … `Ctrl+9`; cada usuario solo ve los módulos que su árbol de permisos le habilita.
  - **Inicio:** indicadores del día y del período, gráficas, alertas de calidad de datos y **predicción a 5 meses** (selección automática de modelo por backtesting, banda del 80 % y escenarios financieros).
  - **Recepción de leche:** captura rápida 100 % por teclado con lectura en voz alta y alerta de duplicados, **planilla tipo Excel** (dos columnas por día, corrección y anulación con teclado y auditoría automática) y operación Offline-First en Hive AES-256.
  - **Productores:** asistente de 4 pasos con autorización **Ley 1581 de 2012 (Habeas Data)**, filtros y ordenamientos, panel de detalle y creación de acceso móvil.
  - **Liquidaciones:** asistente de cierre en 3 pasos (verificaciones, revisión y confirmación), quincenas cerradas con matriz diaria, registro de pagos y comprobantes PDF con huella SHA-256 (**Ley 527 de 1999**) para ver, descargar o compartir.
  - **Tarifas por litro** con historial y **parámetros financieros** (precio de venta y costo operativo) para las proyecciones.
  - **Reportes y auditoría:** catálogo de 6 reportes y bitácora de **actividad de usuarios** por colores.
  - **Comunicados** a todos los productores o a uno, con vista previa en celular.
  - **Usuarios y permisos:** alta en 4 pasos y árbol de permisos por módulo y acción, aplicado también en `firestore.rules` y Cloud Functions.
  - **Asistente IA** (OpenAI `gpt-6-luna`) que responde sobre los datos de la asociación, acepta **dictado por voz** (`gpt-transcribe`) y genera **informes en PDF o Excel con gráficas**, con clave en Secret Manager y límites de uso.
  - Exportación unificada a **PDF**, **Excel (.xlsx)** y **CSV** (UTF-8 con BOM, separador `;`) en `Descargas/ASOPROGANUCOTT`.
  - Cierre de sesión automático tras **10 minutos** de inactividad.
- **App móvil del productor (Android / iOS):**
  - Solo lectura, aislada por UID en `firestore.rules`, con **sesión única por dispositivo**.
  - Barra inferior animada (**Inicio**, **Mis entregas**, **Liquidaciones**, **Avisos** y **Perfil**) y recorrido de bienvenida que aparece una sola vez.
  - Carrusel de indicadores, calendario de entregas por jornada, liquidaciones con **desprendible de pago** descargable o compartible, avisos con borrado individual o total, y solicitud de **rectificación de datos (Ley 1581 de 2012)**.

---

## Ejecución, Pruebas e Integración Continua

```bash
# 1. Instalar dependencias (fuentes Inter empaquetadas, sin descarga en tiempo de ejecución)
flutter pub get

# 2. Análisis estático (0 issues requeridos)
flutter analyze

# 3. Pruebas unitarias y de widgets (225 pruebas)
flutter test

# 4. Pruebas de integración contra el proyecto de PRUEBAS de Firebase
#    (requiere la cuenta administradora de pruebas y los productores sembrados)
flutter test integration_test/firebase_e2e_test.dart -d windows

# 5. Pruebas de reglas y Cloud Functions con emulador
firebase emulators:exec --only firestore --project demo-asoproganucot "node --test functions/test/compliance.test.js"

# 6. Ejecutar la aplicación
flutter run -d windows        # escritorio
flutter run -d <dispositivo>  # Android / iOS
```

**Backend Firebase:**

```bash
cd functions && npm install && cd ..
firebase functions:secrets:set OPENAI_API_KEY   # solo la primera vez o al rotar la clave
firebase deploy --only firestore:rules,firestore:indexes,functions
```

- **CI/CD:** [.github/workflows/flutter_ci.yml](.github/workflows/flutter_ci.yml) (análisis y `flutter test`; la integración se ejecuta manualmente).
- **Reglas, índices y funciones (`asoproganucott-d2a07`):** [firestore.rules](firestore.rules) · [firestore.indexes.json](firestore.indexes.json) · [functions/](functions/) (`signInByDocument`, `closeMilkSettlements`, `adminCreateUser`, `adminUpdateUser`, `askAssistant`, `onNotificationCreated`)

---

## Documentación Técnica y Evidencias del Proyecto

- [Plan Maestro de Desarrollo (56/56 — 100%)](PLAN_MAESTRO_DESARROLLO.md)
- [Manual Técnico del Sistema](docs/MANUAL_TECNICO.md)
- [Manual de Usuario (Administrador, Operario y Productor)](docs/MANUAL_USUARIO.md)
- [Tablero Kanban e Historias de Usuario XP (`HU-01` a `HU-14`)](docs/KANBAN_HISTORIAS_USUARIO_XP.md)
- [Instrumentos de Recolección en Campo (`OE1`)](docs/INSTRUMENTOS_CAMPO_OE1.md)
- [Actas de Validación (`CHK-03`, `CHK-04`, `CHK-05`)](docs/ACTAS_VALIDACION_CAMPO_CHK03_CHK04_CHK05.md)
- [Evaluación Cuantitativa de Usabilidad TAM (`OE3`, `CHK-07`)](docs/EVALUACION_USABILIDAD_TAM_OE3.md)

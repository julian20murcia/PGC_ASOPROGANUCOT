---
name: flutter-mvc-architecture
description: Impone la arquitectura estricta Modelo-Vista-Controlador (MVC) y Cliente-Servidor definida en el proyecto de grado.
---

# Skill: Arquitectura MVC Estricta en Flutter

Todo el código en `lib/` debe organizarse y separarse estrictamente bajo el patrón **MVC**:

```text
lib/
├── core/
│   ├── constants/        # Roles, rutas, claves de Hive, configuración
│   ├── theme/            # AppTheme con design-tokens (Plus Jakarta + JetBrains Mono)
│   ├── services/         # FirebaseAuthService, FirestoreService, HiveService, SyncService, FcmService, ReportExportService
│   └── utils/            # Validadores, formateadores de moneda COP y fechas
├── models/               # Entidades puras con serialización Firestore + Hive TypeAdapters
│   ├── user_model.dart
│   ├── producer_model.dart
│   ├── milk_delivery_model.dart
│   ├── price_config_model.dart
│   └── settlement_model.dart
├── controllers/          # Lógica de negocio, estado y orquestación (ChangeNotifier / Provider)
│   ├── auth_controller.dart
│   ├── producer_controller.dart
│   ├── reception_controller.dart
│   ├── settlement_controller.dart
│   └── sync_controller.dart
└── views/
    ├── shared/           # Login, Splash, Widgets del Design System
    ├── desktop/          # Vistas exclusivas de planta (Admin / Operario)
    └── mobile/           # Vistas exclusivas de productores
```

## Reglas Prohibidas
- **Cero lógica en las Vistas (`views/`):** Ningún widget puede importar `cloud_firestore` ni `hive` directamente, ni calcular liquidaciones. Las vistas solo leen estado del Controller y disparan métodos del Controller.
- **Validación de Plataforma:** Todo código relacionado con `firebase_messaging` (notificaciones push) debe estar encapsulado en `FcmService` con validación `if (!kIsWeb && (Platform.isAndroid || Platform.isIOS))` para no romper la compilación en Windows Desktop.
- **Cumplimiento Legal (Ley 1581 de 2012 y Ley 527 de 1999):** El registro de productores debe incluir bandera de autorización de tratamiento de datos personales (`habeasDataAccepted: bool`, fecha y hora) y los registros de entrega/liquidación deben ser inmutables una vez cerrados (usar estados `anulado` con motivo de auditoría en lugar de borrado físico).

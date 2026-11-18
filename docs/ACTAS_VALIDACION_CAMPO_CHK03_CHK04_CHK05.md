# Actas de Validación en Campo — Offline-First, Exactitud Matemática y Alertas FCM (`CHK-03`, `CHK-04`, `CHK-05`)

> **Proyecto:** Sistema ASOPROGANUCOTT — Susa, Cundinamarca (`asoproganucott-d2a07`)  
> **Suite automatizada de respaldo:** [test/unit/e2e_field_validation_test.dart](../test/unit/e2e_field_validation_test.dart)

---

## Acta 1 — Validación Offline-First en Vivo (`CHK-03`, `RNF-01`, `RNF-03`)

| Parámetro | Resultado Automatizado Verificado (`flutter test`) | Protocolo de Verificación en Planta Susa |
| :--- | :--- | :--- |
| **Desconexión simulada (`isOnline = false`)** | Captura de entregas Mañana (`43.25 L`) y Tarde (`28.40 L`) guardadas en `HiveService` con estado `PENDIENTE` e `isSynced = false` sin acceder a la nube. | Deshabilitar Wi-Fi / cable de red en la estación de escritorio durante jornada real en Susa. |
| **Conservación de identidad (`UUID v4`)** | `recepcionId` UUID v4 conservado íntegramente antes y después de sincronizar. | Verificar en consola Firestore que el `doc.id` coincide exactamente con el registro en Hive. |
| **Idempotencia al reconectar** | `SyncService.syncPendingReceptions()` sincronizó `2` registros en la primera corrida y `0` duplicados en la segunda reejecución. | Reconectar internet en planta, verificar barra superior `"En línea"` y ausencia de registros duplicados. |
| **Reflejo en móvil productor** | `ProducerPortalController.loadPortalForUser` muestra las `2` entregas (`71.65 L`) tras sincronizar. | Abrir la app Android del productor con datos móviles y confirmar visibilidad inmediata en **Mis Entregas**. |

**Registro de firma en campo (`CHK-03`):**
- Fecha de ejecución: `____ / ____ / 202__` · Hora desconexión: `______` · Hora reconexión: `______`
- Firma Operario / Administrador: `___________________________`

---

## Acta 2 — Validación Matemática al Centavo e Inmutabilidad (`CHK-04`, `RNF-04`, `RNF-06`, Ley 527 de 1999)

| Caso Verificado | Fórmula / Entrada | Resultado Esperado y Verificado en Código | Estado |
| :--- | :--- | :--- | :---: |
| **Suma exacta Mañana + Tarde** | `43.25 L + 28.40 L` | `71.65 L` (`SettlementCalculator` en milésimas enteras sin deriva `double`) | **Aprobado** |
| **Cálculo monetario al centavo** | `71.65 L * $ 1.850,40` | `$ 132.581,16` (`totalCents = 13258116`) | **Aprobado** |
| **Huella íntegra SHA-256 (Ley 527/1999)** | Campos canónicos + `recepcionIds` ordenados | `hashIntegridad` SHA-256 de 64 caracteres hexadecimales verificable | **Aprobado** |
| **Bloqueo post-liquidación (`RNF-06`)** | Intento de `editReceptionLitros` tras cierre | Lanza `ReceptionServiceException` en cliente y bloqueado en `firestore.rules` | **Aprobado** |
| **Prevención de doble liquidación** | Re-ejecutar cierre sobre el mismo período | Excluye productores con cierre solapado (`alreadySettledProducerIds`) | **Aprobado** |
| **Comprobante PDF válido** | `SettlementPdfService.buildVoucherPdfBytes` | Encabezado binario `%PDF` válido, consecutivo `COMP-YYYY-XXXX` y detalle diario | **Aprobado** |

---

## Acta 3 — Verificación de Alertas Push FCM HTTP v1 en Android (`CHK-05`, `RF-23`, `HU-13`)

| Evento Clave | Origen del Disparador | Tópicos / Destino FCM HTTP v1 (`functions/index.js`) | Verificación Técnica |
| :--- | :--- | :--- | :--- |
| **1. Entrega diaria (`ENTREGA`)** | `ReceptionService.registerReception` | `productor_<productorId>` + `fcmTokens` en `usuarios` | Alerta local Hive + payload `FcmService.parseRemoteMessageData` verificados. |
| **2. Cierre de quincena (`CIERRE_QUINCENA`)** | `SettlementService.closeQuincena` | `productor_<productorId>` + `fcmTokens` en `usuarios` | Generación atómica en `WriteBatch` verificada en pruebas. |
| **3. Liquidación emitida (`LIQUIDACION`)** | `SettlementService.closeQuincena` | `productor_<productorId>` + `fcmTokens` en `usuarios` | Comprobante y notificación visibles en Pestaña 3 móvil. |
| **4. Confirmación de pago (`PAGO`)** | `SettlementService.markAsPaid` | `productor_<productorId>` + `fcmTokens` en `usuarios` | Estado `PAGADA` + notificación automática verificados. |
| **5. Comunicado masivo (`COMUNICADO`)** | `NotificationService.sendInstitutionalBroadcast` | Tópico general `asoproganucott_comunicados` | Emisión desde `AdminShellView` verificada con RBAC `ADMIN`. |

### Protocolo para Prueba Física en Dispositivos Android (`CHK-05`)
1. Desplegar disparador Cloud Functions:
   ```bash
   cd functions
   npm install
   firebase deploy --only functions
   ```
2. Instalar el APK en al menos 2 teléfonos Android de productores asociados y conceder permiso de notificaciones.
3. Probar envío en **primer plano** (app abierta en Pestaña 1) y **segundo plano** (pantalla bloqueada/app minimizada) ejecutando una entrega diaria, un cierre quincenal, una confirmación de pago y un comunicado general desde la estación Windows de Susa.
4. Registrar evidencias: dispositivo `_________________`, versión Android `______`, recepción en primer plano `[ ]`, recepción en segundo plano `[ ]`.

---
name: offline-first-hive-sync
description: Implementa persistencia local atómica en Hive y sincronización automática en segundo plano hacia Firebase Firestore.
---

# Skill: Estrategia Offline-First (Hive + Firebase)

Dado que ASOPROGANUCOT opera en zona rural (Susa, Cundinamarca) con conectividad intermitente, aplica este flujo obligatorio para operaciones críticas (especialmente recepción de leche y gestión de productores):

1. **Escritura Local Primero (Atomic Local Write):**
   - Al registrar una entrega de leche, guarda primero el objeto en la caja de Hive (`deliveries_box`) usando un `UUID v4` generado en cliente como clave primaria (esto evita duplicados al reintentar sincronización).
   - Marca el registro con `isSynced = false` y `createdAt = DateTime.now().toUtc()`.
   - Notifica a la UI inmediatamente (`notifyListeners()`) para que el operario continúe sin esperas de red.
2. **Motor de Sincronización (`SyncService`):**
   - Escucha cambios de conectividad (`connectivity_plus`) y ejecuta un barrido periódico cuando hay acceso a Internet.
   - Toma todos los registros de Hive con `isSynced == false`, los sube en lote (`WriteBatch`) a Firestore respetando las reglas de seguridad por rol, y al recibir confirmación actualiza `isSynced = true` en Hive.
3. **Resolución de Conflictos:**
   - La aplicación de escritorio en planta es la fuente de verdad para entregas y liquidaciones.
   - Si una entrega ya pertenece a una quincena con estado `LIQUIDADA`, bloquea cualquier modificación local o remota.

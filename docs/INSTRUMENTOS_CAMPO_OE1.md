# Instrumentos de Recolección en Campo — Objetivo Específico 1 (`OE1`, `CHK-01`)

> **Proyecto de grado:** *Sistema de registro y control de recepción de leche cruda para la asociación lechera ASOPROGANUCOT en el municipio de Susa (Valle de Ubaté, Cundinamarca)*  
> **Propósito:** Consolidar la guía de observación directa en planta y el guion/síntesis de entrevistas semiestructuradas para el levantamiento riguroso de requerimientos funcionales (`RF-01` a `RF-24`) y no funcionales (`RNF-01` a `RNF-07`).  
> **Nota metodológica:** Los formatos y tablas de síntesis siguientes sirven simultáneamente como instrumento de levantamiento de campo en la planta de Susa y como matriz de trazabilidad directa hacia los módulos implementados en el sistema.

---

## 1. Guía de Observación Directa en Planta de Acopio (Susa, Cundinamarca)

| Campo de Control | Registro / Especificación |
| :--- | :--- |
| **Escenario observado** | Centro de acopio y enfriamiento ASOPROGANUCOTT — Susa, Valle de Ubaté |
| **Jornadas evaluadas** | Jornada Mañana (`05:30 – 10:30`) y Jornada Tarde (`15:00 – 18:30`) |
| **Participantes observados** | Operario(s) de recepción en tanque, Administrador Central y productores de veredas |
| **Modalidad** | Observación no participante con cronómetro y lista de chequeo operativa |

### 1.1 Lista de Chequeo de Proceso Actual vs. Solución Sistematizada

| # | Aspecto Observado en Planta | Hallazgo / Dolor Operativo Identificado | Requerimiento Derivado | Evidencia Implementada |
| :-: | :--- | :--- | :--- | :--- |
| 1 | Identificación del productor en báscula/cantinas | Se dicta código de asociado o nombre en voz alta mientras hay fila de entrega; riesgo de homonimia o digitación lenta. | `RF-04`, `RF-10` | Búsqueda instantánea por código (`ASO-XXX`), cédula o nombre con navegación por teclado (`ReceptionModuleView`). |
| 2 | Horarios y turnos de recepción | Entregas diferenciadas en dos turnos diarios (Mañana y Tarde) que deben totalizarse por separado en la quincena. | `RF-08`, `RF-13` | Selección automática `MANANA` (`< 12:00`) / `TARDE` (`>= 12:00`) editable y desglose en reportes y liquidación. |
| 3 | Conectividad rural en Susa | Intermitencia frecuente de internet en planta durante horas pico de acopio. | `RNF-01`, `RNF-03`, `CHK-03` | Motor Offline-First con Hive cifrado AES-256 (`< 1 s`), registro pendiente por sincronizar y envío idempotente por UUID v4 (`SyncService`). |
| 4 | Errores de doble digitación | Un productor puede aparecer con doble registro involuntario en la misma jornada si no existe alerta. | `RF-09` | Detector `findDuplicate()` por `productorId + fechaEntrega + jornada` con confirmación explícita. |
| 5 | Trazabilidad de correcciones | Ajustar litros a mano en planilla impide saber quién autorizó el cambio o altera liquidaciones ya pagadas. | `RF-11`, `RNF-06`, `RNF-07` | Solo `ADMIN` corrige/anula con motivo obligatorio, traza en `auditoria_logs` y bloqueo absoluto tras cierre (`liquidacionId != null`). |
| 6 | Liquidación quincenal y cálculo de tarifa | Sumar 15 días de mañana y tarde manualmente genera diferencias de redondeo y consumo alto de tiempo administrativo. | `RF-12`, `RF-13`, `RF-14`, `CHK-04` | Tarifas históricas inmutables (`RateService`), aritmética de punto fijo (`SettlementCalculator`), cierre atómico y comprobante PDF Ley 527 de 1999. |
| 7 | Transparencia para el ganadero en finca | El productor desconoce el consolidado de sus litros hasta el día de pago quincenal. | `RF-20` a `RF-24`, `RNF-02` | Portal móvil de solo lectura con saldo quincenal en vivo, historial diario, PDF descargable y alertas push FCM. |
| 8 | Tratamiento de datos personales | Manejo de cédulas, teléfonos y predios rurales requiere cumplimiento formal de privacidad en Colombia. | `RF-05`, `RF-19`, `RNF-05` | Casilla obligatoria y fecha de consentimiento **Ley 1581 de 2012**, aislamiento por UID y flujo de rectificación en móvil. |

---

## 2. Guion y Síntesis de Entrevistas Semiestructuradas (`OE1`)

### 2.1 Bloque A — Administrador Central de ASOPROGANUCOTT

| Pregunta Guía | Necesidad Expresada (Síntesis) | Traducción en Diseño del Sistema |
| :--- | :--- | :--- |
| *¿Cómo se controlan hoy las entregas de cada asociado y los cambios cuando alguien se equivoca al anotar?* | Se requiere que el operario solo registre entregas del día, mientras que únicamente administración pueda ajustar o anular un registro equivocado dejando constancia del motivo. | Separación estricta RBAC (`ADMIN` vs. `OPERARIO` vs. `PRODUCTOR`) y bitácora inmutable `auditoria_logs` (`UserModel`, `ReceptionService`). |
| *¿Cómo se manejan los cortes quincenales y cambios en el precio por litro?* | Los cortes van del día 1 al 15 y del 16 al fin de mes. Si sube el precio por litro este mes, no se pueden recalcular las quincenas que ya fueron pagadas. | `MilkRateModel` por vigencia con cierre automático del período previo sin tocar `liquidaciones` históricas; cálculo determinista en `QuincenaPeriod`. |
| *¿Qué comprobantes y reportes necesitan para contabilidad y entrega al ganadero?* | Comprobante individual por productor con el detalle de cada mañana y tarde, total a pagar, número consecutivo y archivo exportable en Excel/CSV y PDF para reunión de junta. | `SettlementPdfService` (consecutivo `COMP-YYYY-XXXX` + hash SHA-256 Ley 527/1999) y `ReportExportService` (CSV UTF-8 con BOM y PDF consolidado). |

### 2.2 Bloque B — Operario de Recepción en Planta

| Pregunta Guía | Necesidad Expresada (Síntesis) | Traducción en Diseño del Sistema |
| :--- | :--- | :--- |
| *¿Qué es lo más crítico en las mañanas cuando llegan varios productores al mismo tiempo?* | No depender del mouse ni de que haya internet estable: escribir el código, pasar con `Enter`, anotar los litros y guardar en menos de un segundo. | Formulario optimizado con `FocusNode` en `ReceptionModuleView`, captura en `< 10 s` y guardado atómico en Hive antes de subir a la nube. |
| *¿Qué ocurre si un mismo ganadero entrega dos cantinas separadas en un turno?* | El sistema debe advertir que ya entregó esa mañana/tarde por si fue error, pero permitir confirmar si realmente trajo un segundo viaje. | Excepción controlada `DuplicateReceptionException` con diálogo de confirmación explícita (`allowDuplicate: true`). |

### 2.3 Bloque C — Productores / Ganaderos Asociados (Veredas de Susa)

| Pregunta Guía | Necesidad Expresada (Síntesis) | Traducción en Diseño del Sistema |
| :--- | :--- | :--- |
| *¿Qué información le gustaría ver en su celular y bajo qué condiciones la consulta en la finca?* | Poder ver cuánto lleva entregado en la quincena, cuánto le van a pagar y descargar su recibo sin confundirse con botones complicados ni letras pequeñas bajo el sol. | `ProducerShellView` con tipografía `Inter` de alto contraste (`>= 15px`), 3 pestañas simples (`Resumen`, `Mis Entregas`, `Liquidaciones`), navegación `<= 2` toques y solo lectura. |
| *¿Cómo prefiere enterarse cuando le reciben la leche o cuando ya le pagaron la quincena?* | Que le llegue un aviso inmediato al celular cada vez que entrega en planta y cuando salga su liquidación o pago, además de avisos de reuniones de la asociación. | Notificaciones push automáticas FCM HTTP v1 (`ENTREGA`, `CIERRE_QUINCENA`, `PAGO`, `COMUNICADO`) + bandeja móvil persistente offline en Hive. |

---

## 3. Formato para Firma y Evidencia de Levantamiento en Planta

- **Fecha de aplicación en planta:** `____ / ____ / 202__`
- **Responsable del levantamiento (Estudiante / Investigador):** `Bradley Ballen`
- **Visto bueno Administración ASOPROGANUCOTT:** `___________________________` (Cargo: `_____________________`)
- **Representante Operario de Planta:** `___________________________`
- **Observaciones adicionales de campo:** `____________________________________________________________________`

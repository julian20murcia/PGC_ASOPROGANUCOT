# Evaluación Cuantitativa de Usabilidad (Modelo TAM) y Rendimiento (`OE3`, `CHK-07`)

> **Proyecto:** Sistema ASOPROGANUCOTT — Susa, Cundinamarca  
> **Cobertura:** Objetivo Específico 3 (`OE3`), `RNF-02`, `RNF-03`, `CHK-07`

---

## 1. Matriz de Cumplimiento de Métricas Técnicas de Rendimiento

| Métrica de Desempeño | Umbral Exigido | Implementación Técnica Verificada | Estado |
| :--- | :--- | :--- | :---: |
| **Guardado local prioritario Offline (`RNF-03`)** | `< 1 segundo` | `SyncService.registerReceptionOfflineFirst` persiste atómicamente en `deliveries_box` (`HiveService`) antes de intentar subida a Firestore. | **Cumple** |
| **Captura completa por teclado en planta (`HU-03`)** | `< 10 segundos` | `ReceptionModuleView` encadena `FocusNode` (`Código/Cédula -> Jornada -> Litros -> Enter -> Limpieza automática`). | **Cumple** |
| **Profundidad de navegación móvil (`RNF-02`)** | `<= 2 toques` | `ProducerShellView` ofrece barra inferior directa de 3 pestañas (`Resumen`, `Mis Entregas`, `Liquidaciones`) y accesos en 1 toque desde `Resumen`. | **Cumple** |
| **Legibilidad bajo luz solar en campo (`RNF-02`)** | Cuerpo `>= 15px`, alto contraste | Tipografía local `Inter` empaquetada sin red (`assets/fonts/`), fondo claro `#FFFFFF` y texto principal `#0B2619` con tarjetas `>= 15px`. | **Cumple** |

---

## 2. Instrumento Cuantitativo Basado en el Modelo TAM (Escala Likert 1–5)

> Escala: **1** = Totalmente en desacuerdo · **2** = En desacuerdo · **3** = Neutral · **4** = De acuerdo · **5** = Totalmente de acuerdo.

### 2.1 Dimensiones Evaluadas

| Dimensión TAM | Código | Ítem / Pregunta de Evaluación | Rol Destinatario |
| :--- | :---: | :--- | :--- |
| **Facilidad de Uso Percibida (PEOU)** | `PEOU-1` | Aprender a registrar o consultar entregas de leche en la aplicación resulta claro y sencillo. | Operario / Productor |
| **Facilidad de Uso Percibida (PEOU)** | `PEOU-2` | El tamaño de letra y los colores facilitan la lectura en planta y al aire libre bajo luz solar. | Productor / Operario |
| **Facilidad de Uso Percibida (PEOU)** | `PEOU-3` | Encontrar la información de entregas, comprobantes o comunicados toma pocos pasos (`<= 2` toques). | Productor |
| **Utilidad Percibida (PU)** | `PU-1` | El sistema reduce errores en el registro diario de litros (Mañana / Tarde) y evita duplicados accidentales. | Operario / Admin |
| **Utilidad Percibida (PU)** | `PU-2` | Poder trabajar sin internet en planta y sincronizar automáticamente al volver la señal mejora la continuidad operativa. | Operario / Admin |
| **Utilidad Percibida (PU)** | `PU-3` | El cálculo automático de liquidaciones quincenales y los comprobantes PDF agilizan y transparentan los pagos. | Admin / Productor |
| **Actitud hacia el Uso (ATU)** | `ATU-1` | El sistema genera mayor confianza y transparencia entre la asociación y los ganaderos asociados. | Todos |
| **Intención de Uso (BI)** | `BI-1` | Adoptaría y recomendaría el uso permanente de la plataforma ASOPROGANUCOTT en las jornadas diarias en Susa. | Todos |

---

## 3. Plantilla de Tabulación de Resultados en Campo (`OE3`)

| ID Evaluado | Rol (`Admin / Operario / Productor`) | Tiempo Captura (`s`) | `PEOU-1` | `PEOU-2` | `PEOU-3` | `PU-1` | `PU-2` | `PU-3` | `ATU-1` | `BI-1` | Observaciones / Mejoras Aplicadas |
| :-: | :--- | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :-: | :--- |
| E-01 | Administrador Central | — | | | | | | | | | |
| E-02 | Operario de Recepción 1 | | | | | | | | | | |
| E-03 | Operario de Recepción 2 | | | | | | | | | | |
| E-04 | Productor Ganadero 1 | — | | | | | | | | | |
| E-05 | Productor Ganadero 2 | — | | | | | | | | | |
| E-06 | Productor Ganadero 3 | — | | | | | | | | | |

### Criterios de Aceptación y Refactorizaciones ya Incorporadas Pre-Campo
- **Tipografía y contraste:** Unificación global a `Inter` empaquetada offline (`assets/fonts/`), eliminando fuentes con serifas y aumentando cuerpo móvil a `>= 15px`.
- **Vitalidad visual:** Diferenciación por colores institucionales (`primaryGreen`, `skyBlue`, `warmGold`, `tealAccent`, `indigoAccent`) en tarjetas KPI, menús y estados.
- **Escenario 3D desktop:** Ampliación de escala e iluminación de `CowBalloon3DWidget` en el login de escritorio y cabecera wave limpia en móvil.

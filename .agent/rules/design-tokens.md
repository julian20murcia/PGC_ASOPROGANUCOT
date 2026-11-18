---
description: Reglas globales de identidad visual, tipografía, colores y espaciado para ASOPROGANUCOT. Aplica siempre en toda pantalla o componente UI.
---

# Design System: ASOPROGANUCOT (Agro-Fintech Limpio)

## 1. Identidad Visual y Paleta de Colores (Prohibido usar colores por defecto de Material)
- **Fondo Principal (Canvas):** `#F8FAFC` (Gris hielo ultra limpio)
- **Superficies / Tarjetas / Modales:** `#FFFFFF` (Blanco puro) con borde de `1px` en `#E2E8F0` (sin sombras pesadas ni elevation > 0).
- **Color Primario Institucional:** `#0F4C3A` (Verde bosque profundo) — usar en botones principales, indicadores activos y encabezados clave.
- **Color Secundario / Acento:** `#0F172A` (Azul pizarra oscuro) — usar en barras laterales de escritorio y textos de alto contraste.
- **Estados Semánticos:**
  - Éxito / Sincronizado / Pagado: `#10B981` (Texto `#065F46`, Fondo badge `#ECFDF5`)
  - Pendiente / Offline en cola Hive: `#F59E0B` (Texto `#92400E`, Fondo badge `#FFFBEB`)
  - Error / Alerta / Anulado: `#EF4444` (Texto `#991B1B`, Fondo badge `#FEF2F2`)
- **Tipografía de Texto:**
  - Primario: `#0F172A`
  - Secundario / Etiquetas: `#475569`
  - Deshabilitado / Placeholders: `#94A3B8`

## 2. Tipografía Limpia (`google_fonts`)
- **Fuente Principal (UI, Títulos, Cuerpo, Botones):** `Plus Jakarta Sans`.
  - Títulos de pantalla: `24px` (Desktop) / `20px` (Mobile), `FontWeight.w700`, `letterSpacing: -0.5`.
  - Subtítulos / Cards: `16px`, `FontWeight.w600`.
  - Cuerpo / Inputs: `14px` (Desktop) / `15px` (Mobile), `FontWeight.w400`.
- **Fuente Numérica y Financiera (Litros, Precios, Totales, IDs, Fechas):** `JetBrains Mono` con `fontFeatures: [FontFeature.tabularFigures()]` obligatorio para alineación vertical perfecta en tablas y liquidaciones.

## 3. Geometría, Espaciado y Limpieza
- **Sistema de Espaciado:** Múltiplos estrictos de `4px` (`8, 12, 16, 24, 32`).
- **Radios de Borde:**
  - Tarjetas y contenedores: `12px`
  - Botones, Inputs y Dropdowns: `8px`
  - Badges / Chips de estado: `6px`
- **Inputs de Formulario:** Estilo `OutlineInputBorder` limpio con relleno `#FFFFFF`, borde normal `#CBD5E1` (`1px`) y borde enfocado `#0F4C3A` (`1.5px`). Etiqueta siempre visible arriba del campo, nunca flotante recargada.

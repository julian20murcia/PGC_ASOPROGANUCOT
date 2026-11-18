---
name: ui-design-system
description: Construye interfaces limpias, propias y profesionales en Flutter siguiendo el sistema de diseño Agro-Fintech de ASOPROGANUCOT.
---

# Skill: UI Design System Propio

Cuando diseñes o construyas cualquier pantalla o componente visual:
1. **Cero apariencia genérica:** Nunca uses `AppBar` morados ni `Card` con sombras grises por defecto. Usa contenedores planos blancos (`#FFFFFF`) delimitados por bordes sutiles (`Border.all(color: Color(0xFFE2E8F0))`) y amplios márgenes internos (`EdgeInsets.all(20)` o `24`).
2. **Componentes Reutilizables Obligatorios (`lib/views/shared/widgets/`):**
   - `AppKpiCard`: Tarjeta métrica con título en `Plus Jakarta Sans` (`#475569`), cifra principal en `JetBrains Mono` tabular (`28px`, `w700`) e indicador de estado o tendencia.
   - `SyncStatusBadge`: Indicador visual obligatorio en recepción y consultas que muestra si un registro está `"Sincronizado"` (verde) o `"Local / Offline"` (ámbar).
   - `PrimaryActionButton`: Botón de altura fija (`48px` desktop, `52px` móvil), fondo `#0F4C3A`, texto blanco `w600`, con estado de carga integrado (`CircularProgressIndicator` de `18px`).
   - `CleanDataTable`: Tabla administrativa con encabezados en mayúscula sutil (`12px`, `w600`, `#475569`), filas con hover suave (`#F1F5F9`) y cifras alineadas a la derecha en `JetBrains Mono`.
3. **Jerarquía Visual:** Prioriza siempre el dato operativo (litros entregados, valor a pagar, nombre del productor) sobre elementos decorativos. Evita gradientes innecesarios e iconos sobrecargados.

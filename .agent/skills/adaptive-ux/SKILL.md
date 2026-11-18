---
name: adaptive-ux
description: Adapta la experiencia de usuario entre la aplicación de Escritorio (Planta ASOPROGANUCOT) y la aplicación Móvil (Productores/Ganaderos).
---

# Skill: Experiencia Dual Adaptativa (Planta vs. Campo)

El proyecto compila desde un único código fuente hacia Windows Desktop (administración en planta) y Android/iOS (consulta de productores). Aplica estas reglas según el rol y plataforma:

## 1. Modo Escritorio — Planta ASOPROGANUCOT (Administrador / Operario)
- **Navegación:** `NavigationRail` lateral izquierdo fijo (`240px` expandido / `72px` colapsado) en `#0F172A` con iconos minimalistas y barra superior (`TopBar`) que muestra el usuario activo, fecha actual y estado global de red (Online / Offline).
- **Flujo de Recepción Rápida (Alta Velocidad):**
  - El formulario de registro de leche debe operar 100% con teclado (`FocusNode`): buscar productor por código o cédula -> seleccionar turno (Mañana / Tarde) -> digitar litros -> presionar `Enter` para guardar al instante y limpiar el campo para el siguiente ganadero.
- **Módulos Administrativos:** Dashboard operativo, Gestión de Productores (CRUD), Registro de Recepción Diaria, Liquidación Quincenal de Pagos, Tarifas por Litro y Exportación de Reportes (PDF/CSV).

## 2. Modo Móvil — Productores Ganaderos (Consulta en Campo)
- **Legibilidad en Exteriores:** Alto contraste y tamaños de fuente generosos (`>= 15px` en cuerpo) pensados para lectura bajo luz solar en finca.
- **Navegación Simple:** Máximo 3 pestañas inferiores (`NavigationBar` limpio):
  1. **Resumen:** Litros acumulados en la quincena actual, último pago liquidado y gráfico simple de entregas recientes.
  2. **Mis Entregas:** Lista cronológica con fecha, turno (Mañana/Tarde), litros y estado de sincronización.
  3. **Liquidaciones y Avisos:** Historial de quincenas cerradas, detalle de valor por litro, comprobante descargable/visualizable y bandeja de notificaciones push.
- **Restricción de Seguridad:** El productor tiene interfaz de solo lectura sobre entregas y pagos; nunca mostrar botones de edición o eliminación en móvil.

# Manual de Usuario — Plataforma ASOPROGANUCOTT (`CHK-08`)

> **Asociación de Productores y Ganaderos — Susa, Valle de Ubaté, Cundinamarca**
> Guía práctica paso a paso para los tres perfiles del sistema: **Administrador**, **Operario de planta** y **Productor (app móvil)**.
> Versión actualizada al rediseño de la interfaz (sistema visual "Pradera": verde azulado institucional con acentos ámbar).

---

## Contenido

1. [Antes de empezar](#1-antes-de-empezar)
2. [Iniciar y cerrar sesión](#2-iniciar-y-cerrar-sesión)
3. [Conocer la pantalla de escritorio](#3-conocer-la-pantalla-de-escritorio)
4. [Inicio (panel de indicadores y predicciones)](#4-inicio-panel-de-indicadores-y-predicciones)
5. [Recepción de leche (Operario y Administrador)](#5-recepción-de-leche)
6. [Productores](#6-productores)
7. [Liquidaciones quincenales](#7-liquidaciones-quincenales)
8. [Tarifas por litro y parámetros financieros](#8-tarifas-por-litro-y-parámetros-financieros)
9. [Reportes y auditoría](#9-reportes-y-auditoría)
10. [Comunicados](#10-comunicados)
11. [Usuarios y permisos](#11-usuarios-y-permisos)
12. [Asistente IA](#12-asistente-ia)
13. [Descargar y compartir archivos](#13-descargar-y-compartir-archivos)
14. [App móvil del productor](#14-app-móvil-del-productor)
15. [Preguntas frecuentes](#15-preguntas-frecuentes)

---

## 1. Antes de empezar

| Perfil | Dónde trabaja | Qué puede hacer |
| :--- | :--- | :--- |
| **Administrador** | Aplicación de escritorio (Windows) | Todo: recepción, productores, cierres de quincena, pagos, tarifas, reportes, comunicados, usuarios y asistente IA. |
| **Operario** | Aplicación de escritorio (Windows) | Lo que el administrador le habilite. Por defecto: ver Inicio, registrar entregas y descargar la planilla de recepción, y consultar productores, liquidaciones, tarifas, comunicados y el asistente IA. |
| **Productor** | App móvil (Android / iOS) | Consultar sus entregas, liquidaciones, desprendibles de pago y avisos, y pedir corrección de sus datos. No puede modificar registros. |

**Formato de números.** La plataforma usa el formato colombiano: punto para los miles y coma para los decimales (por ejemplo `1.250,5 L` o `$ 1.850`). Al escribir cantidades, los puntos de miles se colocan solos mientras digita.

**Límites de los campos.** Cada campo tiene un tamaño máximo para que la información no se corte en pantallas ni en los PDF. Algunos ejemplos: nombres hasta 40 caracteres, nombre completo hasta 80, cédula de 5 a 12 dígitos, celular de 10 dígitos (debe empezar por `3` o por `60`), finca hasta 60, vereda hasta 40, títulos hasta 80 y mensajes hasta 500. Los litros por entrega no pueden pasar de `5.000 L`.

---

## 2. Iniciar y cerrar sesión

### 2.1 Iniciar sesión

1. Abra la aplicación ASOPROGANUCOTT.
2. En **Correo o documento** escriba su correo o su número de cédula.
3. En **Contraseña** escriba su clave. Puede usar el ojo para **Mostrar contraseña**. Si aparece el aviso **Bloq Mayús activado**, desactive las mayúsculas.
4. Deje marcado **Recordar acceso** si quiere que el equipo recuerde su usuario y mantenga la sesión al volver a abrir la aplicación.
5. Pulse **Ingresar al sistema**.

- Administradores y operarios entran al **panel de escritorio**.
- Los productores usan la **app móvil** (ver sección 14).

### 2.2 Recuperar la contraseña

1. Escriba su **correo electrónico** (no la cédula) en el primer campo.
2. Pulse **¿Olvidaste tu contraseña?**.
3. Revise su correo y siga el enlace de recuperación.

### 2.3 Cierre automático por inactividad (escritorio)

Por seguridad, si el panel de escritorio queda **10 minutos sin uso**, la sesión se cierra sola.

1. Un minuto antes aparece la ventana **¿Sigues ahí?** con una cuenta regresiva.
2. Pulse **Seguir conectado** para continuar, o **Cerrar sesión** para salir de una vez.
3. Si no responde, volverá a la pantalla de ingreso con el mensaje *"Tu sesión se cerró por inactividad (10 minutos sin uso)"*.

Las entregas guardadas en el equipo que aún no se han enviado a la nube **no se pierden** al cerrar sesión.

### 2.4 Una sola sesión en el celular

En la app móvil una cuenta solo puede estar abierta en **un teléfono a la vez**. Si inicia sesión en otro celular, el primero se cierra con el mensaje *"Tu cuenta se abrió en otro dispositivo, por eso cerramos la sesión en este."* Si un administrador suspende la cuenta, la sesión también se cierra.

### 2.5 Cerrar sesión en escritorio

1. Haga clic en su nombre, en la parte inferior del menú lateral.
2. Elija **Cerrar sesión** y confirme.

---

## 3. Conocer la pantalla de escritorio

### 3.1 Menú lateral

El menú está organizado en tres grupos. Cada módulo tiene un atajo de teclado:

| Grupo | Módulo | Atajo |
| :--- | :--- | :--- |
| **Operación** | Inicio | `Ctrl + 1` |
| | Recepción de Leche | `Ctrl + 2` |
| | Productores | `Ctrl + 3` |
| | Liquidaciones | `Ctrl + 4` |
| **Gestión** | Tarifas por Litro | `Ctrl + 5` |
| | Reportes y Auditoría | `Ctrl + 6` |
| | Comunicados | `Ctrl + 7` |
| | Usuarios | `Ctrl + 8` |
| **Inteligencia** | Asistente IA | `Ctrl + 9` |

- Solo verá los módulos para los que tiene permiso. Los atajos conservan su número aunque falten módulos.
- Si su cuenta no tiene ningún módulo asignado, verá *"Tu cuenta no tiene módulos asignados"*: pida permisos al administrador.
- En pantallas anchas puede usar **Contraer menú** para ganar espacio. En ventanas angostas el menú se abre con el botón **Menú**.

### 3.2 Barra superior

- La ruta del módulo actual (por ejemplo *Operación > Recepción de Leche*).
- **N por sincronizar**: entregas guardadas en este equipo que todavía no se han enviado a la nube.
- **En línea / Sin conexión**: estado de internet.
- Fecha y hora.
- **Preguntar a la IA**: abre el asistente (si tiene permiso).

### 3.3 Selector de fechas

Muchos módulos tienen un campo de rango de fechas. Al abrirlo:

1. Use un atajo rápido: **Hoy**, **Ayer**, **Últimos 7 días**, **Esta quincena**, **Quincena anterior**, **Este mes**, **Mes anterior**, **Últimos 30 días**, **Últimos 90 días** o **Este año**.
2. O marque en el calendario el día inicial y luego el día final.
3. Pulse **Aplicar**.

---

## 4. Inicio (panel de indicadores y predicciones)

El módulo **Inicio** muestra el *Resumen Operativo de Planta*:

- **Banda de hoy:** litros acopiados hoy (mañana y tarde), cuántos productores han entregado, estado de conexión y entregas pendientes de sincronizar.
- **Accesos rápidos:** Registrar entrega, Productores, Liquidaciones, Tarifas y Reportes (según sus permisos).
- **Indicadores del período** comparados con el período anterior: litros, promedio diario, entregas, productores que entregaron y días sin entregas. Si tiene permisos de liquidaciones, tarifas o reportes, también ve el valor estimado a pagar, el precio vigente y las liquidaciones pendientes.
- **Gráficas:** tendencia diaria, mañana vs. tarde, litros por vereda y productores con mayor entrega.
- **Alertas y calidad de datos:** caídas fuertes de producción, días sin entregas, productores inactivos, registros sin sincronizar y liquidaciones pendientes.

### 4.1 Predicción a 5 meses

La tarjeta **Predicción inteligente · próximos 5 meses** proyecta los litros que se esperan recibir:

- Necesita al menos **14 días** de historia; si no, muestra *"Datos insuficientes para proyectar"*.
- El sistema prueba varios modelos estadísticos y elige el que mejor habría acertado en el pasado. La **Precisión histórica** y el nivel de **confianza** (alta, media o baja) indican qué tan confiable es la proyección.
- La gráfica muestra lo real, la proyección y una franja de **rango 80 %** (lo más probable es que el valor caiga dentro de ella).
- Se presentan tres escenarios: **Pesimista**, **Esperado** y **Optimista**, una tabla por mes y unas **Conclusiones** en lenguaje sencillo.
- Si el administrador configuró el precio de venta y los costos (sección 8.2), la tabla también estima **costo de compra, ingresos y resultado neto**. Si no, aparece el botón **Ir a Tarifas**.

---

## 5. Recepción de leche

### 5.1 Registrar una entrega (captura rápida, solo con el teclado)

1. Abra **Recepción de Leche** (`Ctrl + 2`).
2. En la barra **Captura rápida en planta**, escriba en **Productor** el código, la cédula o el nombre.
3. Use las flechas `↑` `↓` para elegir en la lista y pulse `Enter`. Si la lectura en voz alta está activa, el equipo dirá el nombre del productor para confirmar sin mirar la pantalla.
4. Verifique la jornada: **Mañana** o **Tarde**.
5. Escriba los **Litros** (acepta `12,5`, `12.5`, `1.250` o `1.250,75`).
6. Pulse `Enter` o el botón **Registrar entrega**.
7. Aparece *"Entrega registrada."*, la voz repite los litros y el productor, y el cursor vuelve a **Productor** listo para el siguiente.

**Posible duplicado.** Si ese productor ya entregó en la misma jornada del día, la barra se pone naranja y muestra el aviso *"Posible duplicado…"*. Pulse `Enter` otra vez (botón **Registrar igual**) si de verdad es una segunda entrega, o `Esc` para cancelar.

**Lectura en voz alta.** El botón con el ícono de altavoz activa o silencia la voz.

**Sin internet.** La entrega se guarda en el equipo de forma cifrada y queda como pendiente. Cuando vuelva la conexión pulse **Sincronizar (N)** en la parte superior o espere la subida automática. El indicador **Pendientes de sincronizar** muestra cuántas faltan.

### 5.2 La planilla (como una hoja de Excel)

En la pestaña **Planilla** cada fila es un productor y cada día tiene dos columnas: **Mañana (M)** y **Tarde (T)**. Al final están el **TOTAL L** por productor y, abajo, **TOTAL POR JORNADA** y **TOTAL DEL DÍA**.

Atajos de teclado en la planilla:

| Tecla | Acción |
| :--- | :--- |
| `↑ ↓ ← →` | Moverse entre celdas |
| `Tab` / `Shift + Tab` | Celda siguiente / anterior |
| `Inicio` / `Fin` | Ir al comienzo / final |
| `RePág` / `AvPág` | Subir / bajar una pantalla |
| `Enter`, `F2` o escribir un número | Editar la celda |
| `Enter` (editando) | Guardar y bajar (`Shift + Enter` guarda y sube) |
| `Esc` | Cancelar la edición |
| `Supr` o `Retroceso` | Anular la entrega de la celda |

Marcas en las celdas: punto = pendiente de sincronizar, triángulo = corregida, candado = liquidada.

### 5.3 Corregir litros en la planilla

1. Abra la pestaña **Planilla** y elija el rango de fechas (por ejemplo **Esta quincena**).
2. Ubique con las flechas la celda del productor, día y jornada.
3. Pulse `Enter` (o escriba directamente el nuevo número).
4. Escriba la cantidad correcta y pulse `Enter`.
5. El cambio queda guardado y registrado en la auditoría con un motivo automático (por ejemplo *"Corrección en planilla: 30 L → 32 L"*).

Para **registrar una entrega que faltó**, haga lo mismo sobre una celda vacía.

### 5.4 Anular una entrega

1. Ubique la celda y pulse `Supr` (o borre el número y guarde).
2. Aparece *"¿Anular X L de …? Enter confirma · Esc cancela"*.
3. Pulse `Enter` o **Anular**. Verá *"Entrega anulada y registrada en auditoría."*

### 5.5 Pestaña Registros

Muestra cada entrega con fecha, hora, código, productor, jornada, litros, estado y operario. Puede filtrar por jornada y por estado (**Solo activas**, **Pendientes**, **Anuladas**, **Todas**).

- **Corregir:** haga clic sobre los litros, escriba el nuevo valor y pulse `Enter`.
- **Anular:** pulse el ícono **Anular entrega** y confirme con **Anular**.
- Use esta pestaña cuando una jornada tenga varias entregas del mismo productor.

### 5.6 Cuándo no se puede editar

- Entregas **liquidadas** (la quincena ya se cerró): quedan bloqueadas por ley.
- Fechas futuras y productores inactivos.
- Si su usuario no tiene el permiso de registrar, corregir o anular. En ese caso la planilla indica *"Solo lectura"*.

### 5.7 Descargar la planilla

Pulse el botón de descarga, elija **PDF**, **Excel** o **CSV** (ver sección 13). El Excel trae dos hojas: *Planilla* y *Registros*.

---

## 6. Productores

### 6.1 Registrar un productor (asistente de 4 pasos)

1. Abra **Productores** (`Ctrl + 3`) y pulse **Nuevo productor**.
2. **Paso 1 – Datos personales:** nombres, apellidos, cédula y celular.
3. **Paso 2 – Finca:** código de asociado (puede usar el **código sugerido**), nombre de la finca y vereda.
4. **Paso 3 – Autorización de datos (Ley 1581 de 2012):**
   1. Entregue al productor el aviso de privacidad que aparece en pantalla.
   2. Obtenga su autorización firmada o electrónica.
   3. Marque *"Entregué el aviso y el productor autorizó el tratamiento de sus datos."*
   4. En **Soporte de autorización** escriba una referencia para encontrar el documento (por ejemplo *"Formato firmado N.º 045 · Carpeta 2026"*). No copie el documento de identidad.
5. **Paso 4 – Revisar y guardar:** revise el resumen (puede pulsar **Editar** en cualquier sección) y pulse **Guardar productor**.

Puede volver atrás sin perder lo escrito. `Ctrl + Enter` avanza al siguiente paso.

### 6.2 Dar acceso a la app móvil

1. Al terminar el registro, en la ventana **Productor registrado** pulse **Crear acceso a la app móvil** (o use **Crear acceso app** desde el panel del productor).
2. Escriba el **correo electrónico** y una **contraseña inicial** (mínimo 8 caracteres, con letras y números).
3. Pulse **Crear acceso** y entregue los datos al productor de forma segura.

### 6.3 Buscar, filtrar y ordenar

- Filtre por estado (**Todos**, **Activos**, **Inactivos**) y por vereda.
- Busque por nombre, cédula, código o finca.
- Ordene por **Más recientes**, **Más antiguos**, **Más leche entregada**, **Menos leche entregada**, **Nombre A–Z** o **Código**.
- **Limpiar filtros** devuelve la vista completa.

### 6.4 Consultar, editar o inactivar

1. Haga clic en un productor para abrir su panel de detalle: entregas del período, gráfica de los últimos 30 días, últimas entregas, datos y autorización de datos.
2. Use **Editar** para cambiar datos, o **Inactivar / Activar** para cambiar su estado. El historial se conserva siempre.
3. `Esc` cierra el panel.

### 6.5 Exportar el directorio

Pulse **Exportar** y elija PDF, Excel o CSV. Se exporta la lista con los filtros que tenga aplicados.

---

## 7. Liquidaciones quincenales

El módulo **Liquidaciones** (`Ctrl + 4`) muestra la **quincena en curso**, el valor estimado con la tarifa vigente y la tabla de **Quincenas cerradas**.

### 7.1 Cerrar una quincena (asistente de 3 pasos)

> Antes de cerrar: sincronice todas las entregas y verifique que haya una tarifa vigente.

1. Pulse **Cerrar quincena**.
2. **Paso 1 – Elegir quincena:** escoja **Quincena anterior**, **Quincena actual** o un rango propio. Revise la lista de **Verificaciones**: entregas pendientes de sincronizar, tarifa que se aplicará, días sin registros y comprobantes ya emitidos. Pulse **Continuar**.
3. **Paso 2 – Revisar productores:** revise litros (mañana, tarde, total), precio y valor de cada productor. Si debe dejar a alguien por fuera, quítele la marca: sus entregas quedan abiertas para un cierre posterior. Pulse **Continuar**.
4. **Paso 3 – Confirmar cierre:** lea el resumen y el recuadro *"Qué pasará al confirmar"*:
   - Se bloquean las entregas del período (ya no se pueden corregir ni anular).
   - Se genera un comprobante por productor con consecutivo `COMP-AAAA-####` y código de verificación.
   - Se notifica a cada productor en su celular.
5. Pulse **Cerrar quincena (N)** y no cierre la ventana mientras dice *"Cerrando…"*.
6. Al terminar pulse **Ver quincena cerrada**. Si algo falló, pulse **Revisar y reintentar**: los comprobantes ya emitidos no se repiten.

**Esta acción no se puede deshacer.**

### 7.2 Consultar una quincena cerrada

1. En **Quincenas cerradas** haga clic en el período.
2. Pestaña **Productores**: litros, precio por litro, valor, estado de pago y comprobante de cada uno.
3. Pestaña **Registros diarios**: matriz con los litros de cada productor por día y el total por día.

### 7.3 Registrar un pago

1. Dentro de la quincena, en la fila del productor, abra las acciones y elija **Registrar pago**.
2. Indique la **Fecha del pago**.
3. En **Referencia u observación** escriba cómo se pagó (por ejemplo *"Transferencia 0045"* o *"Efectivo en planta"*). Mínimo 3 caracteres.
4. Pulse **Registrar pago**. El comprobante pasa a **Pagada** y el productor recibe un aviso.

### 7.4 Ver, descargar o compartir un comprobante

1. En la fila del productor elija:
   - **Ver comprobante** para abrir el PDF (desde allí puede imprimir, **Descargar** o **Compartir**).
   - **Descargar PDF** para guardarlo en *Descargas › ASOPROGANUCOTT*.
   - **Compartir en…** para enviarlo por correo, WhatsApp u otra aplicación instalada.
2. En escritorio aparece el aviso *"Comprobante … guardado en Descargas"* con el botón **Abrir carpeta**.

### 7.5 Descargar la quincena completa

Pulse **Descargar quincena** y elija **PDF** (consolidado), **Excel** (hojas Resumen, Productores, Registros diarios y Registros) o **CSV**.

---

## 8. Tarifas por litro y parámetros financieros

### 8.1 Publicar una nueva tarifa

1. Abra **Tarifas por Litro** (`Ctrl + 5`).
2. En **Nueva tarifa vigente** escriba el **Precio por litro**, la fecha en que **Rige desde** y el **Motivo del cambio** (por ejemplo *"Ajuste acordado en asamblea de noviembre"*).
3. Revise el impacto estimado que se muestra debajo.
4. Pulse **Publicar tarifa** y confirme.

La tarifa anterior se cierra sola y queda en el **Historial de tarifas**. Las quincenas ya cerradas **no cambian**.

### 8.2 Parámetros financieros

En **Parámetros financieros** el administrador registra:

- **Precio de venta por litro**: lo que paga la industria a la asociación.
- **Costo operativo mensual**: transporte, tanque, personal, energía.

Pulse **Guardar parámetros**. Estos datos **no afectan las liquidaciones**: solo sirven para calcular el margen por litro, el margen bruto mensual y la ganancia estimada que aparecen en las predicciones del Inicio.

---

## 9. Reportes y auditoría

### 9.1 Descargar un reporte

1. Abra **Reportes y Auditoría** (`Ctrl + 6`), pestaña **Reportes**.
2. Elija un reporte del catálogo:
   - Consolidado de recepción
   - Resumen por productor
   - Liquidaciones y pagos
   - Comparativo mañana / tarde
   - Productores sin entregas
   - Correcciones y anulaciones (con responsable y motivo)
3. Ajuste el rango de fechas, el productor y la jornada.
4. Revise la **Vista previa**.
5. Pulse **Descargar** y elija PDF, Excel o CSV.

### 9.2 Revisar la actividad de los usuarios

1. Abra la pestaña **Actividad de usuarios**.
2. Filtre por fechas, usuario, tipo de acción o módulo, o use **Buscar en la actividad…**.
3. Cada acción tiene un color: azul para inicios de sesión, verde para registros y pagos, ámbar para correcciones, rojo para anulaciones, entre otros.
4. Abra un evento para ver el detalle: valores antes y después, motivo y registros relacionados.
5. Si no encuentra algo, pulse **Buscar en registros anteriores** o **Cargar más actividad**.
6. Use **Descargar actividad** para exportar lo filtrado.

---

## 10. Comunicados

### 10.1 Enviar un comunicado

1. Abra **Comunicados** (`Ctrl + 7`).
2. En **Redactar comunicado** elija los destinatarios: **Todos los productores** o **Un productor** (búsquelo por nombre, código o cédula).
3. Escriba el **Título** (3 a 80 caracteres) y el **Mensaje** (5 a 500 caracteres).
4. Revise cómo se verá en la sección **Así se verá en el celular**.
5. Pulse **Enviar comunicado** y confirme.

Por privacidad, la notificación del celular solo dice *"Tienes un nuevo aviso. Consúltalo en la aplicación."*; el texto completo se lee dentro de la app.

### 10.2 Historial

En **Historial de comunicados** puede buscar mensajes enviados, ver si un aviso individual fue **Leído** y **Eliminar comunicado**. Las notificaciones que ya llegaron al celular no se pueden retirar.

---

## 11. Usuarios y permisos

### 11.1 Crear un usuario

1. Abra **Usuarios** (`Ctrl + 8`) y pulse **Nuevo usuario**.
2. **Paso 1 – Datos:** nombre completo, documento, celular, correo electrónico, contraseña (mínimo 8 caracteres, con letras y números) y su confirmación. Deje encendido **Cuenta activa**.
3. **Paso 2 – Rol:** elija **Administrador**, **Operario** o **Productor**. Para un productor debe escoger a qué productor del padrón pertenece la cuenta. Solo un administrador puede crear otro administrador.
4. **Paso 3 – Permisos** (solo operarios): ajuste el árbol de permisos (ver 11.2).
5. **Paso 4 – Revisar:** confirme y pulse **Crear usuario**.

La persona podrá ingresar con su correo o con su documento.

### 11.2 Asignar permisos a un operario

El árbol muestra cada módulo con sus acciones. Marque lo que la persona puede hacer:

| Módulo | Acciones disponibles |
| :--- | :--- |
| Inicio y estadísticas | Ver |
| Recepción de leche | Ver, Crear (registrar entregas), Editar (corregir litros), Eliminar / anular, Descargar |
| Productores | Ver, Crear, Editar, Eliminar (inactivar), Descargar |
| Liquidaciones | Ver, Crear (cerrar quincenas), Editar (registrar pagos), Descargar |
| Tarifas por litro | Ver, Crear (publicar tarifas) |
| Reportes y auditoría | Ver, Descargar |
| Usuarios y permisos | Ver, Crear, Editar, Eliminar (suspender cuentas) |
| Comunicados | Ver, Crear, Eliminar |
| Asistente IA | Ver |

- **Conceder todo el módulo** / **Quitar todo el módulo** marca o desmarca un módulo completo. **Todo** y **Nada** aplican a todos.
- Al marcar cualquier acción se marca también **Ver**.
- **Restablecer a permisos del rol** vuelve a los permisos por defecto del operario.
- Los permisos se aplican tanto en la pantalla como en el servidor: aunque alguien intente saltarse la interfaz, la base de datos rechaza lo que no tiene permitido.

### 11.3 Otras acciones sobre un usuario

En el menú de cada fila:

- **Editar datos** (incluidos rol y permisos).
- **Ver actividad**: lleva a la bitácora filtrada por ese usuario.
- **Restablecer contraseña (correo)**: envía un enlace al correo de la persona.
- **Suspender cuenta** / **Activar cuenta**: la persona no podrá ingresar, pero su historial se conserva.

No puede suspender su propia cuenta ni cambiar su propio rol, y siempre debe quedar al menos un administrador activo.

---

## 12. Asistente IA

El **Asistente IA** (`Ctrl + 9` o botón **Preguntar a la IA**) responde preguntas en lenguaje natural sobre los datos de la asociación, permite **dictar** las preguntas con el micrófono y genera **informes en PDF o Excel con gráficas**.

### 12.1 Hacer una pregunta

1. Abra el asistente.
2. Pulse una de las sugerencias (por ejemplo *"¿Quién entregó más leche este mes?"* o *"¿Cuánto debemos pagar esta quincena?"*) o escriba su pregunta.
3. Pulse `Enter` para enviar (`Shift + Enter` hace un salto de línea).
4. Espere mientras aparece *"Pensando…"*.
5. Use **Copiar respuesta** si quiere pegarla en otro documento.
6. **Nueva conversación** borra el historial y empieza de cero.

### 12.2 Dictar por voz

1. Pulse el botón del **micrófono** junto a *Enviar*. La primera vez, el sistema puede pedir permiso para usar el micrófono.
2. Hable con normalidad. Verá un punto rojo y el tiempo de grabación (máximo 3 minutos).
3. Pulse **■** para terminar. El texto aparece en el cuadro de pregunta.
4. Revíselo, corríjalo si hace falta y pulse `Enter` para enviar. Con **✕** descarta la grabación.

### 12.3 Pedir informes (PDF o Excel)

1. Pida el informe con sus palabras, por ejemplo: *"Hazme un informe en PDF de los 10 productores que más leche entregaron en octubre, con una gráfica de barras y otra de torta"* o *"Excel con la producción diaria de esta quincena y una gráfica de líneas"*.
2. El asistente calcula las cifras y responde con una **tarjeta del informe** que muestra una vista previa de la gráfica.
3. Pulse **Descargar PDF** o **Descargar Excel**. Los dos formatos están disponibles. En el computador el archivo queda en `Descargas/ASOPROGANUCOTT` (botón **Abrir carpeta**); en el celular se abre el menú para compartir.
4. El Excel trae una hoja de *Resumen*, una hoja por cada tabla y una hoja por cada gráfica, con la gráfica de Excel lista para editar.

### 12.4 Tenga en cuenta

- Solo responde sobre la plataforma: productores, entregas, litros, tarifas, liquidaciones, pagos, usuarios y finanzas. No revela documentos, correos ni teléfonos.
- Las respuestas se generan con IA: **verifique las cifras importantes** en los módulos o reportes.
- Cada pregunta admite hasta 1.500 caracteres. Si alcanza un límite de uso, el asistente hace una pausa corta antes de recibir otra pregunta.
- Hay un límite de uso por persona (30 preguntas por hora y 150 por día) y un cupo diario para toda la asociación. Si lo alcanza, intente más tarde.
- Necesita internet.

---

## 13. Descargar y compartir archivos

Al pulsar cualquier botón de descarga puede elegir:

| Formato | Para qué sirve |
| :--- | :--- |
| **PDF** | Documento formal listo para imprimir o enviar. |
| **Excel (.xlsx)** | Hoja de cálculo con encabezados, filtros y totales. |
| **CSV** | Datos planos para otros sistemas; se abre bien en Excel en español (separado por punto y coma). |

- **En el computador** los archivos se guardan en la carpeta **Descargas › ASOPROGANUCOTT**. El aviso de confirmación trae el botón **Abrir carpeta**.
- **En el celular** se abre el menú de compartir del teléfono para guardarlo o enviarlo por WhatsApp, correo, Drive, etc.

---

## 14. App móvil del productor

La app es **de solo consulta**: el productor ve su información pero no puede cambiar entregas ni pagos.

### 14.1 Crear su cuenta desde la app (alta digital)

Si ya está inscrito en el padrón de la asociación, puede crear su propia cuenta:

1. En la pantalla de ingreso toque **Crear cuenta de productor**.
2. Abra la política de tratamiento de datos y confirme la autorización.
3. Escriba su número de documento y el celular registrado en la asociación.
4. Escriba el código que le llega por SMS.
5. Cree su contraseña (escríbala dos veces).
6. Ingrese con su número de documento y esa contraseña.

Si el documento y el celular no coinciden con el padrón, comuníquese con la asociación para actualizar sus datos.

### 14.2 Primer ingreso y recorrido de bienvenida

1. Ingrese con su cédula (o el correo que le entregó la asociación) y su contraseña.
2. La primera vez aparece un **recorrido guiado** que explica cada parte de la app. Pulse **Siguiente** para avanzar, **¡Listo!** al final, o **Saltar** para omitirlo.
3. El recorrido aparece solo una vez. Puede volver a verlo desde **Perfil › Ver recorrido de nuevo**.

### 14.3 Barra inferior

La barra tiene las pestañas **Inicio**, **Mis entregas**, **Liquidaciones** y **Avisos**, y en el centro el botón **Perfil** con sus iniciales. La pestaña Avisos muestra cuántos avisos no ha leído. El botón *atrás* del teléfono lo regresa al Inicio.

### 14.4 Inicio

- **Tarjetas que se mueven solas** (también puede deslizarlas): leche de esta quincena, valor estimado a recibir según la tarifa vigente, promedio diario, comparación con la quincena anterior, racha de entregas y mejor día de los últimos 30 días.
- **Tu producción:** gráfica de barras de **7 días** o **30 días** (verde = mañana, ámbar = tarde).
- **Mañana vs. tarde**, **Quincena en curso** (cuándo cierra y cuántos días faltan), **Última liquidación** y **Últimas entregas** con el botón **Ver calendario**.

### 14.5 Mis entregas (calendario)

1. Deslice el calendario o use las flechas para cambiar de mes.
2. Cada día muestra el total y dos barritas: mañana y tarde. Los colores más intensos indican más litros.
3. Toque un día para ver el detalle: total del día, valor estimado y cada registro con su estado (**Sincronizada**, **Por sincronizar**, **Liquidada** o **Anulada**).
4. Arriba verá el **Resumen del mes**: litros, entregas y días con entrega.

### 14.6 Liquidaciones y desprendible de pago

1. Abra **Liquidaciones**. Verá lo pagado, lo pendiente y la lista de quincenas cerradas (**Pagada** o **Pendiente de pago**).
2. Toque una quincena para ver el total a pagar, los litros, el precio por litro, lo entregado cada día y los **Datos del pago** (comprobante, fechas, referencia y código de integridad).
3. Pulse **Ver desprendible** para abrir el PDF dentro de la app.
4. Pulse **Descargar** (o **Descargar / Compartir PDF** desde la vista previa) para guardarlo o enviarlo por WhatsApp, correo u otra app.

### 14.7 Avisos

- Lea las alertas de entregas, cierres de quincena, pagos y comunicados de la asociación.
- Filtre por **Todos** o **No leídos**. Pulse **Marcar todas como leídas** para ponerse al día.
- **Borrar un aviso:** deslícelo hacia la izquierda, o ábralo y pulse **Borrar aviso**. Durante unos segundos puede pulsar **Deshacer**.
- **Borrar todos:** pulse **Borrar todas** y confirme con **Borrar todos**. Esta acción no se puede deshacer.

### 14.8 Perfil

- Consulte sus **Datos personales** (documento, teléfono, correo) y **Mi finca** (finca, vereda, código de asociado).
- **Habeas Data:** muestra el aviso de tratamiento de datos y la fecha de su autorización.
- **Solicitar corrección de datos** (Ley 1581 de 2012):
  1. Elija qué dato está mal (teléfono, finca, vereda, nombres u otro).
  2. Escriba el **Dato correcto** y, si quiere, un comentario.
  3. Pulse **Enviar solicitud**. El administrador la revisa.
- **Ver recorrido de nuevo** y **Cerrar sesión**.

---

## 15. Preguntas frecuentes

**¿Qué pasa si se va el internet en la planta?**
Siga registrando normalmente. Las entregas se guardan cifradas en el equipo y se envían al volver la conexión (botón **Sincronizar**). Sincronice todo antes de cerrar una quincena.

**¿Puedo corregir una entrega de una quincena ya cerrada?**
No. Al cerrar la quincena las entregas quedan bloqueadas para proteger los comprobantes (Ley 527 de 1999).

**No veo un módulo en el menú.**
Su usuario no tiene permiso para verlo. Pida al administrador que lo habilite en **Usuarios › Editar datos › Permisos**.

**El productor no recibe notificaciones.**
Verifique que tenga acceso a la app creado, que la cuenta esté activa y que haya iniciado sesión al menos una vez en su celular con internet.

**¿Dónde quedan mis descargas?**
En el computador, en **Descargas › ASOPROGANUCOTT**. En el celular, donde usted elija al compartir.

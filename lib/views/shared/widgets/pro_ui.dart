import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../core/services/file_export_service.dart';
import '../../../core/theme/app_theme.dart';

/// Kit de componentes "Pradera" — compactos, planos y sin tarjetas anidadas.
///
/// Reglas de uso:
/// * Una pantalla = [PageHeader] + secciones [Panel] directamente sobre el
///   canvas. Nunca poner un [Panel] dentro de otro.
/// * Para varios indicadores usar UN [StatStrip] (un solo contenedor con
///   divisores), no una fila de tarjetas grandes.
/// * Espaciado entre secciones: 12 px. Padding interno: 12–16 px.

enum Tone { neutral, brand, success, warning, danger, info, accent }

extension ToneColors on Tone {
  Color get fg => switch (this) {
        Tone.neutral => AppTheme.textSecondary,
        Tone.brand => AppTheme.brand,
        Tone.success => AppTheme.successText,
        Tone.warning => AppTheme.warningText,
        Tone.danger => AppTheme.dangerText,
        Tone.info => AppTheme.infoText,
        Tone.accent => AppTheme.accentDeep,
      };

  Color get solid => switch (this) {
        Tone.neutral => AppTheme.textMuted,
        Tone.brand => AppTheme.brand,
        Tone.success => AppTheme.success,
        Tone.warning => AppTheme.warning,
        Tone.danger => AppTheme.danger,
        Tone.info => AppTheme.info,
        Tone.accent => AppTheme.accent,
      };

  Color get bg => switch (this) {
        Tone.neutral => AppTheme.surfaceSunken,
        Tone.brand => AppTheme.brandSoft,
        Tone.success => AppTheme.successBg,
        Tone.warning => AppTheme.warningBg,
        Tone.danger => AppTheme.dangerBg,
        Tone.info => AppTheme.infoBg,
        Tone.accent => AppTheme.accentSoft,
      };
}

/// Encabezado de página: título, subtítulo y acciones alineadas a la derecha.
class PageHeader extends StatelessWidget {
  const PageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.actions = const <Widget>[],
    this.leading,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final bool narrow = MediaQuery.sizeOf(context).width < 900;
    final Widget text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(title, style: AppTheme.titleStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
        if (subtitle != null) ...<Widget>[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.bodyStyle(fontSize: 13),
          ),
        ],
      ],
    );
    final Widget acts = Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: actions,
    );
    if (narrow && actions.isNotEmpty) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
            Expanded(child: text),
          ]),
          const SizedBox(height: 10),
          acts,
        ],
      );
    }
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (leading != null) ...<Widget>[leading!, const SizedBox(width: 10)],
        Expanded(child: text),
        if (actions.isNotEmpty) ...<Widget>[const SizedBox(width: 12), acts],
      ],
    );
  }
}

/// Sección plana con encabezado opcional. Nunca anidar.
class Panel extends StatelessWidget {
  const Panel({
    super.key,
    this.title,
    this.subtitle,
    this.trailing,
    required this.child,
    this.padding = const EdgeInsets.all(14),
    this.headerPadding = const EdgeInsets.fromLTRB(14, 12, 12, 10),
    this.icon,
    this.divider = true,
    this.color = AppTheme.surface,
  });

  final String? title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry headerPadding;
  final IconData? icon;
  final bool divider;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (title != null) ...<Widget>[
            Padding(
              padding: headerPadding,
              child: Row(
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Icon(icon, size: 16, color: AppTheme.brand),
                    const SizedBox(width: 8),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        Text(title!, style: AppTheme.subtitleStyle(), maxLines: 1, overflow: TextOverflow.ellipsis),
                        if (subtitle != null)
                          Text(
                            subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                          ),
                      ],
                    ),
                  ),
                  ?trailing,
                ],
              ),
            ),
            if (divider) const Divider(height: 1),
          ],
          Flexible(fit: FlexFit.loose, child: Padding(padding: padding, child: child)),
        ],
      ),
    );
  }
}

/// Un indicador dentro de un [StatStrip].
class StatItem {
  const StatItem({
    required this.label,
    required this.value,
    this.hint,
    this.icon,
    this.tone = Tone.brand,
    this.delta,
    this.deltaPositiveIsGood = true,
  });

  final String label;
  final String value;
  final String? hint;
  final IconData? icon;
  final Tone tone;

  /// Variación porcentual frente al período anterior (ej. 0.12 = +12 %).
  final double? delta;
  final bool deltaPositiveIsGood;
}

/// Fila de indicadores en UN solo contenedor con divisores verticales.
class StatStrip extends StatelessWidget {
  const StatStrip({super.key, required this.items, this.minItemWidth = 170});

  final List<StatItem> items;
  final double minItemWidth;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
        border: Border.all(color: AppTheme.border),
      ),
      child: LayoutBuilder(
        builder: (BuildContext context, BoxConstraints c) {
          final int perRow = (c.maxWidth / minItemWidth).floor().clamp(1, items.length);
          final List<Widget> rows = <Widget>[];
          for (int i = 0; i < items.length; i += perRow) {
            final List<StatItem> chunk = items.sublist(i, (i + perRow).clamp(0, items.length));
            rows.add(
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    for (int j = 0; j < perRow; j++) ...<Widget>[
                      if (j > 0) const VerticalDivider(width: 1, thickness: 1, color: AppTheme.dividerLight),
                      Expanded(child: j < chunk.length ? _StatCell(item: chunk[j]) : const SizedBox()),
                    ],
                  ],
                ),
              ),
            );
            if (i + perRow < items.length) rows.add(const Divider(height: 1));
          }
          return Column(mainAxisSize: MainAxisSize.min, children: rows);
        },
      ),
    );
  }
}

class _StatCell extends StatelessWidget {
  const _StatCell({required this.item});
  final StatItem item;

  @override
  Widget build(BuildContext context) {
    final double? d = item.delta;
    final bool good = d == null ? true : (d >= 0) == item.deltaPositiveIsGood;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (item.icon != null) ...<Widget>[
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    color: item.tone.bg,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Icon(item.icon, size: 13, color: item.tone.solid),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTheme.bodyStyle(fontSize: 12, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              item.value,
              style: AppTheme.monoStyle(fontSize: 20, fontWeight: FontWeight.w700),
            ),
          ),
          if (d != null || item.hint != null) ...<Widget>[
            const SizedBox(height: 4),
            Row(
              children: <Widget>[
                if (d != null) ...<Widget>[
                  Icon(
                    d >= 0 ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
                    size: 12,
                    color: good ? AppTheme.success : AppTheme.danger,
                  ),
                  Text(
                    '${(d.abs() * 100).toStringAsFixed(d.abs() >= 0.1 ? 0 : 1)}%',
                    style: AppTheme.monoStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: good ? AppTheme.success : AppTheme.danger,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                if (item.hint != null)
                  Expanded(
                    child: Text(
                      item.hint!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Insignia de estado pequeña.
class StatusBadge extends StatelessWidget {
  const StatusBadge(this.text, {super.key, this.tone = Tone.neutral, this.icon, this.dot = false});

  final String text;
  final Tone tone;
  final IconData? icon;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: tone.bg,
        borderRadius: BorderRadius.circular(AppTheme.radiusBadge),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (dot) ...<Widget>[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone.solid, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          if (icon != null) ...<Widget>[
            Icon(icon, size: 12, color: tone.fg),
            const SizedBox(width: 4),
          ],
          Flexible(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w600, color: tone.fg),
            ),
          ),
        ],
      ),
    );
  }
}

/// Estado vacío compacto.
class EmptyState extends StatelessWidget {
  const EmptyState({
    super.key,
    required this.title,
    this.message,
    this.icon = Icons.inbox_outlined,
    this.action,
  });

  final String title;
  final String? message;
  final IconData icon;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: AppTheme.surfaceSunken, shape: BoxShape.circle),
              child: Icon(icon, size: 22, color: AppTheme.textMuted),
            ),
            const SizedBox(height: 10),
            Text(title, textAlign: TextAlign.center, style: AppTheme.subtitleStyle()),
            if (message != null) ...<Widget>[
              const SizedBox(height: 4),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textMuted, height: 1.4),
                ),
              ),
            ],
            if (action != null) ...<Widget>[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

/// Campo de búsqueda compacto con botón de limpiar.
class AppSearchField extends StatefulWidget {
  const AppSearchField({
    super.key,
    required this.onChanged,
    this.hint = 'Buscar…',
    this.initialValue = '',
    this.width = 280,
  });

  final ValueChanged<String> onChanged;
  final String hint;
  final String initialValue;
  final double? width;

  @override
  State<AppSearchField> createState() => _AppSearchFieldState();
}

class _AppSearchFieldState extends State<AppSearchField> {
  late final TextEditingController _c = TextEditingController(text: widget.initialValue);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Widget field = TextField(
      controller: _c,
      onChanged: (String v) {
        setState(() {});
        widget.onChanged(v);
      },
      inputFormatters: <TextInputFormatter>[LengthLimitingTextInputFormatter(60)],
      style: GoogleFonts.inter(fontSize: 13),
      decoration: InputDecoration(
        hintText: widget.hint,
        prefixIcon: const Icon(Icons.search_rounded, size: 18),
        prefixIconConstraints: const BoxConstraints(minWidth: 36),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        suffixIcon: _c.text.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close_rounded, size: 16),
                onPressed: () {
                  _c.clear();
                  setState(() {});
                  widget.onChanged('');
                },
              ),
      ),
    );
    return widget.width == null ? field : SizedBox(width: widget.width, child: field);
  }
}

/// Etiqueta fija sobre un campo + el campo.
class LabeledField extends StatelessWidget {
  const LabeledField({
    super.key,
    required this.label,
    required this.child,
    this.hint,
    this.required = false,
  });

  final String label;
  final Widget child;
  final String? hint;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text.rich(
          TextSpan(
            text: label,
            children: <InlineSpan>[
              if (required)
                const TextSpan(text: ' *', style: TextStyle(color: AppTheme.danger)),
            ],
          ),
          style: GoogleFonts.inter(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppTheme.textPrimary),
        ),
        const SizedBox(height: 6),
        child,
        if (hint != null) ...<Widget>[
          const SizedBox(height: 4),
          Text(hint!, style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
        ],
      ],
    );
  }
}

/// TextFormField con etiqueta arriba y formateadores obligatorios.
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.inputFormatters,
    this.validator,
    this.hint,
    this.helper,
    this.required = false,
    this.keyboardType,
    this.obscure = false,
    this.enabled = true,
    this.prefixIcon,
    this.suffix,
    this.maxLines = 1,
    this.textInputAction,
    this.onFieldSubmitted,
    this.onChanged,
    this.autofocus = false,
    this.focusNode,
    this.textAlign = TextAlign.start,
    this.monospace = false,
  });

  final String label;
  final TextEditingController controller;
  final List<TextInputFormatter> inputFormatters;
  final FormFieldValidator<String>? validator;
  final String? hint;
  final String? helper;
  final bool required;
  final TextInputType? keyboardType;
  final bool obscure;
  final bool enabled;
  final IconData? prefixIcon;
  final Widget? suffix;
  final int maxLines;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onFieldSubmitted;
  final ValueChanged<String>? onChanged;
  final bool autofocus;
  final FocusNode? focusNode;
  final TextAlign textAlign;
  final bool monospace;

  @override
  Widget build(BuildContext context) {
    return LabeledField(
      label: label,
      required: required,
      hint: helper,
      child: TextFormField(
        controller: controller,
        focusNode: focusNode,
        autofocus: autofocus,
        inputFormatters: inputFormatters,
        validator: validator,
        keyboardType: keyboardType,
        obscureText: obscure,
        enabled: enabled,
        maxLines: obscure ? 1 : maxLines,
        textAlign: textAlign,
        textInputAction: textInputAction,
        onFieldSubmitted: onFieldSubmitted,
        onChanged: onChanged,
        autovalidateMode: AutovalidateMode.onUserInteraction,
        style: monospace
            ? AppTheme.monoStyle(fontSize: 13.5)
            : GoogleFonts.inter(fontSize: 13.5, color: AppTheme.textPrimary),
        decoration: InputDecoration(
          hintText: hint,
          prefixIcon: prefixIcon == null ? null : Icon(prefixIcon, size: 17),
          prefixIconConstraints: const BoxConstraints(minWidth: 38),
          suffixIcon: suffix,
        ),
      ),
    );
  }
}

/// Estructura estándar de diálogo: cabecera, cuerpo desplazable y pie.
class AppDialog extends StatelessWidget {
  const AppDialog({
    super.key,
    required this.title,
    required this.body,
    this.subtitle,
    this.icon,
    this.actions = const <Widget>[],
    this.width = 520,
    this.footerLeading,
  });

  final String title;
  final String? subtitle;
  final IconData? icon;
  final Widget body;
  final List<Widget> actions;
  final double width;
  final Widget? footerLeading;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: MediaQuery.sizeOf(context).height * 0.9),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 10, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  if (icon != null) ...<Widget>[
                    Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        color: AppTheme.brandSoft,
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Icon(icon, size: 18, color: AppTheme.brand),
                    ),
                    const SizedBox(width: 12),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(title, style: AppTheme.subtitleStyle().copyWith(fontSize: 16)),
                        if (subtitle != null) ...<Widget>[
                          const SizedBox(height: 2),
                          Text(subtitle!, style: AppTheme.bodyStyle(fontSize: 12.5)),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Cerrar',
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                child: body,
              ),
            ),
            if (actions.isNotEmpty || footerLeading != null) ...<Widget>[
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: Row(
                  children: <Widget>[
                    if (footerLeading != null) Expanded(child: footerLeading!) else const Spacer(),
                    ...<Widget>[
                      for (int i = 0; i < actions.length; i++) ...<Widget>[
                        if (i > 0) const SizedBox(width: 8),
                        actions[i],
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Confirmación simple. Devuelve true si el usuario confirma.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'Confirmar',
  bool destructive = false,
}) async {
  final bool? ok = await showDialog<bool>(
    context: context,
    builder: (BuildContext ctx) => AppDialog(
      title: title,
      width: 420,
      icon: destructive ? Icons.warning_amber_rounded : Icons.help_outline_rounded,
      body: Text(message, style: AppTheme.bodyStyle(fontSize: 13.5, height: 1.45)),
      actions: <Widget>[
        OutlinedButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancelar')),
        FilledButton(
          style: destructive ? FilledButton.styleFrom(backgroundColor: AppTheme.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Mensaje flotante con tono.
void showAppToast(BuildContext context, String message, {Tone tone = Tone.neutral, SnackBarAction? action}) {
  final ScaffoldMessengerState? m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  final IconData icon = switch (tone) {
    Tone.success => Icons.check_circle_rounded,
    Tone.danger => Icons.error_rounded,
    Tone.warning => Icons.warning_rounded,
    _ => Icons.info_rounded,
  };
  m.hideCurrentSnackBar();
  m.showSnackBar(
    SnackBar(
      width: MediaQuery.sizeOf(context).width > 700 ? 440 : null,
      action: action,
      content: Row(
        children: <Widget>[
          Icon(icon, size: 18, color: tone == Tone.neutral ? Colors.white70 : tone.solid),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
    ),
  );
}

/// Diálogo para elegir el formato de descarga (PDF, Excel o CSV).
Future<ExportFormat?> showExportFormatPicker(
  BuildContext context, {
  String title = 'Descargar reporte',
  String? subtitle,
  Set<ExportFormat> formats = const <ExportFormat>{ExportFormat.pdf, ExportFormat.xlsx, ExportFormat.csv},
}) {
  return showDialog<ExportFormat>(
    context: context,
    builder: (BuildContext ctx) => AppDialog(
      title: title,
      subtitle: subtitle ?? 'Elige el formato del archivo',
      icon: Icons.download_rounded,
      width: 440,
      body: Column(
        children: <Widget>[
          if (formats.contains(ExportFormat.pdf))
            _FormatTile(
              icon: Icons.picture_as_pdf_rounded,
              color: const Color(0xFFDC2626),
              title: 'PDF',
              description: 'Documento formal listo para imprimir o enviar.',
              onTap: () => Navigator.pop(ctx, ExportFormat.pdf),
            ),
          if (formats.contains(ExportFormat.xlsx))
            _FormatTile(
              icon: Icons.grid_on_rounded,
              color: const Color(0xFF15803D),
              title: 'Excel (.xlsx)',
              description: 'Hoja de cálculo con formato, filtros y totales.',
              onTap: () => Navigator.pop(ctx, ExportFormat.xlsx),
            ),
          if (formats.contains(ExportFormat.csv))
            _FormatTile(
              icon: Icons.description_outlined,
              color: AppTheme.info,
              title: 'CSV',
              description: 'Datos planos para importar en otros sistemas.',
              onTap: () => Navigator.pop(ctx, ExportFormat.csv),
            ),
        ],
      ),
    ),
  );
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: AppTheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(10),
          side: const BorderSide(color: AppTheme.border),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          hoverColor: AppTheme.surfaceMuted,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Icon(icon, color: color, size: 20),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: AppTheme.subtitleStyle()),
                      const SizedBox(height: 2),
                      Text(description, style: AppTheme.bodyStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, color: AppTheme.textMuted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Botón "Descargar" que pide el formato y delega la generación.
///
/// [build] recibe el formato elegido y devuelve los bytes + nombre base del
/// archivo (sin extensión). El botón guarda el archivo y ofrece abrir la
/// carpeta o compartir.
class ExportButton extends StatefulWidget {
  const ExportButton({
    super.key,
    required this.build,
    this.label = 'Descargar',
    this.title = 'Descargar reporte',
    this.subtitle,
    this.formats = const <ExportFormat>{ExportFormat.pdf, ExportFormat.xlsx, ExportFormat.csv},
    this.compact = false,
  });

  final Future<({Uint8List bytes, String baseName})> Function(ExportFormat format) build;
  final String label;
  final String title;
  final String? subtitle;
  final Set<ExportFormat> formats;
  final bool compact;

  @override
  State<ExportButton> createState() => _ExportButtonState();
}

class _ExportButtonState extends State<ExportButton> {
  bool _busy = false;

  Future<void> _run() async {
    final ExportFormat? format = await showExportFormatPicker(
      context,
      title: widget.title,
      subtitle: widget.subtitle,
      formats: widget.formats,
    );
    if (format == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final ({Uint8List bytes, String baseName}) out = await widget.build(format);
      final String name = FileExportService.safeFileName(out.baseName, format);
      if (FileExportService.isDesktop) {
        final SavedFile saved = await FileExportService.save(out.bytes, name);
        if (!mounted) return;
        showAppToast(
          context,
          '${format.label} guardado en Descargas',
          tone: Tone.success,
          action: SnackBarAction(
            label: 'Abrir carpeta',
            textColor: AppTheme.brandMuted,
            onPressed: () => FileExportService.reveal(saved),
          ),
        );
      } else {
        await FileExportService.share(out.bytes, name, mimeType: format.mimeType);
      }
    } catch (e) {
      if (mounted) showAppToast(context, 'No se pudo generar el archivo: $e', tone: Tone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget icon = _busy
        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
        : const Icon(Icons.download_rounded, size: 17);
    if (widget.compact) {
      return IconButton.outlined(
        tooltip: widget.label,
        onPressed: _busy ? null : _run,
        icon: icon,
        style: IconButton.styleFrom(
          side: const BorderSide(color: AppTheme.inputBorder),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppTheme.radiusControl)),
        ),
      );
    }
    return OutlinedButton.icon(
      onPressed: _busy ? null : _run,
      icon: icon,
      label: Text(widget.label),
    );
  }
}

/// Avatar circular con iniciales y color estable según el nombre.
class InitialsAvatar extends StatelessWidget {
  const InitialsAvatar(this.name, {super.key, this.size = 30});
  final String name;
  final double size;

  static const List<Color> _palette = <Color>[
    AppTheme.brand,
    Color(0xFF4F6BED),
    Color(0xFFB45309),
    Color(0xFFBE185D),
    Color(0xFF0E7490),
    Color(0xFF6D28D9),
  ];

  @override
  Widget build(BuildContext context) {
    final List<String> parts =
        name.trim().split(RegExp(r'\s+')).where((String p) => p.isNotEmpty).toList();
    final String initials = parts.isEmpty
        ? '?'
        : parts.length == 1
            ? parts.first.substring(0, parts.first.length >= 2 ? 2 : 1).toUpperCase()
            : '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    final Color c = _palette[name.hashCode.abs() % _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.12), shape: BoxShape.circle),
      child: Text(
        initials,
        style: GoogleFonts.inter(fontSize: size * 0.36, fontWeight: FontWeight.w700, color: c),
      ),
    );
  }
}

/// Encabezado de tabla y celdas compactas para listas tipo hoja de datos.
class DataHeaderCell extends StatelessWidget {
  const DataHeaderCell(this.text, {super.key, this.align = TextAlign.start, this.onTap, this.sortAscending});
  final String text;
  final TextAlign align;
  final VoidCallback? onTap;
  final bool? sortAscending;

  @override
  Widget build(BuildContext context) {
    final Widget label = Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            text.toUpperCase(),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTheme.overlineStyle(color: sortAscending != null ? AppTheme.brand : AppTheme.textMuted),
          ),
        ),
        if (sortAscending != null)
          Icon(
            sortAscending! ? Icons.arrow_upward_rounded : Icons.arrow_downward_rounded,
            size: 12,
            color: AppTheme.brand,
          ),
      ],
    );
    return onTap == null
        ? label
        : InkWell(onTap: onTap, borderRadius: BorderRadius.circular(4), child: label);
  }
}

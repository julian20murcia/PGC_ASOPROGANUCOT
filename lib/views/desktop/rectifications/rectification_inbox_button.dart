import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../controllers/rectification_inbox_controller.dart';
import '../../../core/services/rectification_inbox_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/pro_ui.dart';

/// Campana de la barra superior con las solicitudes de rectificación de datos
/// enviadas por los productores desde la app móvil. Si la app no registra el
/// controlador (por ejemplo en pruebas de widgets) no se muestra.
class RectificationInboxButton extends StatefulWidget {
  const RectificationInboxButton({super.key, required this.user});

  final UserModel user;

  @override
  State<RectificationInboxButton> createState() => _RectificationInboxButtonState();
}

class _RectificationInboxButtonState extends State<RectificationInboxButton> {
  RectificationInboxController? _ctrl;
  StreamSubscription<RectificationRequest>? _arrivalSub;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    RectificationInboxController? ctrl;
    try {
      ctrl = Provider.of<RectificationInboxController>(context, listen: false);
    } on ProviderNotFoundException {
      ctrl = null;
    }
    if (!identical(ctrl, _ctrl)) {
      _arrivalSub?.cancel();
      _ctrl = ctrl;
      _arrivalSub = ctrl?.arrivals.listen(_onArrival);
    }
    ctrl?.bind(widget.user);
  }

  @override
  void didUpdateWidget(covariant RectificationInboxButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.user.uid != widget.user.uid) _ctrl?.bind(widget.user);
  }

  void _onArrival(RectificationRequest r) {
    if (!mounted) return;
    final String who = r.nombreProductor ?? (r.codigoAsociado.isEmpty ? 'Un productor' : r.codigoAsociado);
    showAppToast(
      context,
      'Nueva solicitud de corrección de datos: $who',
      tone: Tone.warning,
      action: SnackBarAction(label: 'Ver', onPressed: () => _open(context)),
    );
  }

  @override
  void dispose() {
    _arrivalSub?.cancel();
    _ctrl?.unbind();
    super.dispose();
  }

  Future<void> _open(BuildContext context) {
    return showDialog<void>(
      context: context,
      builder: (_) => ChangeNotifierProvider<RectificationInboxController>.value(
        value: _ctrl!,
        child: const _RectificationInboxDialog(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final RectificationInboxController? ctrl = _ctrl;
    if (ctrl == null || !RectificationInboxController.canAttend(widget.user)) return const SizedBox.shrink();
    return AnimatedBuilder(
      animation: ctrl,
      builder: (BuildContext context, _) {
        final int n = ctrl.pendingCount;
        return Padding(
          padding: const EdgeInsets.only(left: 8),
          child: Tooltip(
            message: n == 0
                ? 'Solicitudes de corrección de datos'
                : '$n solicitud${n == 1 ? '' : 'es'} de corrección pendiente${n == 1 ? '' : 's'}',
            child: InkWell(
              key: const ValueKey<String>('rectificaciones-campana'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => _open(context),
              child: SizedBox(
                width: 36,
                height: 36,
                child: Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    Icon(
                      n > 0 ? Icons.notifications_active_rounded : Icons.notifications_none_rounded,
                      size: 20,
                      color: n > 0 ? AppTheme.warning : AppTheme.textMuted,
                    ),
                    if (n > 0)
                      Positioned(
                        top: 3,
                        right: 2,
                        child: Container(
                          constraints: const BoxConstraints(minWidth: 16),
                          height: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 4),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppTheme.danger,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: AppTheme.surface, width: 1.5),
                          ),
                          child: Text(
                            n > 99 ? '99+' : '$n',
                            style: GoogleFonts.inter(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _RectificationInboxDialog extends StatefulWidget {
  const _RectificationInboxDialog();

  @override
  State<_RectificationInboxDialog> createState() => _RectificationInboxDialogState();
}

class _RectificationInboxDialogState extends State<_RectificationInboxDialog> {
  bool _showAttended = false;
  final Set<String> _busy = <String>{};

  Future<void> _attend(RectificationInboxController ctrl, RectificationRequest r) async {
    setState(() => _busy.add(r.id));
    final bool ok = await ctrl.markAttended(r);
    if (!mounted) return;
    setState(() => _busy.remove(r.id));
    showAppToast(
      context,
      ok ? 'Solicitud marcada como atendida.' : (ctrl.errorMessage ?? 'No se pudo actualizar la solicitud.'),
      tone: ok ? Tone.success : Tone.danger,
    );
  }

  @override
  Widget build(BuildContext context) {
    final RectificationInboxController ctrl = context.watch<RectificationInboxController>();
    final List<RectificationRequest> list =
        _showAttended ? ctrl.items : ctrl.pending;
    final DateFormat fmt = DateFormat("d 'de' MMM yyyy, h:mm a", 'es');

    return AppDialog(
      title: 'Solicitudes de corrección de datos',
      subtitle: 'Enviadas por los productores desde la app móvil (Ley 1581 de 2012).',
      icon: Icons.fact_check_outlined,
      width: 620,
      footerLeading: Row(
        children: <Widget>[
          Switch(
            value: _showAttended,
            onChanged: (bool v) => setState(() => _showAttended = v),
          ),
          const SizedBox(width: 6),
          Text('Mostrar también las atendidas', style: AppTheme.bodyStyle(fontSize: 12.5)),
        ],
      ),
      actions: <Widget>[
        OutlinedButton(onPressed: () => Navigator.of(context).maybePop(), child: const Text('Cerrar')),
      ],
      body: list.isEmpty
          ? EmptyState(
              icon: Icons.mark_email_read_outlined,
              title: _showAttended ? 'Aún no hay solicitudes' : 'No hay solicitudes pendientes',
              message: 'Cuando un productor pida corregir sus datos desde el celular, la solicitud aparecerá aquí.',
            )
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (ctrl.errorMessage != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: StatusBadge(ctrl.errorMessage!, tone: Tone.danger, icon: Icons.error_outline),
                  ),
                for (final RectificationRequest r in list)
                  Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: r.atendida ? AppTheme.surfaceMuted : AppTheme.surface,
                      borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                      border: Border.all(color: r.atendida ? AppTheme.border : AppTheme.warning.withValues(alpha: 0.45)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                r.nombreProductor ?? 'Productor ${r.codigoAsociado}',
                                style: AppTheme.subtitleStyle().copyWith(fontSize: 14),
                              ),
                            ),
                            StatusBadge(
                              r.atendida ? 'Atendida' : 'Pendiente',
                              tone: r.atendida ? Tone.success : Tone.warning,
                              dot: true,
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${r.codigoAsociado.isEmpty ? '' : '${r.codigoAsociado} · '}${fmt.format(r.fecha.toLocal())}',
                          style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                        ),
                        const SizedBox(height: 8),
                        if (r.campo.isNotEmpty)
                          Text.rich(TextSpan(children: <InlineSpan>[
                            TextSpan(text: 'Dato a corregir: ', style: AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textMuted)),
                            TextSpan(text: r.campo, style: AppTheme.bodyStyle(fontSize: 13).copyWith(fontWeight: FontWeight.w600)),
                          ])),
                        const SizedBox(height: 2),
                        Text(r.detalle, style: AppTheme.bodyStyle(fontSize: 13, height: 1.4)),
                        if (!r.atendida) ...<Widget>[
                          const SizedBox(height: 10),
                          Align(
                            alignment: Alignment.centerRight,
                            child: FilledButton.icon(
                              onPressed: _busy.contains(r.id) ? null : () => _attend(ctrl, r),
                              icon: _busy.contains(r.id)
                                  ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                                  : const Icon(Icons.check_rounded, size: 16),
                              label: const Text('Marcar como atendida'),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: 2),
                Text(
                  'Para aplicar el cambio, edita los datos del productor en el módulo Productores y luego marca la solicitud como atendida.',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted, height: 1.4),
                ),
              ],
            ),
    );
  }
}

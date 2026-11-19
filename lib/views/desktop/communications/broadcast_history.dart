import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/app_notification_model.dart';
import '../../shared/widgets/pro_ui.dart';
import '../../shared/widgets/ui_kit.dart';

enum HistoryFilter { all, general, direct }

/// Historial de comunicados enviados.
class BroadcastHistory extends StatefulWidget {
  const BroadcastHistory({
    super.key,
    required this.items,
    required this.producerNames,
    required this.canDelete,
    required this.onDelete,
  });

  final List<AppNotificationModel> items;
  final Map<String, String> producerNames;
  final bool canDelete;
  final Future<void> Function(AppNotificationModel n) onDelete;

  @override
  State<BroadcastHistory> createState() => _BroadcastHistoryState();
}

class _BroadcastHistoryState extends State<BroadcastHistory> {
  HistoryFilter _filter = HistoryFilter.all;
  String _q = '';
  int _visible = 20;

  String _recipient(AppNotificationModel n) => n.destinoProductorId == null
      ? 'Todos los productores'
      : (widget.producerNames[n.destinoProductorId] ?? 'Productor');

  @override
  Widget build(BuildContext context) {
    final String q = _q.trim().toLowerCase();
    final List<AppNotificationModel> list = widget.items.where((AppNotificationModel n) {
      if (_filter == HistoryFilter.general && n.destinoProductorId != null) return false;
      if (_filter == HistoryFilter.direct && n.destinoProductorId == null) return false;
      if (q.isEmpty) return true;
      return n.titulo.toLowerCase().contains(q) ||
          n.mensaje.toLowerCase().contains(q) ||
          _recipient(n).toLowerCase().contains(q);
    }).toList();
    final List<AppNotificationModel> shown = list.take(_visible).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              AppSegmentedControl<HistoryFilter>(
                selected: _filter,
                onChanged: (HistoryFilter f) => setState(() => _filter = f),
                segments: const <AppSegment<HistoryFilter>>[
                  AppSegment<HistoryFilter>(value: HistoryFilter.all, label: 'Todos'),
                  AppSegment<HistoryFilter>(value: HistoryFilter.general, label: 'Generales'),
                  AppSegment<HistoryFilter>(value: HistoryFilter.direct, label: 'Dirigidos'),
                ],
              ),
              AppSearchField(
                width: 260,
                hint: 'Buscar por título, mensaje o productor…',
                onChanged: (String v) => setState(() => _q = v),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        if (shown.isEmpty)
          EmptyState(
            icon: Icons.campaign_outlined,
            title: widget.items.isEmpty ? 'Aún no se han enviado comunicados' : 'Ningún comunicado coincide',
            message: widget.items.isEmpty
                ? 'Los comunicados que envíes aparecerán aquí con su fecha y destinatario.'
                : 'Prueba con otra búsqueda.',
          )
        else
          for (final AppNotificationModel n in shown)
            _HistoryRow(
              item: n,
              recipient: _recipient(n),
              canDelete: widget.canDelete,
              onDelete: () => widget.onDelete(n),
            ),
        if (list.length > shown.length)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: TextButton(
                onPressed: () => setState(() => _visible += 20),
                child: Text('Ver más (${list.length - shown.length} restantes)'),
              ),
            ),
          ),
      ],
    );
  }
}

class _HistoryRow extends StatefulWidget {
  const _HistoryRow({required this.item, required this.recipient, required this.canDelete, required this.onDelete});
  final AppNotificationModel item;
  final String recipient;
  final bool canDelete;
  final VoidCallback onDelete;

  @override
  State<_HistoryRow> createState() => _HistoryRowState();
}

class _HistoryRowState extends State<_HistoryRow> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final AppNotificationModel n = widget.item;
    final bool general = n.destinoProductorId == null;
    return InkWell(
      onTap: () => setState(() => _open = !_open),
      hoverColor: AppTheme.surfaceMuted,
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 6, 10),
        decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.dividerLight))),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: general ? AppTheme.accentSoft : AppTheme.infoBg,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                general ? Icons.campaign_rounded : Icons.person_pin_outlined,
                size: 16,
                color: general ? AppTheme.accentDeep : AppTheme.infoText,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    n.titulo,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textPrimary, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    n.mensaje,
                    maxLines: _open ? null : 1,
                    overflow: _open ? null : TextOverflow.ellipsis,
                    style: AppTheme.bodyStyle(fontSize: 12.5, height: 1.4),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: <Widget>[
                      StatusBadge(widget.recipient, tone: general ? Tone.accent : Tone.info),
                      if (!general && n.leida) const StatusBadge('Leído', tone: Tone.success, icon: Icons.done_all_rounded),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 120,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(AppFormatters.formatDate(n.fechaEnvio), style: AppTheme.monoStyle(fontSize: 12)),
                  Text(
                    _time(n.fechaEnvio),
                    style: AppTheme.monoStyle(fontSize: 11.5, color: AppTheme.textMuted),
                  ),
                ],
              ),
            ),
            SizedBox(
              width: 40,
              child: widget.canDelete
                  ? IconButton(
                      tooltip: 'Eliminar comunicado',
                      onPressed: widget.onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 18, color: AppTheme.textMuted),
                    )
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  static String _time(DateTime d) {
    final DateTime l = d.toLocal();
    return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
  }
}

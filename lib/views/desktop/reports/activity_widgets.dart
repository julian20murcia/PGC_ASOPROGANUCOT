import 'package:flutter/material.dart';

import '../../../core/services/activity_presenter.dart';
import '../../../core/theme/app_theme.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';

/// Color por tipo de actividad.
extension ActivityKindTone on ActivityKind {
  Tone get tone => switch (this) {
        ActivityKind.login => Tone.info,
        ActivityKind.create => Tone.success,
        ActivityKind.update => Tone.brand,
        ActivityKind.correction => Tone.warning,
        ActivityKind.annul => Tone.danger,
        ActivityKind.settle => Tone.brand,
        ActivityKind.payment => Tone.success,
        ActivityKind.rate => Tone.accent,
        ActivityKind.broadcast => Tone.accent,
        ActivityKind.permissions => Tone.info,
        ActivityKind.account => Tone.warning,
        ActivityKind.rectification => Tone.info,
        ActivityKind.delete => Tone.danger,
        ActivityKind.other => Tone.neutral,
      };
}

const List<String> _weekdays = <String>['lunes', 'martes', 'miércoles', 'jueves', 'viernes', 'sábado', 'domingo'];
const List<String> _monthsLong = <String>[
  'enero', 'febrero', 'marzo', 'abril', 'mayo', 'junio',
  'julio', 'agosto', 'septiembre', 'octubre', 'noviembre', 'diciembre',
];

/// "Hoy", "Ayer" o "Lunes 16 de noviembre de 2026".
String activityDayLabel(DateTime local, {DateTime? now}) {
  final DateTime n = now ?? DateTime.now();
  final DateTime today = DateTime(n.year, n.month, n.day);
  final DateTime day = DateTime(local.year, local.month, local.day);
  final int diff = today.difference(day).inDays;
  if (diff == 0) return 'Hoy';
  if (diff == 1) return 'Ayer';
  final String wd = _weekdays[day.weekday - 1];
  final String text = '$wd ${day.day} de ${_monthsLong[day.month - 1]}${day.year == n.year ? '' : ' de ${day.year}'}';
  return '${text[0].toUpperCase()}${text.substring(1)}';
}

/// "hace 5 min", "hace 3 h", "ayer", "hace 4 días", "12/10/2026" o "Nunca".
String relativeTimeLabel(DateTime? when, {DateTime? now}) {
  if (when == null) return 'Nunca';
  final DateTime n = now ?? DateTime.now();
  final DateTime local = when.toLocal();
  final Duration d = n.difference(local);
  if (d.isNegative || d.inMinutes < 1) return 'Justo ahora';
  if (d.inMinutes < 60) return 'hace ${d.inMinutes} min';
  if (d.inHours < 24) return 'hace ${d.inHours} h';
  final int days = DateTime(n.year, n.month, n.day).difference(DateTime(local.year, local.month, local.day)).inDays;
  if (days == 1) return 'ayer';
  if (days < 7) return 'hace $days días';
  return '${local.day.toString().padLeft(2, '0')}/${local.month.toString().padLeft(2, '0')}/${local.year}';
}

String _hhmm(DateTime d) {
  final DateTime l = d.toLocal();
  return '${l.hour.toString().padLeft(2, '0')}:${l.minute.toString().padLeft(2, '0')}';
}

/// Línea de tiempo agrupada por día.
class ActivityTimeline extends StatelessWidget {
  const ActivityTimeline({
    super.key,
    required this.entries,
    this.showActor = true,
    this.dense = false,
  });

  final List<ActivityEntry> entries;
  final bool showActor;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final List<Widget> children = <Widget>[];
    String? currentDay;
    for (final ActivityEntry e in entries) {
      final DateTime local = e.timestamp.toLocal();
      final String day = activityDayLabel(local);
      if (day != currentDay) {
        currentDay = day;
        final int count = entries.where((ActivityEntry x) => activityDayLabel(x.timestamp.toLocal()) == day).length;
        children.add(_DayHeader(label: day, count: count, first: children.isEmpty));
      }
      children.add(ActivityTile(entry: e, showActor: showActor, dense: dense));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _DayHeader extends StatelessWidget {
  const _DayHeader({required this.label, required this.count, required this.first});
  final String label;
  final int count;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 8),
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        border: Border(
          top: first ? BorderSide.none : const BorderSide(color: AppTheme.border),
          bottom: const BorderSide(color: AppTheme.dividerLight),
        ),
      ),
      child: Row(
        children: <Widget>[
          Text(label.toUpperCase(), style: AppTheme.overlineStyle(color: AppTheme.textSecondary)),
          const SizedBox(width: 8),
          Text('$count ${count == 1 ? 'actividad' : 'actividades'}',
              style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
        ],
      ),
    );
  }
}

/// Fila de actividad con detalle expandible ("antes → después").
class ActivityTile extends StatefulWidget {
  const ActivityTile({super.key, required this.entry, this.showActor = true, this.dense = false});

  final ActivityEntry entry;
  final bool showActor;
  final bool dense;

  @override
  State<ActivityTile> createState() => _ActivityTileState();
}

class _ActivityTileState extends State<ActivityTile> {
  bool _open = false;

  bool get _expandable {
    final ActivityEntry e = widget.entry;
    return e.changes.isNotEmpty || e.related.isNotEmpty || e.motivo != null;
  }

  @override
  Widget build(BuildContext context) {
    final ActivityEntry e = widget.entry;
    final Tone tone = e.kind.tone;
    final Widget icon = Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(color: tone.bg, borderRadius: BorderRadius.circular(8)),
      child: Icon(e.kind.icon, size: 15, color: tone.solid),
    );
    final TextStyle base = AppTheme.bodyStyle(fontSize: 13, color: AppTheme.textPrimary, height: 1.4);
    final Widget sentence = Text.rich(
      TextSpan(
        style: base,
        children: <InlineSpan>[
          if (widget.showActor)
            TextSpan(text: '${e.actorName} ', style: base.copyWith(fontWeight: FontWeight.w600)),
          TextSpan(text: widget.showActor ? e.description : _capitalize(e.description)),
        ],
      ),
      maxLines: _open ? null : 2,
      overflow: _open ? null : TextOverflow.ellipsis,
    );

    return Material(
      color: AppTheme.surface,
      child: InkWell(
        onTap: _expandable ? () => setState(() => _open = !_open) : null,
        hoverColor: AppTheme.surfaceMuted,
        child: Container(
          padding: EdgeInsets.fromLTRB(14, widget.dense ? 8 : 10, 10, widget.dense ? 8 : 10),
          decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: AppTheme.dividerLight))),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              icon,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    sentence,
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: <Widget>[
                        StatusBadge(e.title, tone: tone),
                        Text(e.module.label, style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                        if (e.related.isNotEmpty)
                          Text('· ${e.related.length} registros relacionados',
                              style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textMuted)),
                        if (!_open && e.motivo != null)
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 360),
                            child: Text(
                              '· Motivo: ${e.motivo}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStyle(fontSize: 11.5, color: AppTheme.textSecondary),
                            ),
                          ),
                      ],
                    ),
                    if (_open) ...<Widget>[
                      const SizedBox(height: 8),
                      _ActivityDetail(entry: e),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  Text(_hhmm(e.timestamp), style: AppTheme.monoStyle(fontSize: 12, color: AppTheme.textSecondary)),
                  if (_expandable)
                    Icon(
                      _open ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                      size: 18,
                      color: AppTheme.textMuted,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _capitalize(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';
}

class _ActivityDetail extends StatelessWidget {
  const _ActivityDetail({required this.entry});
  final ActivityEntry entry;

  @override
  Widget build(BuildContext context) {
    final List<ActivityChange> changed = entry.changes.where((ActivityChange c) => c.before != null).toList();
    final List<ActivityChange> created = entry.changes.where((ActivityChange c) => c.before == null).toList();
    final List<String> permDelta = entry.changes.any((ActivityChange c) => c.field == 'permisos')
        ? ActivityPresenter.permissionDelta(entry.log.valorAnterior?['permisos'], entry.log.valorNuevo?['permisos'])
        : const <String>[];

    return Container(
      decoration: BoxDecoration(
        color: AppTheme.surfaceMuted,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.dividerLight),
      ),
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (entry.motivo != null) ...<Widget>[
            _label('Motivo'),
            Text(entry.motivo!, style: AppTheme.bodyStyle(fontSize: 12.5, color: AppTheme.textPrimary)),
            const SizedBox(height: 8),
          ],
          if (changed.isNotEmpty) ...<Widget>[
            _label('Cambios'),
            for (final ActivityChange c in changed) _ChangeRow(change: c),
            const SizedBox(height: 6),
          ],
          if (permDelta.isNotEmpty) ...<Widget>[
            _label('Detalle de permisos'),
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: <Widget>[
                for (final String p in permDelta)
                  StatusBadge(p.substring(2), tone: p.startsWith('+') ? Tone.success : Tone.danger,
                      icon: p.startsWith('+') ? Icons.add_rounded : Icons.remove_rounded),
              ],
            ),
            const SizedBox(height: 8),
          ],
          if (created.isNotEmpty && changed.isEmpty) ...<Widget>[
            _label('Datos registrados'),
            for (final ActivityChange c in created.take(12))
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 150,
                      child: Text(c.label, style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
                    ),
                    Expanded(
                      child: Text(c.after ?? '—', style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textPrimary)),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 6),
          ],
          if (entry.related.isNotEmpty) ...<Widget>[
            _label('Registros relacionados (${entry.related.length})'),
            for (final ActivityEntry r in entry.related.take(8))
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text('• ${_cap(r.description)}',
                    style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textSecondary)),
              ),
            if (entry.related.length > 8)
              Text('… y ${entry.related.length - 8} más',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
            const SizedBox(height: 6),
          ],
          SelectableText(
            'Registro ${entry.log.registroId.isEmpty ? '—' : entry.log.registroId} · '
            '${_fullDate(entry.timestamp.toLocal())}',
            style: AppTheme.monoStyle(fontSize: 11, color: AppTheme.textMuted),
          ),
        ],
      ),
    );
  }

  static String _cap(String s) => s.isEmpty ? s : '${s[0].toUpperCase()}${s.substring(1)}';

  static String _fullDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year} '
      '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}:${d.second.toString().padLeft(2, '0')}';

  static Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Text(t.toUpperCase(), style: AppTheme.overlineStyle()),
      );
}

class _ChangeRow extends StatelessWidget {
  const _ChangeRow({required this.change});
  final ActivityChange change;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            width: 150,
            child: Text(change.label, style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
          ),
          Expanded(
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 6,
              children: <Widget>[
                Text(
                  change.before ?? '—',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.dangerText).copyWith(
                    decoration: TextDecoration.lineThrough,
                    decorationColor: AppTheme.dangerText.withValues(alpha: 0.5),
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded, size: 13, color: AppTheme.textMuted),
                Text(
                  change.after ?? '—',
                  style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.successText, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Valor por defecto para filtros de actividad: últimos 7 días.
DateRangeValue defaultActivityRange() =>
    DateRangeValue(DateTime.now().subtract(const Duration(days: 6)), DateTime.now());

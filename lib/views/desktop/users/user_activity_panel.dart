import 'package:flutter/material.dart';

import '../../../core/constants/app_constants.dart';
import '../../../core/services/activity_presenter.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/pro_ui.dart';
import '../reports/activity_feed.dart';
import '../reports/activity_tab.dart';
import '../reports/activity_widgets.dart';

/// Panel lateral con todo lo que ha hecho un usuario en la plataforma.
Future<void> showUserActivityPanel(BuildContext context, UserModel user) {
  final ActivityFeedController feed = ActivityFeedController(
    service: resolveAuditQueryService(context),
    range: DateRangeValue(DateTime.now().subtract(const Duration(days: 29)), DateTime.now()),
    initialUserUid: user.uid,
    directory: buildActivityDirectory(context),
  );
  feed.reload();
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Cerrar actividad',
    barrierColor: AppTheme.textPrimary.withValues(alpha: 0.18),
    transitionDuration: const Duration(milliseconds: 200),
    pageBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b) => Align(
      alignment: Alignment.centerRight,
      child: _UserActivityPanel(user: user, feed: feed),
    ),
    transitionBuilder: (BuildContext ctx, Animation<double> a, Animation<double> b, Widget child) =>
        SlideTransition(
      position: Tween<Offset>(begin: const Offset(1, 0), end: Offset.zero)
          .animate(CurvedAnimation(parent: a, curve: Curves.easeOutCubic)),
      child: child,
    ),
  ).whenComplete(feed.dispose);
}

class _UserActivityPanel extends StatelessWidget {
  const _UserActivityPanel({required this.user, required this.feed});
  final UserModel user;
  final ActivityFeedController feed;

  @override
  Widget build(BuildContext context) {
    final double width = MediaQuery.sizeOf(context).width.clamp(320.0, 520.0);
    return Material(
      color: AppTheme.surface,
      elevation: 12,
      child: SizedBox(
        width: width,
        height: double.infinity,
        child: AnimatedBuilder(
          animation: feed,
          builder: (BuildContext context, _) {
            final List<ActivityEntry> entries = feed.entries;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 14, 8, 12),
                  child: Row(
                    children: <Widget>[
                      InitialsAvatar(user.nombreCompleto, size: 36),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text(
                              user.nombreCompleto,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.subtitleStyle().copyWith(fontSize: 15),
                            ),
                            Text(
                              '${AppConstants.roleShortLabel(user.rol)} · último acceso ${relativeTimeLabel(user.ultimoAcceso).toLowerCase()}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Cerrar',
                        onPressed: () => Navigator.of(context).maybePop(),
                        icon: const Icon(Icons.close_rounded, size: 18),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
                  child: Row(
                    children: <Widget>[
                      Flexible(
                        child: AppDateRangeField(
                          value: feed.range,
                          dense: true,
                          lastDate: DateTime.now(),
                          onChanged: feed.setRange,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${entries.length}${feed.hasMore ? '+' : ''} actividades',
                        style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(child: _content(entries)),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _content(List<ActivityEntry> entries) {
    if (feed.isLoading && entries.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (feed.error != null && entries.isEmpty) {
      return EmptyState(
        icon: Icons.cloud_off_outlined,
        title: 'No se pudo cargar la actividad',
        message: feed.error,
        action: OutlinedButton(onPressed: feed.reload, child: const Text('Reintentar')),
      );
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.history_toggle_off_rounded,
        title: 'Sin actividad en este período',
        message: 'Prueba con un rango de fechas más amplio.',
        action: feed.hasMore
            ? OutlinedButton(onPressed: feed.loadMore, child: const Text('Buscar más atrás'))
            : null,
      );
    }
    return ListView(
      children: <Widget>[
        ActivityTimeline(entries: entries, showActor: false, dense: true),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: feed.isLoadingMore
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : feed.hasMore
                    ? OutlinedButton(onPressed: feed.loadMore, child: const Text('Cargar más'))
                    : Text('Fin del registro', style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted)),
          ),
        ),
      ],
    );
  }
}

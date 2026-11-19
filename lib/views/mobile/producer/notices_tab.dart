import 'package:flutter/material.dart';

import '../../../controllers/producer_portal_controller.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/app_notification_model.dart';
import 'mobile_kit.dart';

/// Apariencia por tipo de aviso.
({IconData icon, MTone tone, String label}) noticeStyle(String tipo) {
  switch (tipo.toUpperCase()) {
    case 'ENTREGA':
      return (icon: Icons.water_drop_rounded, tone: MTone.brand, label: 'Entrega');
    case 'CIERRE_QUINCENA':
      return (icon: Icons.event_available_rounded, tone: MTone.accent, label: 'Cierre de quincena');
    case 'PAGO':
      return (icon: Icons.payments_rounded, tone: MTone.success, label: 'Pago');
    case 'COMUNICADO':
      return (icon: Icons.campaign_rounded, tone: MTone.info, label: 'Comunicado');
    case 'RECTIFICACION':
      return (icon: Icons.manage_accounts_rounded, tone: MTone.warning, label: 'Solicitud de datos');
    default:
      return (icon: Icons.notifications_rounded, tone: MTone.neutral, label: 'Aviso');
  }
}

/// Pestaña "Avisos": bandeja agrupada con borrado (deslizar) y lectura.
class NoticesTab extends StatelessWidget {
  const NoticesTab({super.key, required this.portal, required this.onRefresh});

  final ProducerPortalController portal;
  final Future<void> Function() onRefresh;

  Future<void> _clearAll(BuildContext context) async {
    final bool ok = await showMobileConfirm(
      context,
      title: '¿Borrar todos los avisos?',
      message: 'Se quitarán todos los avisos de tu bandeja. Esta acción no se puede deshacer.',
      confirmLabel: 'Borrar todos',
      icon: Icons.delete_sweep_rounded,
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final int n = await portal.clearAllNotifications();
    if (!context.mounted) return;
    ScaffoldMessenger.maybeOf(context)
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(n == 1 ? 'Se borró 1 aviso' : 'Se borraron $n avisos')));
  }

  void _remove(BuildContext context, AppNotificationModel n) {
    portal.stageNotificationRemoval(n.notificacionId);
    final ScaffoldMessengerState? messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) {
      portal.commitNotificationRemoval(n.notificacionId);
      return;
    }
    messenger.hideCurrentSnackBar();
    messenger
        .showSnackBar(
          SnackBar(
            content: const Text('Aviso borrado'),
            persist: false,
            duration: const Duration(seconds: 4),
            action: SnackBarAction(
              label: 'Deshacer',
              textColor: AppTheme.accent,
              onPressed: () => portal.undoNotificationRemoval(n.notificacionId),
            ),
          ),
        )
        .closed
        .then((SnackBarClosedReason reason) async {
      if (reason == SnackBarClosedReason.action) return;
      final bool ok = await portal.commitNotificationRemoval(n.notificacionId);
      if (!ok && messenger.mounted) {
        messenger.showSnackBar(
          SnackBar(
            backgroundColor: AppTheme.danger,
            content: Text(portal.errorMessage ?? 'No se pudo borrar el aviso.'),
          ),
        );
      }
    });
  }

  Future<void> _open(BuildContext context, AppNotificationModel n) async {
    if (!n.leida) portal.markNotificationRead(n.notificacionId);
    final ({IconData icon, MTone tone, String label}) st = noticeStyle(n.tipo);
    final bool? delete = await showMobileSheet<bool>(
      context,
      builder: (BuildContext ctx) => SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(20, 16, 20, 20 + MediaQuery.paddingOf(ctx).bottom),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Row(
              children: <Widget>[
                IconChip(st.icon, tone: st.tone, size: 46),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TonePill(st.label, tone: st.tone),
                      const SizedBox(height: 4),
                      Text(
                        AppFormatters.formatDateTime(n.fechaEnvio),
                        style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(n.titulo, style: MobileTokens.title(size: 19)),
            const SizedBox(height: 8),
            SelectableText(n.mensaje, style: MobileTokens.body(size: 15, color: AppTheme.textPrimary, height: 1.5)),
            if (n.destinoProductorId == null) ...<Widget>[
              const SizedBox(height: 12),
              Text(
                'Comunicado general para todos los asociados.',
                style: MobileTokens.body(size: 13.5, color: AppTheme.textMuted),
              ),
            ],
            const SizedBox(height: 20),
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: AppTheme.danger,
                side: const BorderSide(color: AppTheme.dangerBg, width: 1.5),
                minimumSize: const Size.fromHeight(46),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              icon: const Icon(Icons.delete_outline_rounded),
              label: const Text('Borrar aviso'),
            ),
          ],
        ),
      ),
    );
    if (delete == true && context.mounted) _remove(context, n);
  }

  @override
  Widget build(BuildContext context) {
    final List<AppNotificationModel> visible = portal.visibleNotifications;
    final List<NotificationGroup> groups = ProducerPortalController.groupNotifications(visible, now: DateTime.now());
    final int unread = portal.unreadNotificationsCount;
    final int total = portal.allNotifications.length;
    final bool skeleton = portal.isLoading && !portal.hasLoaded;

    return RefreshIndicator(
      color: AppTheme.brand,
      onRefresh: onRefresh,
      child: ListView(
        key: const PageStorageKey<String>('notices-list'),
        padding: EdgeInsets.zero,
        physics: const AlwaysScrollableScrollPhysics(),
        children: <Widget>[
          GradientHeader(
            title: 'Avisos',
            subtitle: unread == 0 ? 'Estás al día' : (unread == 1 ? '1 aviso sin leer' : '$unread avisos sin leer'),
            actions: <Widget>[
              HeaderIconButton(
                key: const ValueKey<String>('notices-mark-all'),
                icon: Icons.done_all_rounded,
                tooltip: 'Marcar todas como leídas',
                onPressed: unread == 0 ? null : portal.markAllRead,
              ),
              HeaderIconButton(
                key: const ValueKey<String>('notices-clear-all'),
                icon: Icons.delete_sweep_rounded,
                tooltip: 'Borrar todas',
                onPressed: total == 0 ? null : () => _clearAll(context),
              ),
            ],
            bottom: Row(
              children: <Widget>[
                _FilterChip(
                  label: 'Todos',
                  count: total,
                  active: !portal.onlyUnreadNotifications,
                  onTap: () => portal.setOnlyUnreadNotifications(false),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'No leídos',
                  count: unread,
                  active: portal.onlyUnreadNotifications,
                  onTap: () => portal.setOnlyUnreadNotifications(true),
                ),
              ],
            ),
          ),
          if (skeleton)
            const TabSkeleton(rows: 5, hero: false)
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(MobileTokens.gutter, 16, MobileTokens.gutter, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (portal.fromCache) ...<Widget>[const OfflineBanner(), const SizedBox(height: 12)],
                  if (visible.isEmpty)
                    SoftCard(
                      child: MobileEmpty(
                        icon: Icons.notifications_none_rounded,
                        title: portal.onlyUnreadNotifications ? 'No tienes avisos sin leer' : 'No tienes avisos',
                        message: 'Aquí verás las entregas registradas, los pagos y los comunicados de la asociación.',
                      ),
                    )
                  else ...<Widget>[
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 8),
                      child: Text(
                        'Desliza un aviso hacia la izquierda para borrarlo.',
                        style: MobileTokens.body(size: 13, color: AppTheme.textMuted),
                      ),
                    ),
                    for (final NotificationGroup g in groups) ...<Widget>[
                      Padding(
                        padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                        child: Text(g.label.toUpperCase(), style: MobileTokens.label(size: 12.5)),
                      ),
                      for (final AppNotificationModel n in g.items)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Dismissible(
                            key: ValueKey<String>('notice-${n.notificacionId}'),
                            direction: DismissDirection.endToStart,
                            onDismissed: (_) => _remove(context, n),
                            background: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 22),
                              decoration: BoxDecoration(
                                color: AppTheme.danger,
                                borderRadius: BorderRadius.circular(MobileTokens.radius),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  Text('Borrar', style: MobileTokens.body(size: 14, color: Colors.white, weight: FontWeight.w700)),
                                  const SizedBox(width: 8),
                                  const Icon(Icons.delete_outline_rounded, color: Colors.white),
                                ],
                              ),
                            ),
                            child: _NoticeTile(
                              notification: n,
                              bucket: g.bucket,
                              onTap: () => _open(context, n),
                            ),
                          ),
                        ),
                    ],
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.count, required this.active, required this.onTap});

  final String label;
  final int count;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: active ? Colors.white : Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          '$label · $count',
          style: MobileTokens.body(
            size: 14,
            color: active ? AppTheme.brandDeep : Colors.white,
            weight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _NoticeTile extends StatelessWidget {
  const _NoticeTile({required this.notification, required this.bucket, required this.onTap});

  final AppNotificationModel notification;
  final NoticeBucket bucket;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final AppNotificationModel n = notification;
    final ({IconData icon, MTone tone, String label}) st = noticeStyle(n.tipo);
    final DateTime local = n.fechaEnvio.toLocal();
    final String time = bucket == NoticeBucket.today || bucket == NoticeBucket.yesterday
        ? '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}'
        : MobileDates.shortDay(local);

    return SoftCard(
      onTap: onTap,
      color: n.leida ? AppTheme.surface : Color.lerp(AppTheme.surface, AppTheme.brandSoft, 0.6)!,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          IconChip(st.icon, tone: st.tone, size: 42),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        n.titulo.isEmpty ? st.label : n.titulo,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: MobileTokens.body(
                          size: 15,
                          color: AppTheme.textPrimary,
                          weight: n.leida ? FontWeight.w600 : FontWeight.w800,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(time, style: MobileTokens.body(size: 12.5, color: AppTheme.textMuted)),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  n.mensaje,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: MobileTokens.body(size: 14, color: AppTheme.textSecondary, height: 1.35),
                ),
              ],
            ),
          ),
          if (!n.leida) ...<Widget>[
            const SizedBox(width: 8),
            Container(
              key: ValueKey<String>('unread-dot-${n.notificacionId}'),
              margin: const EdgeInsets.only(top: 6),
              width: 9,
              height: 9,
              decoration: const BoxDecoration(color: AppTheme.accent, shape: BoxShape.circle),
            ),
          ],
        ],
      ),
    );
  }
}

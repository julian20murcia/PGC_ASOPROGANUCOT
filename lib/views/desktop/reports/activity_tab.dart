import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../controllers/auth_controller.dart';
import '../../../controllers/report_controller.dart';
import '../../../controllers/user_controller.dart';
import '../../../core/security/permissions.dart';
import '../../../core/services/activity_presenter.dart';
import '../../../core/services/audit_query_service.dart';
import '../../../core/services/file_export_service.dart';
import '../../../core/services/report_export_service.dart';
import '../../../core/services/report_service.dart';
import '../../../core/theme/app_theme.dart';
import '../../../models/milk_reception_model.dart';
import '../../../models/producer_model.dart';
import '../../../models/user_model.dart';
import '../../shared/widgets/app_date_range_picker.dart';
import '../../shared/widgets/app_select.dart';
import '../../shared/widgets/pro_ui.dart';
import 'activity_feed.dart';
import 'activity_widgets.dart';

/// Servicio de consultas de auditoría: usa el del árbol de widgets si existe
/// (pruebas) o el de Firestore.
AuditQueryService resolveAuditQueryService(BuildContext context) {
  try {
    return Provider.of<AuditQueryService>(context, listen: false);
  } on ProviderNotFoundException {
    return FirestoreAuditQueryService();
  }
}

/// Construye el directorio de nombres con lo que ya está cargado en memoria.
ActivityDirectory buildActivityDirectory(BuildContext context) {
  Map<String, String> users = const <String, String>{};
  Map<String, String> producers = <String, String>{};
  Map<String, MilkReceptionModel> receptions = const <String, MilkReceptionModel>{};
  try {
    users = context.read<UserController>().userNamesByUid;
  } on ProviderNotFoundException {
    // Sin controlador de usuarios: se muestran identificadores abreviados.
  }
  try {
    final ReportController r = context.read<ReportController>();
    producers = <String, String>{for (final ProducerModel p in r.producers) p.productorId: p.nombreCompleto};
    receptions = <String, MilkReceptionModel>{for (final MilkReceptionModel m in r.allReceptions) m.recepcionId: m};
  } on ProviderNotFoundException {
    // Sin datos de reportes: se usan las instantáneas guardadas en la bitácora.
  }
  return ActivityDirectory(userNames: users, producerNames: producers, receptions: receptions);
}

/// ¿Puede [u] leer la bitácora? (Mismo criterio que `firestore.rules`.)
bool canReadActivity(UserModel? u) =>
    u != null &&
    (u.isAdmin || u.can(Permissions.reportes, PermAction.ver) || u.can(Permissions.usuarios, PermAction.ver));

/// Pestaña "Actividad de usuarios": línea de tiempo legible de la bitácora.
class ActivityTab extends StatefulWidget {
  const ActivityTab({super.key});

  @override
  State<ActivityTab> createState() => _ActivityTabState();
}

class _ActivityTabState extends State<ActivityTab> {
  ActivityFeedController? _feed;
  int _directoryStamp = -1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final UserModel? me = context.read<AuthController>().currentUser;
      if (!canReadActivity(me)) return;
      _feed = ActivityFeedController(
        service: resolveAuditQueryService(context),
        range: defaultActivityRange(),
        directory: buildActivityDirectory(context),
      )..addListener(_onFeed);
      _feed!.reload();
      context.read<UserController>().ensureLoaded();
      setState(() {});
    });
  }

  void _onFeed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed?.removeListener(_onFeed);
    _feed?.dispose();
    super.dispose();
  }

  void _syncDirectory(int stamp) {
    if (_feed == null || stamp == _directoryStamp) return;
    _directoryStamp = stamp;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _feed?.updateDirectory(buildActivityDirectory(context));
    });
  }

  @override
  Widget build(BuildContext context) {
    final UserModel? me = context.watch<AuthController>().currentUser;
    final UserController users = context.watch<UserController>();
    final ReportController reports = context.watch<ReportController>();
    _syncDirectory(Object.hash(users.allUsers.length, reports.producers.length, reports.allReceptions.length));

    if (!canReadActivity(me)) {
      return const Panel(
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Sin acceso a la actividad de usuarios',
          message: 'Pide a un administrador el permiso "Reportes y auditoría · Ver".',
        ),
      );
    }
    final ActivityFeedController? feed = _feed;
    if (feed == null) return const Center(child: Padding(padding: EdgeInsets.all(32), child: CircularProgressIndicator()));

    final List<ActivityEntry> entries = feed.entries;
    final bool canExport = me!.can(Permissions.reportes, PermAction.exportar);
    final List<UserModel> people = List<UserModel>.from(users.allUsers)
      ..sort((UserModel a, UserModel b) => a.nombreCompleto.compareTo(b.nombreCompleto));
    final String? selectedUserName =
        feed.userUid == null ? null : users.findByUid(feed.userUid!)?.nombreCompleto;

    final int actors = entries.map((ActivityEntry e) => e.log.usuarioUid).toSet().length;
    final int sensitive = entries
        .where((ActivityEntry e) =>
            e.kind == ActivityKind.correction || e.kind == ActivityKind.annul || e.kind == ActivityKind.delete)
        .length;
    final int logins = entries.where((ActivityEntry e) => e.kind == ActivityKind.login).length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Panel(
          title: 'Actividad de usuarios',
          subtitle: 'Todo lo que hace cada persona en la plataforma, en orden cronológico.',
          icon: Icons.manage_search_rounded,
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              IconButton(
                tooltip: 'Actualizar',
                onPressed: feed.isLoading ? null : feed.reload,
                icon: const Icon(Icons.refresh_rounded, size: 18),
              ),
              if (canExport)
                ExportButton(
                  title: 'Descargar actividad',
                  subtitle: 'Incluye todas las actividades del rango con los filtros actuales',
                  build: (ExportFormat f) async {
                    final List<ActivityEntry> all = await feed.entriesForExport();
                    final ReportDataset d = ActivityFeedController.toDataset(
                      all,
                      periodLabel: feed.range.label,
                      subtitle: selectedUserName == null ? null : 'Usuario: $selectedUserName',
                    );
                    return (
                      bytes: await ReportExportService.exportDataset(d, f, generatedBy: me.nombreCompleto),
                      baseName: ReportExportService.datasetFileName(d, suffix: selectedUserName),
                    );
                  },
                ),
            ],
          ),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: <Widget>[
              AppDateRangeField(
                value: feed.range,
                dense: true,
                lastDate: DateTime.now(),
                onChanged: feed.setRange,
              ),
              SizedBox(
                width: 230,
                child: AppSelect<String?>(
                  dense: true,
                  value: feed.userUid,
                  prefixIcon: Icons.person_outline_rounded,
                  searchable: true,
                  searchHint: 'Buscar usuario…',
                  options: <AppSelectOption<String?>>[
                    const AppSelectOption<String?>(value: null, label: 'Todos los usuarios'),
                    for (final UserModel u in people)
                      AppSelectOption<String?>(
                        value: u.uid,
                        label: u.nombreCompleto,
                        description: u.correo,
                      ),
                  ],
                  onChanged: feed.setUser,
                ),
              ),
              SizedBox(
                width: 210,
                child: AppSelect<ActivityKind?>(
                  dense: true,
                  value: feed.kind,
                  prefixIcon: Icons.category_outlined,
                  options: <AppSelectOption<ActivityKind?>>[
                    const AppSelectOption<ActivityKind?>(value: null, label: 'Todas las acciones'),
                    for (final ActivityKind k in ActivityKind.values)
                      AppSelectOption<ActivityKind?>(value: k, label: k.label, icon: k.icon),
                  ],
                  onChanged: feed.setKind,
                ),
              ),
              SizedBox(
                width: 200,
                child: AppSelect<ActivityModule?>(
                  dense: true,
                  value: feed.module,
                  prefixIcon: Icons.widgets_outlined,
                  options: <AppSelectOption<ActivityModule?>>[
                    const AppSelectOption<ActivityModule?>(value: null, label: 'Todos los módulos'),
                    for (final ActivityModule m in ActivityModule.values)
                      AppSelectOption<ActivityModule?>(value: m, label: m.label),
                  ],
                  onChanged: feed.setModule,
                ),
              ),
              AppSearchField(
                width: 220,
                hint: 'Buscar en la actividad…',
                initialValue: feed.search,
                onChanged: feed.setSearch,
              ),
              if (feed.hasFilters)
                TextButton.icon(
                  onPressed: feed.clearFilters,
                  icon: const Icon(Icons.filter_alt_off_outlined, size: 16),
                  label: const Text('Limpiar filtros'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        StatStrip(
          items: <StatItem>[
            StatItem(
              label: 'Actividades',
              value: '${entries.length}${feed.hasMore ? '+' : ''}',
              hint: feed.range.label,
              icon: Icons.timeline_rounded,
            ),
            StatItem(label: 'Usuarios con actividad', value: '$actors', icon: Icons.people_outline, tone: Tone.info),
            StatItem(
              label: 'Correcciones y anulaciones',
              value: '$sensitive',
              icon: Icons.edit_note_rounded,
              tone: sensitive > 0 ? Tone.warning : Tone.neutral,
            ),
            StatItem(label: 'Inicios de sesión', value: '$logins', icon: Icons.login_rounded, tone: Tone.accent),
          ],
        ),
        const SizedBox(height: 12),
        Panel(
          padding: EdgeInsets.zero,
          child: _body(feed, entries),
        ),
      ],
    );
  }

  Widget _body(ActivityFeedController feed, List<ActivityEntry> entries) {
    if (feed.isLoading && entries.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator()),
      );
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
        title: 'Sin actividad',
        message: feed.hasFilters
            ? 'No hay actividades que coincidan con los filtros en ${feed.range.label}.'
            : 'No se registró actividad en ${feed.range.label}.',
        action: feed.hasMore
            ? OutlinedButton(onPressed: feed.loadMore, child: const Text('Buscar en registros anteriores'))
            : null,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        ActivityTimeline(entries: entries),
        _LoadMoreFooter(feed: feed),
      ],
    );
  }
}

class _LoadMoreFooter extends StatelessWidget {
  const _LoadMoreFooter({required this.feed});
  final ActivityFeedController feed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Center(
        child: feed.isLoadingMore
            ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
            : feed.hasMore
                ? OutlinedButton.icon(
                    onPressed: feed.loadMore,
                    icon: const Icon(Icons.expand_more_rounded, size: 18),
                    label: const Text('Cargar más actividad'),
                  )
                : Text(
                    'Fin de la actividad del período · ${feed.loadedCount} registros revisados',
                    style: AppTheme.bodyStyle(fontSize: 12, color: AppTheme.textMuted),
                  ),
      ),
    );
  }
}

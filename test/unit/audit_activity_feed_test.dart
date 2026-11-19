import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/constants/app_constants.dart';
import 'package:pgc_asoproganucot/core/services/activity_presenter.dart';
import 'package:pgc_asoproganucot/core/services/audit_query_service.dart';
import 'package:pgc_asoproganucot/core/services/file_export_service.dart';
import 'package:pgc_asoproganucot/core/services/report_export_service.dart';
import 'package:pgc_asoproganucot/core/services/report_service.dart';
import 'package:pgc_asoproganucot/models/audit_log_model.dart';
import 'package:pgc_asoproganucot/views/desktop/reports/activity_feed.dart';
import 'package:pgc_asoproganucot/views/shared/widgets/app_date_range_picker.dart';

AuditLogModel _log(String id, DateTime ts, {String uid = 'u1', String action = 'INICIAR_SESION', String entity = 'usuarios'}) =>
    AuditLogModel(
      logId: id,
      entidadAfectada: entity,
      registroId: uid,
      accion: action,
      usuarioUid: uid,
      timestamp: ts,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuditQueryService', () {
    test('mergeDesc une dos listas ordenadas y cuenta lo consumido', () {
      final DateTime b = DateTime.utc(2026, 11, 10);
      final List<AuditLogModel> a = <AuditLogModel>[
        _log('a1', b.add(const Duration(hours: 5))),
        _log('a2', b.add(const Duration(hours: 3))),
        _log('a3', b.add(const Duration(hours: 1))),
      ];
      final List<AuditLogModel> iso = <AuditLogModel>[
        _log('b1', b.add(const Duration(hours: 4))),
        _log('b2', b.add(const Duration(hours: 2))),
      ];
      final ({List<AuditLogModel> merged, int takenA, int takenB}) m = AuditQueryService.mergeDesc(a, iso, 4);
      expect(m.merged.map((AuditLogModel l) => l.logId), <String>['a1', 'b1', 'a2', 'b2']);
      expect(m.takenA, 2);
      expect(m.takenB, 2);
    });

    test('AuditQuery filtra por usuario y rango (fin exclusivo)', () {
      final AuditQuery q = AuditQuery.forDays(DateTime(2026, 11, 1), DateTime(2026, 11, 2), usuarioUid: 'u1');
      expect(q.matches(_log('x', DateTime(2026, 11, 1, 0, 1))), isTrue);
      expect(q.matches(_log('x', DateTime(2026, 11, 2, 23, 59))), isTrue);
      expect(q.matches(_log('x', DateTime(2026, 11, 3, 0, 0))), isFalse);
      expect(q.matches(_log('x', DateTime(2026, 11, 1, 10), uid: 'u2')), isFalse);
    });

    test('paginación en memoria y fetchAll', () async {
      final DateTime base = DateTime(2026, 11, 10, 12);
      final InMemoryAuditQueryService svc = InMemoryAuditQueryService(<AuditLogModel>[
        for (int i = 0; i < 25; i++) _log('l$i', base.subtract(Duration(minutes: i))),
      ]);
      final AuditQuery q = AuditQuery.forDays(DateTime(2026, 11, 10), DateTime(2026, 11, 10), limit: 10);
      final AuditPage p1 = await svc.fetchPage(q);
      expect(p1.logs.length, 10);
      expect(p1.logs.first.logId, 'l0');
      expect(p1.hasMore, isTrue);
      final AuditPage p3 = await svc.fetchPage(q, cursor: const AuditCursor(offset: 20));
      expect(p3.logs.length, 5);
      expect(p3.hasMore, isFalse);
      expect((await svc.fetchAll(q)).length, 25);
      expect((await svc.fetchAll(q, max: 7)).length, 7);
    });
  });

  group('ActivityFeedController', () {
    final DateTime now = DateTime.now();
    List<AuditLogModel> sample() => <AuditLogModel>[
          for (int i = 0; i < 30; i++) _log('login$i', now.subtract(Duration(minutes: i * 3)), uid: i.isEven ? 'u1' : 'u2'),
          AuditLogModel(
            logId: 'rate',
            entidadAfectada: AppConstants.ratesCollection,
            registroId: 't1',
            accion: 'CREAR',
            valorNuevo: const <String, dynamic>{'precioPorLitro': 1850},
            usuarioUid: 'u1',
            timestamp: now.subtract(const Duration(minutes: 200)),
          ),
        ];

    test('carga, pagina, filtra por tipo/módulo/búsqueda y por usuario', () async {
      final InMemoryAuditQueryService svc = InMemoryAuditQueryService(sample());
      final ActivityFeedController feed = ActivityFeedController(
        service: svc,
        range: DateRangeValue(now.subtract(const Duration(days: 1)), now),
        directory: ActivityDirectory(userNames: <String, String>{'u1': 'Ana Gómez', 'u2': 'Luis Pérez'}),
        pageSize: 10,
      );
      await feed.reload();
      expect(feed.entries.length, 10);
      expect(feed.hasMore, isTrue);
      await feed.loadMore();
      expect(feed.entries.length, 20);

      // El filtro por tipo carga páginas extra hasta encontrar resultados.
      feed.setKind(ActivityKind.rate);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      await pumpEventQueue();
      expect(feed.entries.length, 1);
      expect(feed.entries.single.actorName, 'Ana Gómez');

      feed.clearFilters();
      feed.setSearch('luis');
      expect(feed.entries.every((ActivityEntry e) => e.actorName == 'Luis Pérez'), isTrue);
      feed.clearFilters();

      feed.setModule(ActivityModule.sesion);
      expect(feed.entries.every((ActivityEntry e) => e.module == ActivityModule.sesion), isTrue);
      feed.clearFilters();

      feed.setUser('u2');
      await pumpEventQueue();
      expect(feed.entries.every((ActivityEntry e) => e.log.usuarioUid == 'u2'), isTrue);

      final List<ActivityEntry> all = await feed.entriesForExport();
      expect(all.length, 15);
      feed.dispose();
    });

    test('mensajes de error comprensibles', () {
      expect(ActivityFeedController.describeError(Exception('[cloud_firestore/permission-denied]')), contains('administrador'));
      expect(ActivityFeedController.describeError(Exception('failed-precondition: The query requires an index')), contains('índice'));
      expect(ActivityFeedController.describeError(Exception('boom')), contains('No fue posible'));
    });

    test('exporta la actividad a CSV, Excel y PDF', () async {
      final ActivityPresenter p = ActivityPresenter(ActivityDirectory(userNames: <String, String>{'u1': 'Ana Gómez'}));
      final List<ActivityEntry> entries = p.presentAll(sample().take(3));
      final ReportDataset d = ActivityFeedController.toDataset(entries, periodLabel: '1 – 15 nov 2026');
      expect(d.rows.length, 3);
      expect(d.rows.first[2], 'Ana Gómez');
      final String csv = String.fromCharCodes(await ReportExportService.exportDataset(d, ExportFormat.csv));
      expect(csv, contains('Usuario'));
      final List<int> xlsx = await ReportExportService.exportDataset(d, ExportFormat.xlsx);
      expect(xlsx.sublist(0, 2), <int>[0x50, 0x4B]);
      final List<int> pdf = await ReportExportService.exportDataset(d, ExportFormat.pdf);
      expect(pdf.sublist(0, 4), <int>[0x25, 0x50, 0x44, 0x46]);
    });
  });
}

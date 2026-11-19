import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/constants/app_constants.dart';
import '../core/services/fcm_service.dart';
import '../core/services/hive_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/producer_service.dart';
import '../core/services/rate_service.dart';
import '../core/services/reception_service.dart';
import '../core/services/settlement_service.dart';
import '../models/app_notification_model.dart';
import '../models/milk_rate_model.dart';
import '../models/milk_reception_model.dart';
import '../models/producer_model.dart';
import '../models/settlement_model.dart';
import '../models/user_model.dart';

class ProducerDailySeriesPoint {
  const ProducerDailySeriesPoint({
    required this.isoDate,
    required this.label,
    required this.morningLiters,
    required this.afternoonLiters,
  });

  final String isoDate;
  final String label;
  final double morningLiters;
  final double afternoonLiters;

  double get totalLiters => morningLiters + afternoonLiters;
}

/// Resumen de entregas de un día (jornadas mañana / tarde) para el calendario móvil.
class DayDeliverySummary {
  const DayDeliverySummary({
    required this.isoDate,
    this.receptions = const <MilkReceptionModel>[],
    this.annulled = const <MilkReceptionModel>[],
  });

  final String isoDate;

  /// Entregas válidas (no anuladas) ordenadas por hora.
  final List<MilkReceptionModel> receptions;

  /// Entregas anuladas del día (solo informativas).
  final List<MilkReceptionModel> annulled;

  static bool isAfternoon(MilkReceptionModel r) =>
      r.jornada.trim().toUpperCase() == AppConstants.shiftAfternoon;

  List<MilkReceptionModel> get morning =>
      receptions.where((MilkReceptionModel r) => !isAfternoon(r)).toList();
  List<MilkReceptionModel> get afternoon =>
      receptions.where(isAfternoon).toList();

  double get morningLiters => morning.fold<double>(
        0,
        (double s, MilkReceptionModel r) => s + r.litros,
      );
  double get afternoonLiters => afternoon.fold<double>(
        0,
        (double s, MilkReceptionModel r) => s + r.litros,
      );
  double get totalLiters => morningLiters + afternoonLiters;

  bool get hasMorning =>
      receptions.any((MilkReceptionModel r) => !isAfternoon(r));
  bool get hasAfternoon => receptions.any(isAfternoon);
  bool get hasDeliveries => receptions.isNotEmpty;
  bool get isEmpty => receptions.isEmpty && annulled.isEmpty;
  bool get allSettled =>
      receptions.isNotEmpty &&
      receptions.every((MilkReceptionModel r) => r.isLiquidada);
}

/// Grupo temporal de avisos para la bandeja móvil.
enum NoticeBucket { today, yesterday, thisWeek, older }

class NotificationGroup {
  const NotificationGroup({required this.bucket, required this.items});

  final NoticeBucket bucket;
  final List<AppNotificationModel> items;

  String get label => switch (bucket) {
        NoticeBucket.today => 'Hoy',
        NoticeBucket.yesterday => 'Ayer',
        NoticeBucket.thisWeek => 'Esta semana',
        NoticeBucket.older => 'Anteriores',
      };
}

/// Preferencias locales del portal por usuario (recorrido, avisos ocultos).
abstract class PortalPreferences {
  Future<bool> isTourDone(String uid);
  Future<void> setTourDone(String uid, bool done);
  Future<Set<String>> hiddenNotificationIds(String uid);
  Future<void> saveHiddenNotificationIds(String uid, Set<String> ids);
}

/// Implementación con `shared_preferences`; si el plugin no está disponible
/// (p. ej. pruebas sin mock) degrada a memoria sin lanzar errores.
class SharedPrefsPortalPreferences implements PortalPreferences {
  SharedPrefsPortalPreferences();

  static String tourKey(String uid) => 'tour_done_$uid';
  static String hiddenKey(String uid) => 'hidden_notices_$uid';

  final Map<String, Object> _memory = <String, Object>{};

  Future<SharedPreferences?> _prefs() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<bool> isTourDone(String uid) async {
    if (_memory[tourKey(uid)] == true) return true;
    final SharedPreferences? p = await _prefs();
    if (p == null) return false;
    return p.getBool(tourKey(uid)) ?? false;
  }

  @override
  Future<void> setTourDone(String uid, bool done) async {
    _memory[tourKey(uid)] = done;
    final SharedPreferences? p = await _prefs();
    try {
      await p?.setBool(tourKey(uid), done);
    } catch (_) {}
  }

  @override
  Future<Set<String>> hiddenNotificationIds(String uid) async {
    final SharedPreferences? p = await _prefs();
    if (p == null) {
      final Object? mem = _memory[hiddenKey(uid)];
      return mem is Set<String> ? Set<String>.from(mem) : <String>{};
    }
    return (p.getStringList(hiddenKey(uid)) ?? const <String>[]).toSet();
  }

  @override
  Future<void> saveHiddenNotificationIds(String uid, Set<String> ids) async {
    _memory[hiddenKey(uid)] = Set<String>.from(ids);
    final SharedPreferences? p = await _prefs();
    try {
      await p?.setStringList(hiddenKey(uid), ids.toList());
    } catch (_) {}
  }
}

/// Controlador MVC para el Portal Móvil de Productores (`RF-19` a `RF-24`)
/// y emisor de comunicados institucionales (`RF-24`).
class ProducerPortalController extends ChangeNotifier {
  ProducerPortalController({
    HiveService? hiveService,
    ProducerService? producerService,
    ReceptionService? receptionService,
    RateService? rateService,
    SettlementService? settlementService,
    NotificationService? notificationService,
    FcmService? fcmService,
    PortalPreferences? preferences,
  })  : preferences = preferences ?? SharedPrefsPortalPreferences(),
        _hiveService = hiveService ?? HiveService(),
        _producerService = producerService ?? ProducerService(),
        _receptionService = receptionService ?? ReceptionService(),
        _rateService = rateService ?? RateService(),
        _settlementService = settlementService ?? SettlementService(),
        _notificationService = notificationService ?? NotificationService(),
        _fcmService = fcmService ?? FcmService();

  factory ProducerPortalController.createDefault({
    bool enablePersistence = true,
  }) {
    final HiveService hive = HiveService(enablePersistence: enablePersistence);
    return ProducerPortalController(
      hiveService: hive,
      producerService: ProducerService(hiveService: hive),
      receptionService: ReceptionService(hiveService: hive),
      rateService: RateService(hiveService: hive),
      settlementService: SettlementService(hiveService: hive),
      notificationService: NotificationService(hiveService: hive),
      fcmService: FcmService(),
    );
  }

  final HiveService _hiveService;
  final ProducerService _producerService;
  final ReceptionService _receptionService;
  final RateService _rateService;
  final SettlementService _settlementService;
  final NotificationService _notificationService;
  final FcmService _fcmService;

  /// Preferencias locales por usuario (recorrido de bienvenida, avisos ocultos).
  final PortalPreferences preferences;

  bool isLoading = false;
  bool _hasLoaded = false;
  bool isSubmitting = false;
  bool fromCache = false;
  String? errorMessage;
  String? feedbackMessage;

  UserModel? activeUser;
  ProducerModel? activeProducer;
  MilkRateModel? activeRate;
  DateTime _refDate = DateTime.now();

  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
  List<MilkReceptionModel> _annulledReceptions = <MilkReceptionModel>[];
  Set<String> _hiddenNotificationIds = <String>{};
  final Map<String, AppNotificationModel> _pendingRemovals =
      <String, AppNotificationModel>{};
  List<SettlementModel> _settlements = <SettlementModel>[];
  List<AppNotificationModel> _notifications = <AppNotificationModel>[];
  List<AppNotificationModel> _adminNotifications = <AppNotificationModel>[];

  String _periodFilter = 'QUINCENA'; // QUINCENA | MES | FECHA | TODAS
  String _shiftFilter = 'ALL'; // ALL | MANANA | TARDE
  DateTime? _selectedDateFilter;
  bool _onlyUnreadNotifications = false;

  StreamSubscription<AppNotificationModel>? _fcmSub;
  String? _loadedUid;

  bool get isPortalLoadedForCurrentUser =>
      activeUser != null && _loadedUid == activeUser!.uid;

  /// `true` cuando ya terminó al menos una carga (evita esqueletos al refrescar).
  bool get hasLoaded => _hasLoaded;

  /// Fecha de referencia del portal (hoy, salvo en pruebas).
  DateTime get referenceDate => _refDate;

  void clearFeedback() {
    errorMessage = null;
    feedbackMessage = null;
    notifyListeners();
  }

  /// Carga toda la información del portal del productor con aislamiento estricto por UID (`Paso 7.1`).
  Future<void> loadPortalForUser(
    UserModel user, {
    DateTime? referenceDate,
  }) async {
    isLoading = true;
    errorMessage = null;
    activeUser = user;
    _loadedUid = user.uid;
    _refDate = (referenceDate ?? DateTime.now()).toLocal();
    notifyListeners();

    try {
      try {
        _hiddenNotificationIds =
            await preferences.hiddenNotificationIds(user.uid);
      } catch (_) {
        _hiddenNotificationIds = <String>{};
      }
      ProducerModel? resolvedProducer =
          await _producerService.findProducerForUser(user);

      // Doble verificación de aislamiento estricto por UID / documento.
      if (resolvedProducer != null && user.isProductor) {
        final String? linkedUid = resolvedProducer.uidUsuario?.trim();
        final bool uidMatches = linkedUid != null && linkedUid == user.uid.trim();
        final bool docFallbackMatches = (linkedUid == null || linkedUid.isEmpty) &&
            user.documento.trim().isNotEmpty &&
            resolvedProducer.cedula.trim() == user.documento.trim();
        if (!uidMatches && !docFallbackMatches) {
          resolvedProducer = null;
        }
      }
      activeProducer = resolvedProducer;

      try {
        activeRate = await _rateService.getActiveRate(atDate: _refDate);
      } catch (_) {
        activeRate = await _hiveService.getActiveMilkRate(atDate: _refDate);
      }

      if (resolvedProducer == null) {
        _receptions = <MilkReceptionModel>[];
        _annulledReceptions = <MilkReceptionModel>[];
        _settlements = <SettlementModel>[];
        final notifRes = await _notificationService.listForProducer(
          productorId: user.uid,
          userUid: user.uid,
        );
        _notifications = _withoutHidden(notifRes.notifications);
        fromCache = notifRes.fromCache;
      } else {
        final String prodId = resolvedProducer.productorId;
        final recFuture = _receptionService.listForProducer(prodId);
        final setFuture = _settlementService.listForProducer(prodId);
        final notifFuture = _notificationService.listForProducer(
          productorId: prodId,
          userUid: user.uid,
        );

        final recRes = await recFuture;
        final setRes = await setFuture;
        final notifRes = await notifFuture;

        _receptions = _filterAndSortReceptions(recRes.receptions, prodId);
        _annulledReceptions = _annulledFor(recRes.receptions, prodId);
        _settlements = _filterAndSortSettlements(setRes.settlements, prodId);

        _notifications = _withoutHidden(notifRes.notifications);
        fromCache = recRes.fromCache || setRes.fromCache || notifRes.fromCache;

        await _fcmSub?.cancel();
        _fcmSub = _fcmService.foregroundNotifications.listen(_handleIncomingFcm);
        await _fcmService.initializeForProducer(
          onRefreshRequested: () => _refreshLiveProducerData(
            userUid: user.uid,
            prodId: prodId,
          ),
        );
      }
    } catch (e) {
      errorMessage = 'No se pudo cargar la información del portal: $e';
    } finally {
      isLoading = false;
      _hasLoaded = true;
      notifyListeners();
    }
  }

  List<MilkReceptionModel> _filterAndSortReceptions(
    List<MilkReceptionModel> items,
    String prodId,
  ) {
    return items
        .where(
          (MilkReceptionModel r) => r.productorId == prodId && !r.anulado,
        )
        .toList()
      ..sort((MilkReceptionModel a, MilkReceptionModel b) {
        final int dateCmp = b.fechaEntrega.compareTo(a.fechaEntrega);
        return dateCmp != 0
            ? dateCmp
            : b.horaEntrega.compareTo(a.horaEntrega);
      });
  }

  List<AppNotificationModel> _withoutHidden(List<AppNotificationModel> list) {
    return list
        .where(
          (AppNotificationModel n) =>
              !_hiddenNotificationIds.contains(n.notificacionId) &&
              !_pendingRemovals.containsKey(n.notificacionId),
        )
        .toList();
  }

  List<MilkReceptionModel> _annulledFor(List<MilkReceptionModel> items, String prodId) =>
      items.where((MilkReceptionModel r) => r.productorId == prodId && r.anulado).toList();

  List<SettlementModel> _filterAndSortSettlements(
    List<SettlementModel> items,
    String prodId,
  ) {
    return items
        .where((SettlementModel s) => s.productorId == prodId)
        .toList()
      ..sort(
        (SettlementModel a, SettlementModel b) =>
            b.fechaLiquidacion.compareTo(a.fechaLiquidacion),
      );
  }

  Future<void> _refreshLiveProducerData({
    required String userUid,
    required String prodId,
  }) async {
    try {
      final recFuture = _receptionService.listForProducer(prodId);
      final setFuture = _settlementService.listForProducer(prodId);
      final notifFuture = _notificationService.listForProducer(
        productorId: prodId,
        userUid: userUid,
      );

      final recRes = await recFuture;
      final setRes = await setFuture;
      final notifRes = await notifFuture;
      if (activeUser?.uid != userUid ||
          activeProducer?.productorId != prodId) {
        return;
      }

      _receptions = _filterAndSortReceptions(recRes.receptions, prodId);
      _annulledReceptions = _annulledFor(recRes.receptions, prodId);
      _settlements = _filterAndSortSettlements(setRes.settlements, prodId);
      _notifications = _withoutHidden(notifRes.notifications);
      notifyListeners();
    } catch (_) {
      // Fallo silencioso al refrescar tras push en primer plano.
    }
  }

  void _handleIncomingFcm(AppNotificationModel incoming) {
    final ProducerModel? prod = activeProducer;
    final String? dest = incoming.destinoProductorId?.trim();
    if (dest != null &&
        dest.isNotEmpty &&
        dest != prod?.productorId &&
        dest != activeUser?.uid) {
      return;
    }
    if (_hiddenNotificationIds.contains(incoming.notificacionId) ||
        _pendingRemovals.containsKey(incoming.notificacionId)) {
      return;
    }

    final int idx = _notifications.indexWhere(
      (AppNotificationModel n) => n.notificacionId == incoming.notificacionId,
    );
    if (idx >= 0) {
      _notifications[idx] = incoming;
    } else {
      _notifications = <AppNotificationModel>[incoming, ..._notifications];
    }
    unawaited(_hiveService.upsertNotification(incoming));
    notifyListeners();
  }

  // ---- Pestaña 1: Resumen (`RF-20`, `RNF-02`) ----

  double get activePricePerLiter => activeRate?.precioPorLitro ?? 0;

  ({String start, String end, String label}) get currentQuincena =>
      ReceptionService.currentQuincenaRange(_refDate);

  List<MilkReceptionModel> get quincenaReceptions {
    final q = currentQuincena;
    return _receptions.where((MilkReceptionModel r) {
      return r.fechaEntrega.compareTo(q.start) >= 0 &&
          r.fechaEntrega.compareTo(q.end) <= 0;
    }).toList();
  }

  double get quincenaLiters => quincenaReceptions.fold<double>(
        0.0,
        (double sum, MilkReceptionModel r) => sum + r.litros,
      );

  int get quincenaDeliveriesCount => quincenaReceptions.length;

  double get quincenaEstimatedAmount =>
      ((quincenaLiters * activePricePerLiter) * 100).roundToDouble() / 100;

  String get currentMonthPrefix {
    final String month = _refDate.month.toString().padLeft(2, '0');
    return '${_refDate.year}-$month-';
  }

  List<MilkReceptionModel> get monthReceptions {
    final String prefix = currentMonthPrefix;
    return _receptions
        .where((MilkReceptionModel r) => r.fechaEntrega.startsWith(prefix))
        .toList();
  }

  double get monthLiters => monthReceptions.fold<double>(
        0.0,
        (double sum, MilkReceptionModel r) => sum + r.litros,
      );

  int get monthDeliveriesCount => monthReceptions.length;

  double get averageDailyLiters {
    final Set<String> activeDays =
        monthReceptions.map((MilkReceptionModel r) => r.fechaEntrega).toSet();
    if (activeDays.isEmpty) return 0;
    return monthLiters / activeDays.length;
  }

  SettlementModel? get latestSettlement =>
      _settlements.isEmpty ? null : _settlements.first;

  List<ProducerDailySeriesPoint> get last7DaysSeries {
    final List<ProducerDailySeriesPoint> points = <ProducerDailySeriesPoint>[];
    final DateTime anchor =
        DateTime(_refDate.year, _refDate.month, _refDate.day);

    for (int offset = 6; offset >= 0; offset--) {
      final DateTime day = anchor.subtract(Duration(days: offset));
      final String iso = ReceptionService.formatDate(day);
      double morning = 0;
      double afternoon = 0;
      for (final MilkReceptionModel r in _receptions) {
        if (r.fechaEntrega != iso) continue;
        if (r.jornada == AppConstants.shiftAfternoon) {
          afternoon += r.litros;
        } else {
          morning += r.litros;
        }
      }
      final String label =
          '${day.day.toString().padLeft(2, '0')}/${day.month.toString().padLeft(2, '0')}';
      points.add(
        ProducerDailySeriesPoint(
          isoDate: iso,
          label: label,
          morningLiters: morning,
          afternoonLiters: afternoon,
        ),
      );
    }
    return points;
  }

  /// Serie diaria de los últimos [days] días (incluye hoy).
  List<ProducerDailySeriesPoint> lastDaysSeries(int days) {
    final int n = days.clamp(1, 366);
    final Map<String, DayDeliverySummary> byDay = daySummaries;
    final DateTime anchor =
        DateTime(_refDate.year, _refDate.month, _refDate.day);
    final List<ProducerDailySeriesPoint> points = <ProducerDailySeriesPoint>[];
    for (int offset = n - 1; offset >= 0; offset--) {
      final DateTime day =
          DateTime(anchor.year, anchor.month, anchor.day - offset);
      final String iso = ReceptionService.formatDate(day);
      final DayDeliverySummary? sum = byDay[iso];
      points.add(
        ProducerDailySeriesPoint(
          isoDate: iso,
          label: '${day.day.toString().padLeft(2, '0')}/'
              '${day.month.toString().padLeft(2, '0')}',
          morningLiters: sum?.morningLiters ?? 0,
          afternoonLiters: sum?.afternoonLiters ?? 0,
        ),
      );
    }
    return points;
  }

  static DateTime _parseIso(String iso) {
    final List<String> p = iso.split('-');
    return DateTime(int.parse(p[0]), int.parse(p[1]), int.parse(p[2]));
  }

  /// Rango de la quincena inmediatamente anterior a la actual.
  ({String start, String end, String label}) get previousQuincena {
    final DateTime start = _parseIso(currentQuincena.start);
    return ReceptionService.currentQuincenaRange(
      DateTime(start.year, start.month, start.day - 1),
    );
  }

  double _litersBetween(String start, String end) => _receptions
      .where(
        (MilkReceptionModel r) =>
            r.fechaEntrega.compareTo(start) >= 0 &&
            r.fechaEntrega.compareTo(end) <= 0,
      )
      .fold<double>(0, (double s, MilkReceptionModel r) => s + r.litros);

  double get previousQuincenaLiters {
    final q = previousQuincena;
    return _litersBetween(q.start, q.end);
  }

  /// Variación porcentual frente a la quincena anterior al mismo número de
  /// días transcurridos (comparación justa). `null` sin base de comparación.
  double? get quincenaDeltaPercent {
    final q = previousQuincena;
    final DateTime prevStart = _parseIso(q.start);
    final DateTime cutoff = DateTime(
      prevStart.year,
      prevStart.month,
      prevStart.day + quincenaElapsedDays - 1,
    );
    String end = ReceptionService.formatDate(cutoff);
    if (end.compareTo(q.end) > 0) end = q.end;
    final double base = _litersBetween(q.start, end);
    if (base <= 0) return null;
    return ((quincenaLiters - base) / base) * 100;
  }

  /// Días transcurridos de la quincena actual (incluye hoy).
  int get quincenaElapsedDays =>
      _refDate.day <= 15 ? _refDate.day : _refDate.day - 15;

  /// Días totales de la quincena actual.
  int get quincenaTotalDays =>
      _parseIso(currentQuincena.end).day -
      _parseIso(currentQuincena.start).day +
      1;

  /// Días que faltan para el cierre de la quincena actual.
  int get daysToQuincenaClose =>
      (quincenaTotalDays - quincenaElapsedDays).clamp(0, 31);

  double get quincenaMorningLiters => quincenaReceptions
      .where((MilkReceptionModel r) => !DayDeliverySummary.isAfternoon(r))
      .fold<double>(0, (double s, MilkReceptionModel r) => s + r.litros);

  double get quincenaAfternoonLiters => quincenaReceptions
      .where(DayDeliverySummary.isAfternoon)
      .fold<double>(0, (double s, MilkReceptionModel r) => s + r.litros);

  /// Promedio diario de la quincena (sobre días con entrega).
  double get quincenaAverageDailyLiters {
    final Set<String> days = quincenaReceptions
        .map((MilkReceptionModel r) => r.fechaEntrega)
        .toSet();
    if (days.isEmpty) return 0;
    return quincenaLiters / days.length;
  }

  /// Racha de días consecutivos con entrega, terminando hoy (o ayer si hoy
  /// aún no hay registro).
  int get deliveryStreakDays => computeStreak(
        _receptions.map((MilkReceptionModel r) => r.fechaEntrega).toSet(),
        _refDate,
      );

  static int computeStreak(Set<String> activeIsoDays, DateTime today) {
    DateTime cursor = DateTime(today.year, today.month, today.day);
    if (!activeIsoDays.contains(ReceptionService.formatDate(cursor))) {
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    int streak = 0;
    while (activeIsoDays.contains(ReceptionService.formatDate(cursor)) &&
        streak < 3660) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  /// Mejor día (más litros) de los últimos 30 días.
  ({String isoDate, double liters})? get bestDayLast30 {
    ({String isoDate, double liters})? best;
    for (final ProducerDailySeriesPoint p in lastDaysSeries(30)) {
      if (p.totalLiters <= 0) continue;
      if (best == null || p.totalLiters > best.liters) {
        best = (isoDate: p.isoDate, liters: p.totalLiters);
      }
    }
    return best;
  }

  // ---- Calendario de entregas ----

  /// Resumen por día (`YYYY-MM-DD`) de todas las entregas del productor.
  Map<String, DayDeliverySummary> get daySummaries =>
      buildDaySummaries(_receptions, annulled: _annulledReceptions);

  /// Agrupa entregas por día; las anuladas se listan aparte.
  static Map<String, DayDeliverySummary> buildDaySummaries(
    Iterable<MilkReceptionModel> receptions, {
    Iterable<MilkReceptionModel> annulled = const <MilkReceptionModel>[],
  }) {
    final Map<String, List<MilkReceptionModel>> valid =
        <String, List<MilkReceptionModel>>{};
    final Map<String, List<MilkReceptionModel>> nulls =
        <String, List<MilkReceptionModel>>{};
    for (final MilkReceptionModel r in receptions) {
      (r.anulado ? nulls : valid)
          .putIfAbsent(r.fechaEntrega, () => <MilkReceptionModel>[])
          .add(r);
    }
    for (final MilkReceptionModel r in annulled) {
      nulls.putIfAbsent(r.fechaEntrega, () => <MilkReceptionModel>[]).add(r);
    }
    int byTime(MilkReceptionModel a, MilkReceptionModel b) =>
        a.horaEntrega.compareTo(b.horaEntrega);
    final Set<String> days = <String>{...valid.keys, ...nulls.keys};
    return <String, DayDeliverySummary>{
      for (final String d in days)
        d: DayDeliverySummary(
          isoDate: d,
          receptions: (valid[d] ?? <MilkReceptionModel>[])..sort(byTime),
          annulled: (nulls[d] ?? <MilkReceptionModel>[])..sort(byTime),
        ),
    };
  }

  /// Fecha (`YYYY-MM-DD`) de la entrega más antigua registrada.
  String? get earliestDeliveryDate {
    String? min;
    for (final MilkReceptionModel r in _receptions) {
      if (min == null || r.fechaEntrega.compareTo(min) < 0) {
        min = r.fechaEntrega;
      }
    }
    return min;
  }

  /// Liquidación a la que pertenece una entrega (si existe).
  SettlementModel? settlementForReception(MilkReceptionModel r) {
    final String? id = r.liquidacionId?.trim();
    if (id == null || id.isEmpty) return null;
    for (final SettlementModel s in _settlements) {
      if (s.liquidacionId == id) return s;
    }
    return null;
  }

  /// Precio por litro aplicable: el de la liquidación o la tarifa vigente.
  double priceForReception(MilkReceptionModel r) {
    final SettlementModel? s = settlementForReception(r);
    if (s != null && s.precioLitroAplicado > 0) return s.precioLitroAplicado;
    return activePricePerLiter;
  }

  // ---- Pestaña 2: Mis Entregas (`RF-21`, `HU-11`) ----

  String get periodFilter => _periodFilter;
  String get shiftFilter => _shiftFilter;
  DateTime? get selectedDateFilter => _selectedDateFilter;

  void setPeriodFilter(String value) {
    _periodFilter = value;
    if (value != 'FECHA') {
      _selectedDateFilter = null;
    }
    notifyListeners();
  }

  void setShiftFilter(String value) {
    _shiftFilter = value;
    notifyListeners();
  }

  void setSelectedDateFilter(DateTime? date) {
    _selectedDateFilter = date;
    _periodFilter = date != null ? 'FECHA' : 'QUINCENA';
    notifyListeners();
  }

  void clearDeliveryFilters() {
    _periodFilter = 'QUINCENA';
    _shiftFilter = 'ALL';
    _selectedDateFilter = null;
    notifyListeners();
  }

  List<MilkReceptionModel> get allReceptions =>
      List<MilkReceptionModel>.unmodifiable(_receptions);

  List<MilkReceptionModel> get filteredReceptions {
    final q = currentQuincena;
    final String monthPrefix = currentMonthPrefix;
    final String? dateIso = _selectedDateFilter != null
        ? ReceptionService.formatDate(_selectedDateFilter!)
        : null;

    return _receptions.where((MilkReceptionModel r) {
      if (_shiftFilter != 'ALL' && r.jornada != _shiftFilter) {
        return false;
      }
      switch (_periodFilter) {
        case 'QUINCENA':
          return r.fechaEntrega.compareTo(q.start) >= 0 &&
              r.fechaEntrega.compareTo(q.end) <= 0;
        case 'MES':
          return r.fechaEntrega.startsWith(monthPrefix);
        case 'FECHA':
          return dateIso == null || r.fechaEntrega == dateIso;
        case 'TODAS':
        default:
          return true;
      }
    }).toList();
  }

  double get filteredTotalLiters => filteredReceptions.fold<double>(
        0.0,
        (double sum, MilkReceptionModel r) => sum + r.litros,
      );

  // ---- Pestaña 3: Liquidaciones y Avisos (`RF-22`, `RF-24`) ----

  List<SettlementModel> get settlements =>
      List<SettlementModel>.unmodifiable(_settlements);

  List<MilkReceptionModel> receptionsForSettlement(SettlementModel settlement) {
    final List<MilkReceptionModel> direct = _receptions
        .where(
          (MilkReceptionModel r) =>
              r.liquidacionId == settlement.liquidacionId,
        )
        .toList();
    if (direct.isNotEmpty) {
      direct.sort((MilkReceptionModel a, MilkReceptionModel b) {
        final int cmp = a.fechaEntrega.compareTo(b.fechaEntrega);
        return cmp != 0 ? cmp : a.horaEntrega.compareTo(b.horaEntrega);
      });
      return direct;
    }

    final List<MilkReceptionModel> byRange = _receptions
        .where(
          (MilkReceptionModel r) =>
              r.productorId == settlement.productorId &&
              r.fechaEntrega.compareTo(settlement.periodoInicio) >= 0 &&
              r.fechaEntrega.compareTo(settlement.periodoFin) <= 0,
        )
        .toList()
      ..sort((MilkReceptionModel a, MilkReceptionModel b) {
        final int cmp = a.fechaEntrega.compareTo(b.fechaEntrega);
        return cmp != 0 ? cmp : a.horaEntrega.compareTo(b.horaEntrega);
      });
    return byRange;
  }

  List<AppNotificationModel> get allNotifications =>
      List<AppNotificationModel>.unmodifiable(_notifications);

  bool get onlyUnreadNotifications => _onlyUnreadNotifications;

  int get unreadNotificationsCount =>
      _notifications.where((AppNotificationModel n) => !n.leida).length;

  List<AppNotificationModel> get visibleNotifications {
    if (_onlyUnreadNotifications) {
      return _notifications
          .where((AppNotificationModel n) => !n.leida)
          .toList();
    }
    return allNotifications;
  }

  void setOnlyUnreadNotifications(bool value) {
    _onlyUnreadNotifications = value;
    notifyListeners();
  }

  Future<void> markNotificationRead(String notificacionId) async {
    bool changed = false;
    final List<AppNotificationModel> next =
        _notifications.map((AppNotificationModel n) {
      if (n.notificacionId == notificacionId && !n.leida) {
        changed = true;
        return n.copyWith(leida: true);
      }
      return n;
    }).toList();
    if (changed) {
      _notifications = next;
      notifyListeners();
    }
    await _notificationService.markAsRead(notificacionId);
  }

  Future<void> markAllRead() async {
    final List<String> unreadIds = _notifications
        .where((AppNotificationModel n) => !n.leida)
        .map((AppNotificationModel n) => n.notificacionId)
        .toList();
    if (unreadIds.isEmpty) return;

    _notifications = _notifications
        .map((AppNotificationModel n) => n.copyWith(leida: true))
        .toList();
    notifyListeners();
    await _notificationService.markAllAsRead(unreadIds);
  }

  /// Agrupa avisos en Hoy / Ayer / Esta semana / Anteriores (hora local).
  static List<NotificationGroup> groupNotifications(
    List<AppNotificationModel> items, {
    required DateTime now,
  }) {
    final DateTime today = DateTime(now.year, now.month, now.day);
    final Map<NoticeBucket, List<AppNotificationModel>> map =
        <NoticeBucket, List<AppNotificationModel>>{};
    final List<AppNotificationModel> sorted =
        List<AppNotificationModel>.from(items)
          ..sort(
            (AppNotificationModel a, AppNotificationModel b) =>
                b.fechaEnvio.compareTo(a.fechaEnvio),
          );
    for (final AppNotificationModel n in sorted) {
      final DateTime l = n.fechaEnvio.toLocal();
      final int diff =
          today.difference(DateTime(l.year, l.month, l.day)).inDays;
      final NoticeBucket bucket = diff <= 0
          ? NoticeBucket.today
          : diff == 1
              ? NoticeBucket.yesterday
              : diff < 7
                  ? NoticeBucket.thisWeek
                  : NoticeBucket.older;
      map.putIfAbsent(bucket, () => <AppNotificationModel>[]).add(n);
    }
    return <NotificationGroup>[
      for (final NoticeBucket b in NoticeBucket.values)
        if (map[b] != null) NotificationGroup(bucket: b, items: map[b]!),
    ];
  }

  /// Los avisos personales del productor se borran en la nube; los
  /// comunicados generales y las solicitudes de rectificación solo se ocultan
  /// localmente (la solicitud Habeas Data debe seguir visible para el Admin).
  static bool isRemotelyDeletable(AppNotificationModel n) =>
      n.destinoProductorId != null &&
      n.destinoProductorId!.trim().isNotEmpty &&
      n.tipo.toUpperCase() != 'RECTIFICACION';

  static int _byDateDesc(AppNotificationModel a, AppNotificationModel b) =>
      b.fechaEnvio.compareTo(a.fechaEnvio);

  /// Retira un aviso de la bandeja de forma provisional (permite deshacer).
  void stageNotificationRemoval(String notificacionId) {
    final int idx = _notifications.indexWhere(
      (AppNotificationModel n) => n.notificacionId == notificacionId,
    );
    if (idx < 0) return;
    _pendingRemovals[notificacionId] = _notifications[idx];
    _notifications = List<AppNotificationModel>.from(_notifications)
      ..removeAt(idx);
    notifyListeners();
  }

  /// Revierte un retiro provisional.
  void undoNotificationRemoval(String notificacionId) {
    final AppNotificationModel? n = _pendingRemovals.remove(notificacionId);
    if (n == null) return;
    _notifications = <AppNotificationModel>[..._notifications, n]
      ..sort(_byDateDesc);
    notifyListeners();
  }

  /// Confirma el borrado de un aviso retirado provisionalmente.
  Future<bool> commitNotificationRemoval(String notificacionId) async {
    final AppNotificationModel? n = _pendingRemovals[notificacionId];
    if (n == null) return false;
    final bool ok = await _removeNotification(n);
    _pendingRemovals.remove(notificacionId);
    if (!ok) {
      _notifications = <AppNotificationModel>[..._notifications, n]
        ..sort(_byDateDesc);
    }
    notifyListeners();
    return ok;
  }

  /// Borra un aviso de inmediato (sin opción de deshacer).
  Future<bool> deleteNotification(String notificacionId) async {
    stageNotificationRemoval(notificacionId);
    return commitNotificationRemoval(notificacionId);
  }

  /// Borra todos los avisos visibles. Devuelve cuántos se retiraron.
  Future<int> clearAllNotifications() async {
    final List<AppNotificationModel> all =
        List<AppNotificationModel>.from(_notifications);
    if (all.isEmpty) return 0;
    _notifications = <AppNotificationModel>[];
    notifyListeners();
    final List<AppNotificationModel> failed = <AppNotificationModel>[];
    for (final AppNotificationModel n in all) {
      if (!await _removeNotification(n)) failed.add(n);
    }
    if (failed.isNotEmpty) {
      _notifications = <AppNotificationModel>[...failed, ..._notifications]
        ..sort(_byDateDesc);
      errorMessage =
          'Algunos avisos no se pudieron borrar. Verifica tu conexión.';
    }
    notifyListeners();
    return all.length - failed.length;
  }

  Future<bool> _removeNotification(AppNotificationModel n) async {
    if (isRemotelyDeletable(n)) {
      try {
        await _notificationService.deleteNotification(n.notificacionId);
        return true;
      } on NotificationServiceException catch (e) {
        errorMessage = e.message;
        return false;
      } catch (_) {
        errorMessage = 'No se pudo borrar el aviso.';
        return false;
      }
    }
    _hiddenNotificationIds = <String>{
      ..._hiddenNotificationIds,
      n.notificacionId,
    };
    final String? uid = activeUser?.uid;
    if (uid != null) {
      try {
        await preferences.saveHiddenNotificationIds(
          uid,
          _hiddenNotificationIds,
        );
      } catch (_) {}
    }
    return true;
  }

  // ---- Perfil y Solicitud Habeas Data (`RF-19`, Ley 1581 de 2012) ----

  Future<bool> submitRectificationRequest({
    required UserModel actor,
    required String campo,
    required String detalle,
  }) async {
    final ProducerModel? producer = activeProducer;
    if (producer == null) {
      errorMessage =
          'No hay una ficha de productor vinculada a tu cuenta para rectificar.';
      notifyListeners();
      return false;
    }

    isSubmitting = true;
    errorMessage = null;
    feedbackMessage = null;
    notifyListeners();

    try {
      final AppNotificationModel created =
          await _notificationService.submitDataRectificationRequest(
        producer: producer,
        actor: actor,
        campo: campo,
        detalle: detalle,
      );
      _notifications = <AppNotificationModel>[created, ..._notifications];
      feedbackMessage =
          'Solicitud de rectificación registrada y enviada al Administrador.';
      return true;
    } on NotificationServiceException catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage =
          'No fue posible enviar tu solicitud de rectificación en este momento.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  // ---- Emisor Administrativo de Comunicados (`RF-24`, `HU-14`) ----

  List<AppNotificationModel> get adminNotifications =>
      List<AppNotificationModel>.unmodifiable(_adminNotifications);

  Future<void> loadAdminNotifications() async {
    isLoading = true;
    errorMessage = null;
    notifyListeners();
    try {
      final res = await _notificationService.listAllNotifications();
      _adminNotifications = res.notifications;
      fromCache = res.fromCache;
    } catch (_) {
      errorMessage = 'No se pudo cargar el historial de comunicados.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  Future<bool> sendBroadcast({
    required UserModel actor,
    required String titulo,
    required String mensaje,
    String? destinoProductorId,
  }) async {
    isSubmitting = true;
    errorMessage = null;
    feedbackMessage = null;
    notifyListeners();

    try {
      final AppNotificationModel sent =
          await _notificationService.sendInstitutionalBroadcast(
        actor: actor,
        titulo: titulo,
        mensaje: mensaje,
        destinoProductorId: destinoProductorId,
      );
      _adminNotifications =
          <AppNotificationModel>[sent, ..._adminNotifications];
      if (sent.destinoProductorId == null ||
          sent.destinoProductorId == activeProducer?.productorId) {
        _notifications = <AppNotificationModel>[sent, ..._notifications];
      }
      feedbackMessage = sent.destinoProductorId == null
          ? 'Comunicado institucional enviado a todos los productores.'
          : 'Aviso enviado al productor seleccionado.';
      return true;
    } on NotificationServiceException catch (e) {
      errorMessage = e.message;
      return false;
    } catch (_) {
      errorMessage = 'Ocurrió un error al enviar el comunicado institucional.';
      return false;
    } finally {
      isSubmitting = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _fcmSub?.cancel();
    super.dispose();
  }
}

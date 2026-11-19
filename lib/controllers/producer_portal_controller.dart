import 'dart:async';

import 'package:flutter/foundation.dart';

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
  })  : _hiveService = hiveService ?? HiveService(),
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

  bool isLoading = false;
  bool isSubmitting = false;
  bool fromCache = false;
  String? errorMessage;
  String? feedbackMessage;

  UserModel? activeUser;
  ProducerModel? activeProducer;
  MilkRateModel? activeRate;
  DateTime _refDate = DateTime.now();

  List<MilkReceptionModel> _receptions = <MilkReceptionModel>[];
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
        _settlements = <SettlementModel>[];
        final notifRes = await _notificationService.listForProducer(
          productorId: user.uid,
          userUid: user.uid,
        );
        _notifications = notifRes.notifications;
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
        _settlements = _filterAndSortSettlements(setRes.settlements, prodId);

        _notifications = notifRes.notifications;
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
      _settlements = _filterAndSortSettlements(setRes.settlements, prodId);
      _notifications = notifRes.notifications;
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

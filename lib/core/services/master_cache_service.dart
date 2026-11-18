import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/milk_rate_model.dart';
import '../../models/producer_model.dart';
import '../constants/app_constants.dart';
import 'hive_service.dart';

/// Fuente remota abstracta de catálogos maestros para permitir inyección en pruebas.
abstract class RemoteMasterDataSource {
  Future<List<ProducerModel>> fetchProducers();
  Future<List<MilkRateModel>> fetchRates();
}

/// Implementación por defecto contra Cloud Firestore.
class FirestoreMasterDataSource implements RemoteMasterDataSource {
  FirestoreMasterDataSource({this.firestore});

  final FirebaseFirestore? firestore;

  FirebaseFirestore get _db => firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<ProducerModel>> fetchProducers() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.producersCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              ProducerModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }

  @override
  Future<List<MilkRateModel>> fetchRates() async {
    final QuerySnapshot<Map<String, dynamic>> snap =
        await _db.collection(AppConstants.ratesCollection).get();
    return snap.docs
        .map(
          (QueryDocumentSnapshot<Map<String, dynamic>> doc) =>
              MilkRateModel.fromMap(doc.data(), documentId: doc.id),
        )
        .toList();
  }
}

/// Replica localmente en Hive el padrón de productores y la tarifa vigente
/// para garantizar la operación 100% sin conexión en planta.
class MasterCacheService {
  MasterCacheService({
    required this.hiveService,
    RemoteMasterDataSource? remoteDataSource,
  }) : _remoteDataSource = remoteDataSource ?? FirestoreMasterDataSource();

  final HiveService hiveService;
  final RemoteMasterDataSource _remoteDataSource;

  Future<({int producersCount, int ratesCount, bool fromCache})> refreshAll() async {
    try {
      final List<ProducerModel> producers =
          await _remoteDataSource.fetchProducers();
      final List<MilkRateModel> rates = await _remoteDataSource.fetchRates();

      await hiveService.cacheProducers(producers);
      await hiveService.cacheMilkRates(rates);
      return (
        producersCount: producers.length,
        ratesCount: rates.length,
        fromCache: false,
      );
    } catch (_) {
      final List<ProducerModel> cachedProducers =
          await hiveService.getCachedProducers();
      final List<MilkRateModel> cachedRates =
          await hiveService.getCachedMilkRates();
      return (
        producersCount: cachedProducers.length,
        ratesCount: cachedRates.length,
        fromCache: true,
      );
    }
  }

  Future<List<ProducerModel>> getProducers({
    bool onlyActive = true,
    bool forceRefresh = false,
  }) async {
    if (forceRefresh) {
      await refreshAll();
    }
    final List<ProducerModel> list = await hiveService.getCachedProducers();
    if (!onlyActive) {
      return list;
    }
    return list.where((ProducerModel p) => p.isActivo).toList();
  }

  Future<MilkRateModel?> getActiveRate({bool forceRefresh = false}) async {
    if (forceRefresh) {
      await refreshAll();
    }
    return hiveService.getActiveMilkRate();
  }
}

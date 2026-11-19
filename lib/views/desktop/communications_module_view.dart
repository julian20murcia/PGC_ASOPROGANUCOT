import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../controllers/auth_controller.dart';
import '../../controllers/producer_controller.dart';
import '../../core/security/permissions.dart';
import '../../core/services/broadcast_service.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/formatters.dart';
import '../../models/app_notification_model.dart';
import '../../models/producer_model.dart';
import '../../models/user_model.dart';
import '../shared/widgets/pro_ui.dart';
import 'communications/broadcast_history.dart';
import 'communications/compose_form.dart';
import 'communications/phone_preview.dart';

/// Módulo "Comunicados": redactar avisos para los productores, ver cómo
/// llegan al celular y consultar el historial de envíos.
class CommunicationsModuleView extends StatefulWidget {
  const CommunicationsModuleView({super.key, this.service});

  /// Permite inyectar el servicio en pruebas.
  final BroadcastService? service;

  @override
  State<CommunicationsModuleView> createState() => _CommunicationsModuleViewState();
}

class _CommunicationsModuleViewState extends State<CommunicationsModuleView> {
  late final BroadcastService _service = widget.service ?? BroadcastService();
  List<AppNotificationModel> _items = <AppNotificationModel>[];
  bool _loading = true;
  bool _sending = false;
  String? _error;
  BroadcastDraft _draft = const BroadcastDraft(title: '', message: '');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _load();
      final ProducerController? pc = _producerCtrl;
      if (pc != null && pc.allProducers.isEmpty && !pc.isLoading) pc.loadProducers();
    });
  }

  ProducerController? get _producerCtrl {
    try {
      return context.read<ProducerController>();
    } on ProviderNotFoundException {
      return null;
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final List<AppNotificationModel> list = await _service.listSent();
      if (!mounted) return;
      setState(() => _items = list);
    } on BroadcastException catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<bool> _send(BroadcastDraft d, UserModel me, Map<String, String> names, int activeCount) async {
    final String who = d.producerId == null
        ? 'todos los productores ($activeCount)'
        : (names[d.producerId] ?? 'el productor seleccionado');
    final bool ok = await confirmAction(
      context,
      title: 'Enviar comunicado',
      message: '"${d.title.trim()}" se enviará a $who. Una vez enviado llegará como notificación al celular.',
      confirmLabel: 'Enviar',
    );
    if (!ok || !mounted) return false;
    setState(() => _sending = true);
    try {
      final AppNotificationModel sent = await _service.send(
        actor: me,
        titulo: d.title,
        mensaje: d.message,
        destinoProductorId: d.producerId,
        destinoNombre: d.producerId == null ? null : names[d.producerId],
      );
      if (!mounted) return true;
      setState(() => _items = <AppNotificationModel>[sent, ..._items]);
      showAppToast(context, 'Comunicado enviado a $who.', tone: Tone.success);
      return true;
    } on BroadcastException catch (e) {
      if (mounted) showAppToast(context, e.message, tone: Tone.danger);
      return false;
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _delete(AppNotificationModel n, UserModel me) async {
    final bool ok = await confirmAction(
      context,
      title: 'Eliminar comunicado',
      message: 'Se eliminará "${n.titulo}" del historial y de la app de los productores. '
          'Las notificaciones que ya llegaron a los celulares no se pueden retirar.',
      confirmLabel: 'Eliminar',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _service.delete(actor: me, notification: n);
      if (!mounted) return;
      setState(() => _items = _items.where((AppNotificationModel x) => x.notificacionId != n.notificacionId).toList());
      showAppToast(context, 'Comunicado eliminado.', tone: Tone.success);
    } on BroadcastException catch (e) {
      if (mounted) showAppToast(context, e.message, tone: Tone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final UserModel? me = context.watch<AuthController>().currentUser;
    List<ProducerModel> producers = const <ProducerModel>[];
    try {
      producers = context.watch<ProducerController>().allProducers;
    } on ProviderNotFoundException {
      producers = const <ProducerModel>[];
    }
    final Map<String, String> names = <String, String>{
      for (final ProducerModel p in producers) p.productorId: p.nombreCompleto,
    };
    final int activeCount = producers.where((ProducerModel p) => p.isActivo).length;
    final bool canSee = me?.can(Permissions.comunicados, PermAction.ver) ?? false;
    final bool canCreate = me?.can(Permissions.comunicados, PermAction.crear) ?? false;
    final bool canDelete = me?.can(Permissions.comunicados, PermAction.eliminar) ?? false;
    final bool narrow = MediaQuery.sizeOf(context).width < 900;

    if (!canSee) {
      return const Center(
        child: EmptyState(
          icon: Icons.lock_outline_rounded,
          title: 'Sin acceso a comunicados',
          message: 'Pide a un administrador que te conceda el permiso "Comunicados · Ver".',
        ),
      );
    }

    final int general = _items.where((AppNotificationModel n) => n.destinoProductorId == null).length;
    final DateTime now = DateTime.now();
    final int thisMonth = _items
        .where((AppNotificationModel n) => n.fechaEnvio.toLocal().year == now.year && n.fechaEnvio.toLocal().month == now.month)
        .length;

    final Widget compose = Panel(
      title: 'Redactar comunicado',
      subtitle: 'Título de hasta 80 caracteres y mensaje de hasta 500.',
      icon: Icons.edit_outlined,
      child: ComposeForm(
        producers: producers,
        enabled: canCreate && me != null,
        sending: _sending,
        onDraftChanged: (BroadcastDraft d) => setState(() => _draft = d),
        onSend: (BroadcastDraft d) => _send(d, me!, names, activeCount),
      ),
    );
    final Widget preview = Panel(
      title: 'Así se verá en el celular',
      icon: Icons.phone_android_rounded,
      color: AppTheme.surfaceMuted,
      child: PhonePreview(
        title: _draft.title,
        message: _draft.message,
        general: _draft.producerId == null,
        recipientName: _draft.producerId == null ? null : names[_draft.producerId],
      ),
    );

    return Align(
      alignment: Alignment.topLeft,
      child: SingleChildScrollView(
        padding: EdgeInsets.symmetric(horizontal: narrow ? 16 : 24, vertical: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            PageHeader(
              title: 'Comunicados',
              subtitle: 'Avisos para los productores en la app móvil: a todos o a uno en particular.',
              actions: <Widget>[
                OutlinedButton.icon(
                  onPressed: _loading ? null : _load,
                  icon: const Icon(Icons.refresh_rounded, size: 17),
                  label: const Text('Actualizar'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            StatStrip(
              items: <StatItem>[
                StatItem(label: 'Comunicados enviados', value: '${_items.length}', icon: Icons.campaign_outlined),
                StatItem(label: 'Generales', value: '$general', icon: Icons.groups_2_outlined, tone: Tone.accent),
                StatItem(
                  label: 'Dirigidos',
                  value: '${_items.length - general}',
                  icon: Icons.person_pin_outlined,
                  tone: Tone.info,
                ),
                StatItem(
                  label: 'Este mes',
                  value: '$thisMonth',
                  hint: _items.isEmpty ? null : 'Último: ${AppFormatters.formatDate(_items.first.fechaEnvio)}',
                  icon: Icons.calendar_month_outlined,
                  tone: Tone.success,
                ),
              ],
            ),
            const SizedBox(height: 12),
            LayoutBuilder(
              builder: (BuildContext context, BoxConstraints c) {
                if (c.maxWidth < 860) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[compose, const SizedBox(height: 12), preview],
                  );
                }
                return Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Expanded(child: compose),
                    const SizedBox(width: 12),
                    SizedBox(width: 330, child: preview),
                  ],
                );
              },
            ),
            const SizedBox(height: 12),
            Panel(
              title: 'Historial de comunicados',
              subtitle: 'Del más reciente al más antiguo.',
              icon: Icons.history_rounded,
              padding: EdgeInsets.zero,
              child: _loading && _items.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.symmetric(vertical: 36),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  : _error != null && _items.isEmpty
                      ? EmptyState(
                          icon: Icons.cloud_off_outlined,
                          title: 'No se pudo cargar el historial',
                          message: _error,
                          action: OutlinedButton(onPressed: _load, child: const Text('Reintentar')),
                        )
                      : BroadcastHistory(
                          items: _items,
                          producerNames: names,
                          canDelete: canDelete && me != null,
                          onDelete: (AppNotificationModel n) => _delete(n, me!),
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

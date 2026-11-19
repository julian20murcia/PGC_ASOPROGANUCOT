import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/privacy_notice.dart';
import 'design_system_widgets.dart';
import 'ui_kit.dart';

class PrivacyNoticeView extends StatelessWidget {
  const PrivacyNoticeView({
    super.key,
    required this.notice,
    this.onPolicyOpened,
  });

  final PrivacyNotice notice;
  final VoidCallback? onPolicyOpened;

  static Future<void> openPolicy(
    BuildContext context,
    PrivacyNotice notice, {
    VoidCallback? onPolicyOpened,
  }) async {
    final bool isMobileNative =
        !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS);
    final List<LaunchMode> modes = isMobileNative
        ? <LaunchMode>[
            LaunchMode.inAppBrowserView,
            LaunchMode.externalApplication,
          ]
        : <LaunchMode>[LaunchMode.externalApplication];

    for (final LaunchMode mode in modes) {
      try {
        if (await launchUrl(notice.policyUri, mode: mode)) {
          if (context.mounted) onPolicyOpened?.call();
          return;
        }
      } on PlatformException {
        // Reintentar con modo alternativo o diálogo legible.
      } on MissingPluginException {
        // Reintentar con modo alternativo o diálogo legible.
      }
    }

    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enlace a la política de tratamiento'),
        content: SelectableText(notice.policyUri.toString()),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cerrar'),
          ),
        ],
      ),
    );
    if (context.mounted) onPolicyOpened?.call();
  }

  /// Vista previa integrada de la política completa dentro de la app (con scroll hasta el final para aceptar).
  static Future<bool?> showPolicyPreview(
    BuildContext context, {
    required PrivacyNotice notice,
    bool requireScrollToAccept = false,
    VoidCallback? onPolicyOpened,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: AppTheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _PrivacyPolicyPreviewSheet(
        notice: notice,
        requireScrollToAccept: requireScrollToAccept,
        onPolicyOpened: onPolicyOpened,
      ),
    );
  }

  Future<void> _openPreview(BuildContext context) async {
    await showPolicyPreview(
      context,
      notice: notice,
      requireScrollToAccept: false,
      onPolicyOpened: onPolicyOpened,
    );
    if (context.mounted) onPolicyOpened?.call();
  }

  Future<void> _openPolicy(BuildContext context) =>
      openPolicy(context, notice, onPolicyOpened: onPolicyOpened);

  @override
  Widget build(BuildContext context) {
    final Map<String, String> data = notice.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Versión ${data['version']}', style: AppTheme.subtitleStyle()),
        const SizedBox(height: 8),
        SelectableText(
          '${data['responsable']} es responsable del tratamiento.\n'
          '${data['direccion']} · ${data['telefono']} · ${data['correo']}\n\n'
          '${data['finalidades']}\n\n${data['derechos']}\n\n'
          'También puedes solicitar una copia de la política por los canales indicados.',
          style: const TextStyle(
            fontSize: 13.5,
            height: 1.45,
            color: AppTheme.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: <Widget>[
            TextButton.icon(
              icon: const Icon(Icons.menu_book_outlined, size: 17),
              label: const Text('Ver política completa'),
              onPressed: () => _openPreview(context),
            ),
            TextButton.icon(
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Abrir en navegador'),
              onPressed: () => _openPolicy(context),
            ),
          ],
        ),
      ],
    );
  }
}

class _PrivacyPolicyPreviewSheet extends StatefulWidget {
  const _PrivacyPolicyPreviewSheet({
    required this.notice,
    required this.requireScrollToAccept,
    this.onPolicyOpened,
  });

  final PrivacyNotice notice;
  final bool requireScrollToAccept;
  final VoidCallback? onPolicyOpened;

  @override
  State<_PrivacyPolicyPreviewSheet> createState() =>
      _PrivacyPolicyPreviewSheetState();
}

class _PrivacyPolicyPreviewSheetState extends State<_PrivacyPolicyPreviewSheet> {
  final ScrollController _scrollCtrl = ScrollController();
  double _scrollProgress = 0.0;
  bool _reachedBottom = false;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkInitialExtent());
  }

  @override
  void dispose() {
    _scrollCtrl.removeListener(_handleScroll);
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _checkInitialExtent() {
    if (!mounted || !_scrollCtrl.hasClients) return;
    final ScrollPosition pos = _scrollCtrl.position;
    if (pos.maxScrollExtent <= 16) {
      setState(() {
        _scrollProgress = 1.0;
        _reachedBottom = true;
      });
    }
  }

  void _handleScroll() {
    if (!_scrollCtrl.hasClients) return;
    final ScrollPosition pos = _scrollCtrl.position;
    final double max = pos.maxScrollExtent;
    final double nextProgress = max <= 0
        ? 1.0
        : (pos.pixels / max).clamp(0.0, 1.0);
    final bool atEnd = max <= 16 || pos.pixels >= max - 28;
    if (atEnd != _reachedBottom ||
        (nextProgress - _scrollProgress).abs() >= 0.02) {
      setState(() {
        _scrollProgress = nextProgress;
        if (atEnd) _reachedBottom = true;
      });
    }
  }

  Future<void> _scrollToBottom() async {
    if (!_scrollCtrl.hasClients) return;
    await _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final Map<String, String> data = widget.notice.data;
    final double maxSheetHeight = MediaQuery.sizeOf(context).height * 0.9;

    return SizedBox(
      height: maxSheetHeight,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    const AppIconBadge(
                      icon: Icons.privacy_tip_rounded,
                      color: AppTheme.primaryGreen,
                      size: 36,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          const Text(
                            'Política de tratamiento de datos',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: AppTheme.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Versión ${data['version']} · ${data['responsable']}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Cerrar',
                      onPressed: () => Navigator.of(context).pop(false),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: <Widget>[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreenLight,
                        borderRadius: BorderRadius.circular(AppTheme.radiusPill),
                      ),
                      child: const Text(
                        'Ley 1581 de 2012 · Decreto 1377 de 2013',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.successText,
                        ),
                      ),
                    ),
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        visualDensity: VisualDensity.compact,
                      ),
                      onPressed: () => PrivacyNoticeView.openPolicy(
                        context,
                        widget.notice,
                        onPolicyOpened: widget.onPolicyOpened,
                      ),
                      icon: const Icon(Icons.open_in_new, size: 15),
                      label: const Text('Abrir en navegador'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          LinearProgressIndicator(
            value: _scrollProgress.clamp(0.0, 1.0),
            minHeight: 4,
            backgroundColor: AppTheme.surfaceMuted,
            color: _reachedBottom ? AppTheme.primaryGreen : AppTheme.tealAccent,
          ),
          Expanded(
            child: Scrollbar(
              controller: _scrollCtrl,
              thumbVisibility: true,
              child: SingleChildScrollView(
                controller: _scrollCtrl,
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _PolicySectionBlock(
                      number: '1',
                      title: 'Responsable y canales de atención',
                      body:
                          '${data['responsable']} actúa como responsable del tratamiento de datos personales. '
                          'Domicilio y dirección de atención: ${data['direccion']}. '
                          'Correo electrónico: ${data['correo']}. Teléfono: ${data['telefono']}. '
                          'La administración de la asociación recibe y tramita las solicitudes de los titulares.',
                    ),
                    const _PolicySectionBlock(
                      number: '2',
                      title: 'Ámbito y datos tratados',
                      body:
                          'Esta política aplica a los productores, asociados y usuarios que operan el sistema. '
                          'Se tratan datos de identificación, contacto, vinculación, finca y vereda, entregas '
                          'diarias de leche, liquidaciones, pagos y datos de cuenta, accesos y autorizaciones '
                          'necesarios para prestar el servicio.',
                    ),
                    _PolicySectionBlock(
                      number: '3',
                      title: 'Tratamiento y finalidades',
                      body:
                          '${data['finalidades']} La asociación registra, conserva, consulta y actualiza los datos '
                          'para gestionar la vinculación, registrar entregas de leche, liquidar y confirmar pagos, '
                          'emitir comprobantes, permitir la consulta del historial, verificar tu documento, '
                          'confirmar por SMS tu celular para activar la cuenta y enviar avisos operativos.',
                    ),
                    const _PolicySectionBlock(
                      number: '4',
                      title: 'Autorización y activación del portal (SMS)',
                      body:
                          'Para activar tu acceso en el portal móvil, lees y aceptas esta política vigente y '
                          'verificas mediante código SMS el número celular registrado en el padrón de la asociación. '
                          'Firebase recibe el número únicamente para la verificación por SMS y prevención de abusos. '
                          'El sistema conserva fecha, declaración, aceptación y versión del aviso.',
                    ),
                    const _PolicySectionBlock(
                      number: '5',
                      title: 'Seguridad, proveedores y divulgación',
                      body:
                          'La asociación aplica autenticación individual, control de acceso por rol (solo puedes '
                          'consultar tu propia información como productor), registro inmutable de auditoría y respaldos. '
                          'Los proveedores de infraestructura tecnológica, incluido Firebase cuando intervenga, tratan '
                          'la información conforme a las medidas de seguridad aplicables.',
                    ),
                    _PolicySectionBlock(
                      number: '6',
                      title: 'Derechos del titular (Ley 1581 de 2012)',
                      body:
                          '${data['derechos']} Puedes consultar gratuitamente tus datos, actualizarlos o rectificarlos, '
                          'solicitar prueba de la autorización otorgada, revocar la autorización o solicitar supresión '
                          'cuando proceda, y acudir ante la Superintendencia de Industria y Comercio (SIC) tras '
                          'tramitar consulta o reclamo ante la asociación.',
                    ),
                    _PolicySectionBlock(
                      number: '7',
                      title: 'Cómo presentar consultas y reclamos',
                      body:
                          'Escribe al correo ${data['correo']} o presenta tu solicitud en ${data['direccion']}. '
                          'Indica tu identificación, los hechos o datos objeto de la solicitud y un canal de respuesta. '
                          'Una vez activa tu cuenta móvil, también puedes solicitar rectificación directamente desde '
                          'tu perfil dentro de la aplicación.',
                    ),
                    const _PolicySectionBlock(
                      number: '8',
                      title: 'Plazos de atención',
                      body:
                          'Las consultas se atienden dentro de diez (10) días hábiles contados desde su recibo '
                          '(prorrogables hasta por cinco días hábiles adicionales informando el motivo). Los reclamos '
                          'se atienden dentro de quince (15) días hábiles desde el día siguiente a su recibo '
                          '(prorrogables hasta por ocho días hábiles adicionales cuando sea necesario).',
                    ),
                    const _PolicySectionBlock(
                      number: '9',
                      title: 'Retención e integridad de registros (Ley 527 de 1999)',
                      body:
                          'La información se conserva mientras lo justifiquen las finalidades del servicio y los plazos '
                          'documentales y contables aplicables. Los registros de entregas y liquidaciones conservan su '
                          'origen, usuario responsable, fecha y hora exacta y trazabilidad de cambios para consulta posterior.',
                    ),
                    _PolicySectionBlock(
                      number: '10',
                      title: 'Vigencia y marco normativo',
                      body:
                          'Política versión ${data['version']} emitida conforme a la Ley Estatutaria 1581 de 2012, '
                          'el Decreto 1377 de 2013 (compilado en el Decreto 1074 de 2015) y la Ley 527 de 1999. '
                          'Cualquier cambio sustancial será informado previamente a su aplicación.',
                    ),
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: AppTheme.primaryGreenLight,
                        borderRadius: BorderRadius.circular(AppTheme.radiusCard),
                        border: Border.all(
                          color: AppTheme.primaryGreen.withValues(alpha: 0.35),
                        ),
                      ),
                      child: const Row(
                        children: <Widget>[
                          Icon(
                            Icons.check_circle_outline_rounded,
                            size: 18,
                            color: AppTheme.primaryGreen,
                          ),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Fin del documento · Ya puedes aceptar la política',
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.successText,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Container(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 14),
            decoration: const BoxDecoration(
              color: AppTheme.canvas,
              border: Border(top: BorderSide(color: AppTheme.border)),
            ),
            child: SafeArea(
              top: false,
              child: widget.requireScrollToAccept
                  ? Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            Expanded(
                              child: Text(
                                _reachedBottom
                                    ? 'Lectura completada. Puedes aceptar y continuar.'
                                    : 'Desliza hasta el final para aceptar',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: _reachedBottom
                                      ? AppTheme.successText
                                      : AppTheme.textSecondary,
                                ),
                              ),
                            ),
                            if (!_reachedBottom)
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  visualDensity: VisualDensity.compact,
                                ),
                                onPressed: _scrollToBottom,
                                icon: const Icon(
                                  Icons.arrow_downward_rounded,
                                  size: 15,
                                ),
                                label: const Text('Bajar ↓'),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        PrimaryActionButton(
                          label: 'Aceptar política y continuar',
                          icon: Icons.check_rounded,
                          isMobile: true,
                          fullWidth: true,
                          onPressed: _reachedBottom
                              ? () => Navigator.of(context).pop(true)
                              : null,
                        ),
                      ],
                    )
                  : Row(
                      children: <Widget>[
                        OutlinedButton.icon(
                          onPressed: () => PrivacyNoticeView.openPolicy(
                            context,
                            widget.notice,
                            onPolicyOpened: widget.onPolicyOpened,
                          ),
                          icon: const Icon(Icons.open_in_new, size: 16),
                          label: const Text('Abrir en navegador'),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: PrimaryActionButton(
                            label: 'Cerrar',
                            isMobile: true,
                            fullWidth: true,
                            onPressed: () => Navigator.of(context).pop(false),
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PolicySectionBlock extends StatelessWidget {
  const _PolicySectionBlock({
    required this.number,
    required this.title,
    required this.body,
  });

  final String number;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppTheme.primaryGreenLight,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  number,
                  style: AppTheme.monoStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.primaryGreen,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 14.5,
                    fontWeight: FontWeight.w700,
                    color: AppTheme.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            body,
            style: const TextStyle(
              fontSize: 14,
              height: 1.5,
              color: AppTheme.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

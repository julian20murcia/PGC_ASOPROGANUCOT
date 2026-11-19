import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/privacy_notice.dart';

class PrivacyNoticeView extends StatelessWidget {
  const PrivacyNoticeView({
    super.key,
    required this.notice,
    this.onPolicyOpened,
  });

  final PrivacyNotice notice;
  final VoidCallback? onPolicyOpened;

  Future<void> _openPolicy(BuildContext context) async {
    try {
      if (await launchUrl(
        notice.policyUri,
        mode: LaunchMode.externalApplication,
      )) {
        if (context.mounted) onPolicyOpened?.call();
        return;
      }
    } on PlatformException {
      // El enlace sigue disponible para abrirlo manualmente.
    } on MissingPluginException {
      // El enlace sigue disponible para abrirlo manualmente.
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

  @override
  Widget build(BuildContext context) {
    final data = notice.data;
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
        ),
        TextButton.icon(
          icon: const Icon(Icons.open_in_new),
          label: const Text('Ver política de tratamiento'),
          onPressed: () => _openPolicy(context),
        ),
      ],
    );
  }
}

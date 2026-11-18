import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../../models/privacy_notice.dart';

class PrivacyNoticeView extends StatelessWidget {
  const PrivacyNoticeView({super.key, required this.notice});

  final PrivacyNotice notice;

  @override
  Widget build(BuildContext context) {
    final data = notice.data;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text('Aviso de privacidad · ${data['version']}', style: AppTheme.subtitleStyle()),
        const SizedBox(height: 8),
        SelectableText(
          '${data['responsable']} es responsable del tratamiento.\n'
          '${data['direccion']} · ${data['telefono']} · ${data['correo']}\n\n'
          '${data['finalidades']}\n\n${data['derechos']}\n\n'
          'Consulta la política y sus actualizaciones en ${data['politicaUrl']} '
          'o solicita una copia por el canal de contacto indicado.',
        ),
      ],
    );
  }
}

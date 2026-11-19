import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pgc_asoproganucot/core/services/assistant_report_export.dart';
import 'package:pgc_asoproganucot/core/services/file_export_service.dart';
import 'package:pgc_asoproganucot/models/assistant_report.dart';

Map<String, dynamic> _sample({String chartType = 'barras'}) => <String, dynamic>{
      'titulo': 'Productores con mayor producción',
      'subtitulo': '1 al 31 de octubre de 2026',
      'formato': 'pdf',
      'secciones': <Object?>[
        <String, Object?>{
          'tipo': 'indicadores',
          'titulo': 'Resumen',
          'indicadores': <Object?>[
            <String, String>{'etiqueta': 'Litros totales', 'valor': '12.500 L'},
            <String, String>{'etiqueta': 'Productores', 'valor': '25'},
          ],
        },
        <String, Object?>{
          'tipo': 'grafica',
          'titulo': 'Top 3 productores',
          'grafica': <String, Object?>{
            'tipo': chartType,
            'etiquetas': <String>['A01 Ana', 'A02 Beto', 'A03 Carla'],
            'series': <Object?>[
              <String, Object?>{'nombre': 'Octubre', 'valores': <num>[1200, 980.5, 700]},
              <String, Object?>{'nombre': 'Septiembre', 'valores': <num>[1100, 1000, 650]},
            ],
            'eje_y': 'Litros',
          },
        },
        <String, Object?>{
          'tipo': 'tabla',
          'titulo': 'Detalle',
          'columnas': <String>['Productor', 'Litros', 'Entregas', 'Participación', 'Valor'],
          'tipos_columna': <String>['texto', 'litros', 'entero', 'porcentaje', 'dinero'],
          'filas': <Object?>[
            <String>['Ana', '1200', '60', '9.6', '2220000'],
            <String>['Beto', '980.5', '58', '7.8', '1813925'],
          ],
        },
        <String, Object?>{
          'tipo': 'texto',
          'titulo': 'Análisis',
          'texto': 'La producción se concentra en pocos productores.\n- Ana lidera con 9,6 %.\n- Revisar entregas de la tarde.',
        },
        <String, Object?>{'tipo': 'desconocido'},
      ],
    };

void main() {
  group('AssistantReport.tryParse', () {
    test('lee secciones válidas e ignora las desconocidas', () {
      final AssistantReport r = AssistantReport.tryParse(_sample())!;
      expect(r.title, 'Productores con mayor producción');
      expect(r.sections.length, 4);
      expect(r.charts.single.series.length, 2);
      expect(r.tableCount, 1);
      final ReportSection t = r.sections[2];
      expect(t.cellValue(0, 1), 1200);
      expect(t.cellValue(0, 3), closeTo(0.096, 1e-9));
      expect(t.cellValue(0, 0), 'Ana');
    });

    test('sin secciones devuelve null', () {
      expect(AssistantReport.tryParse(<String, dynamic>{'titulo': 'x', 'secciones': <Object?>[]}), isNull);
      expect(AssistantReport.tryParse(<String, dynamic>{'secciones': 'basura'}), isNull);
    });

    test('series se completan o recortan al número de etiquetas', () {
      final AssistantReport r = AssistantReport.tryParse(<String, dynamic>{
        'titulo': 'x',
        'secciones': <Object?>[
          <String, Object?>{
            'tipo': 'grafica',
            'grafica': <String, Object?>{
              'tipo': 'lineas',
              'etiquetas': <String>['a', 'b', 'c'],
              'series': <Object?>[
                <String, Object?>{'nombre': 's', 'valores': <Object?>[1, 'x']},
              ],
            },
          },
        ],
      })!;
      expect(r.charts.single.series.single.values, <double>[1, 0, 0]);
    });

    test('parseNumber acepta formatos comunes', () {
      expect(AssistantReport.parseNumber('1250.5'), 1250.5);
      expect(AssistantReport.parseNumber('1.250,5'), 1250.5);
      expect(AssistantReport.parseNumber(r'$ 1.850'), 1850);
      expect(AssistantReport.parseNumber('1,250.75'), 1250.75);
      expect(AssistantReport.parseNumber('45%'), 45);
      expect(AssistantReport.parseNumber('Ana'), isNull);
    });
  });

  group('AssistantReportExport', () {
    test('niceTicks cubre el máximo con pasos redondos', () {
      final List<double> t = AssistantReportExport.niceTicks(1234);
      expect(t.first, 0);
      expect(t.last, greaterThanOrEqualTo(1234));
      expect(AssistantReportExport.niceTicks(0), <double>[0, 1]);
    });

    test('Excel incluye hojas, gráfica nativa y relaciones coherentes', () {
      final AssistantReport r = AssistantReport.tryParse(_sample())!;
      final Uint8List bytes = AssistantReportExport.buildXlsx(r);
      final Archive zip = ZipDecoder().decodeBytes(bytes);
      String file(String name) => utf8.decode(zip.findFile(name)!.content as List<int>);

      final String ct = file('[Content_Types].xml');
      expect(ct, contains('/xl/charts/chart1.xml'));
      expect(ct, contains('/xl/drawings/drawing1.xml'));
      final String wb = file('xl/workbook.xml');
      expect(wb, contains('name="Resumen"'));
      expect(wb, contains('name="Gráfica 1"'));
      expect(wb, contains('name="Detalle"'));
      // La hoja de la gráfica (2.ª) referencia el dibujo.
      expect(file('xl/worksheets/sheet2.xml'), contains('<drawing r:id="rId1"/>'));
      expect(file('xl/worksheets/_rels/sheet2.xml.rels'), contains('../drawings/drawing1.xml'));
      expect(file('xl/drawings/_rels/drawing1.xml.rels'), contains('../charts/chart1.xml'));
      final String chart = file('xl/charts/chart1.xml');
      expect(chart, contains('<c:barChart>'));
      expect(chart, contains("'Gráfica 1'!\$B\$5:\$B\$7"));
      expect(chart, contains('<c:v>980.5</c:v>'));
      // Hojas sin gráficas no llevan dibujo.
      expect(file('xl/worksheets/sheet3.xml'), isNot(contains('<drawing')));
      // Porcentaje exportado en 0–100.
      expect(file('xl/worksheets/sheet3.xml'), contains('<v>9.6</v>'));
    });

    test('Excel de torta usa pieChart con una sola serie', () {
      final AssistantReport r = AssistantReport.tryParse(_sample(chartType: 'torta'))!;
      final Archive zip = ZipDecoder().decodeBytes(AssistantReportExport.buildXlsx(r));
      final String chart = utf8.decode(zip.findFile('xl/charts/chart1.xml')!.content as List<int>);
      expect(chart, contains('<c:pieChart>'));
      expect('<c:ser>'.allMatches(chart).length, 1);
    });

    for (final String type in <String>['barras', 'barras_horizontales', 'lineas', 'torta']) {
      test('PDF con gráfica "$type" se genera', () async {
        final AssistantReport r = AssistantReport.tryParse(_sample(chartType: type))!;
        final Uint8List pdf = await AssistantReportExport.build(r, ExportFormat.pdf, generatedBy: 'Prueba');
        expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
        expect(pdf.length, greaterThan(1500));
      });
    }

    test('PDF con muchas categorías (barras → horizontales) se genera', () async {
      final AssistantReport r = AssistantReport.tryParse(<String, dynamic>{
        'titulo': 'Muchos',
        'secciones': <Object?>[
          <String, Object?>{
            'tipo': 'grafica',
            'grafica': <String, Object?>{
              'tipo': 'barras',
              'etiquetas': <String>[for (int i = 0; i < 30; i++) 'Productor número $i'],
              'series': <Object?>[
                <String, Object?>{'nombre': 'L', 'valores': <num>[for (int i = 0; i < 30; i++) i * 37.5]},
              ],
            },
          },
        ],
      })!;
      final Uint8List pdf = await AssistantReportExport.buildPdf(r);
      expect(String.fromCharCodes(pdf.take(5)), '%PDF-');
    });

    test('nombre de archivo seguro', () {
      final AssistantReport r = AssistantReport.tryParse(_sample())!;
      expect(AssistantReportExport.fileBaseName(r), startsWith('ia_productores_con_mayor_produccion_'));
    });
  });
}

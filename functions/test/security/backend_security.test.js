/**
 * PRUEBAS DE SEGURIDAD — Backend (Cloud Functions del asistente IA).
 *
 * Verifican, sin red ni emulador:
 *  - Autenticación obligatoria en todas las funciones invocables.
 *  - Validación estricta de entradas de la herramienta `consultar_produccion`
 *    (fechas, rangos, inyección de texto, límites).
 *  - Saneamiento del informe que genera el modelo (OWASP LLM02: manejo
 *    inseguro de salidas): caracteres de control, tamaños máximos, tipos.
 *  - Esquemas de herramientas cerrados (sin parámetros extra).
 *  - Que ninguna clave secreta esté escrita en el código.
 */
const assert = require('node:assert/strict');
const { readFileSync } = require('node:fs');
const { join } = require('node:path');
const { test, describe } = require('node:test');
const { initializeApp } = require('firebase-admin/app');

initializeApp({ projectId: 'demo-asoproganucot' });
const assistant = require('../../assistant');
const { queryProduction, sanitizeReport, TOOLS } = assistant._internal;

/** Firestore falso: devuelve siempre las mismas entregas y productores. */
function fakeDb(receptions = [], producers = {}) {
  const snap = (docs) => ({ docs: docs.map(([id, data]) => ({ id, data: () => data })) });
  return {
    collection(name) {
      const q = {
        where() { return q; },
        async get() {
          if (name === 'productores') return snap(Object.entries(producers));
          if (name === 'recepciones_leche') return snap(receptions.map((r, i) => [`r${i}`, r]));
          return snap([]);
        },
      };
      return q;
    },
  };
}

describe('Autenticación obligatoria en funciones invocables', () => {
  for (const name of ['askAssistant', 'transcribeAudio', 'createVoiceSession']) {
    test(`${name} rechaza llamadas sin sesión`, async () => {
      await assert.rejects(
        assistant[name].run({ auth: null, data: { question: 'hola', audio: 'AAAA', mimeType: 'audio/wav' } }),
        (e) => e.code === 'unauthenticated',
      );
    });
  }
});

describe('Validación de entradas de consultar_produccion', () => {
  const db = fakeDb();
  const base = { agrupar_por: 'productor', productor_codigo: null, vereda: null, limite: null };

  test('rechaza fechas mal formadas o con texto inyectado', async () => {
    for (const desde of ["2026-01-01' OR '1'='1", '2026/01/01', '01-01-2026', '', '2026-1-1', '<script>']) {
      const r = await assistant._internal.queryProduction(db, { ...base, desde, hasta: '2026-01-31' });
      assert.ok(r.error, `debió rechazar desde=${desde}`);
    }
  });

  test('rechaza rangos invertidos y mayores a 2 años', async () => {
    assert.ok((await queryProduction(db, { ...base, desde: '2026-02-01', hasta: '2026-01-01' })).error);
    assert.ok((await queryProduction(db, { ...base, desde: '2020-01-01', hasta: '2026-01-01' })).error);
    assert.ok(!(await queryProduction(db, { ...base, desde: '2025-01-01', hasta: '2026-12-31' })).error);
  });

  test('el límite de filas se acota (no se puede pedir una cantidad ilimitada)', async () => {
    const recs = Array.from({ length: 900 }, (_, i) => ({
      productorId: `p${i}`, fechaEntrega: '2026-01-05', jornada: 'MANANA', litros: 10,
    }));
    const r = await queryProduction(fakeDb(recs), { ...base, desde: '2026-01-01', hasta: '2026-01-31', limite: 1000000 });
    assert.equal(r.filas.length, 500);
    assert.equal(r.filas_totales, 900);
    const neg = await queryProduction(fakeDb(recs), { ...base, desde: '2026-01-01', hasta: '2026-01-31', limite: -3 });
    assert.equal(neg.filas.length, 500);
  });

  test('ignora entregas anuladas y valores no numéricos', async () => {
    const recs = [
      { productorId: 'p1', fechaEntrega: '2026-01-05', jornada: 'MANANA', litros: 10 },
      { productorId: 'p1', fechaEntrega: '2026-01-05', jornada: 'TARDE', litros: 99, anulado: true },
      { productorId: 'p1', fechaEntrega: '2026-01-06', jornada: 'TARDE', litros: 'NaN' },
    ];
    const r = await queryProduction(fakeDb(recs), { ...base, desde: '2026-01-01', hasta: '2026-01-31' });
    assert.equal(r.total_litros, 10);
    assert.equal(r.total_entregas, 1);
  });
});

describe('Saneamiento del informe generado por la IA', () => {
  test('elimina caracteres de control y acota longitudes', () => {
    const r = sanitizeReport({
      titulo: `Hola\u0000\u0007${'x'.repeat(500)}`,
      formato: 'pdf',
      secciones: [{ tipo: 'texto', titulo: 'T', texto: 'a\u0001b' }],
    });
    assert.ok(!/[\u0000-\u0008]/.test(r.titulo));
    assert.ok(r.titulo.length <= 140);
    assert.equal(r.secciones[0].texto, 'ab');
  });

  test('impone máximos de secciones, columnas, filas y series', () => {
    const big = {
      titulo: 'Grande',
      formato: 'excel',
      secciones: [
        { tipo: 'tabla', columnas: Array.from({ length: 50 }, (_, i) => `c${i}`),
          filas: Array.from({ length: 5000 }, () => Array(50).fill('1')) },
        { tipo: 'grafica', grafica: { tipo: 'barras', etiquetas: Array.from({ length: 500 }, (_, i) => `e${i}`),
          series: Array.from({ length: 40 }, (_, i) => ({ nombre: `s${i}`, valores: [Infinity, NaN, 'x', 5] })) } },
        ...Array.from({ length: 100 }, () => ({ tipo: 'texto', texto: 'relleno' })),
      ],
    };
    const r = sanitizeReport(big);
    assert.ok(r.secciones.length <= 30);
    const t = r.secciones[0];
    assert.equal(t.columnas.length, 12);
    assert.equal(t.filas.length, 1000);
    const g = r.secciones[1].grafica;
    assert.ok(g.etiquetas.length <= 60);
    assert.ok(g.series.length <= 6);
    assert.deepEqual(g.series[0].valores.slice(0, 4), [0, 0, 0, 5]);
  });

  test('descarta tipos de sección y de gráfica desconocidos; formato por defecto PDF', () => {
    const r = sanitizeReport({
      titulo: 'X', formato: 'exe',
      secciones: [
        { tipo: 'script', texto: 'alert(1)' },
        { tipo: 'grafica', grafica: { tipo: '3d-malicioso', etiquetas: ['a'], series: [{ nombre: 's', valores: [1] }] } },
        { tipo: 'texto', texto: 'válido' },
      ],
    });
    assert.equal(r.formato, 'pdf');
    assert.equal(r.secciones.length, 1);
    assert.equal(sanitizeReport({ secciones: [] }), null);
    assert.equal(sanitizeReport(null), null);
  });
});

describe('Esquemas cerrados de herramientas del modelo', () => {
  function checkClosed(schema, path) {
    if (!schema || typeof schema !== 'object') return;
    if (schema.anyOf) schema.anyOf.forEach((s, i) => checkClosed(s, `${path}.anyOf[${i}]`));
    if (schema.type === 'object' || (Array.isArray(schema.type) && schema.type.includes('object'))) {
      assert.equal(schema.additionalProperties, false, `${path} debe prohibir propiedades extra`);
      assert.deepEqual([...schema.required].sort(), Object.keys(schema.properties).sort(), `${path} requiere todas`);
      for (const [k, v] of Object.entries(schema.properties)) checkClosed(v, `${path}.${k}`);
    }
    if (schema.items) checkClosed(schema.items, `${path}[]`);
  }

  test('todas las herramientas usan modo estricto y objetos cerrados', () => {
    assert.ok(TOOLS.length >= 2);
    for (const t of TOOLS) {
      assert.equal(t.strict, true, `${t.name} en modo estricto`);
      checkClosed(t.parameters, t.name);
    }
  });
});

describe('Gestión de secretos', () => {
  test('la clave de OpenAI se lee de Secret Manager y no está escrita en el código', () => {
    const src = readFileSync(join(__dirname, '..', '..', 'assistant.js'), 'utf8');
    assert.match(src, /defineSecret\('OPENAI_API_KEY'\)/);
    assert.doesNotMatch(src, /sk-(proj-)?[A-Za-z0-9_-]{20,}/);
  });
});

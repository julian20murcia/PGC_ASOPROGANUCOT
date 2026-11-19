/**
 * PRUEBAS DE ESTRÉS — Backend del asistente IA (Cloud Functions).
 *
 * - consultar_produccion con 300.000 entregas (≈ 7 años de operación real).
 * - 50 consultas concurrentes (ráfaga de usuarios) con resultados exactos.
 * - Saneamiento de un informe malicioso gigante (100.000 filas) sin bloquearse.
 *
 * Cada prueba imprime `METRICA {json}` para el informe del workflow.
 */
const assert = require('node:assert/strict');
const { test } = require('node:test');
const { initializeApp } = require('firebase-admin/app');

initializeApp({ projectId: 'demo-asoproganucot' });
const { queryProduction, sanitizeReport } = require('../../assistant')._internal;

const PRODUCERS = 1000;
const DAYS = 150;
const milli = (p, d, s) => 5000 + ((p * 7919 + d * 104729 + s * 15485863) % 30000);
const iso = (d) => new Date(Date.UTC(2026, 0, 1) + d * 86400000).toISOString().slice(0, 10);

const producers = Object.fromEntries(Array.from({ length: PRODUCERS }, (_, p) => [
  `p${p}`, { codigoAsociado: `ASO-${p}`, nombres: 'Productor', apellidos: `${p}`, vereda: `Vereda ${p % 12}` },
]));
const receptions = [];
for (let p = 0; p < PRODUCERS; p++) {
  for (let d = 0; d < DAYS; d++) {
    for (let s = 0; s < 2; s++) {
      receptions.push({ productorId: `p${p}`, fechaEntrega: iso(d), jornada: s ? 'TARDE' : 'MANANA', litros: milli(p, d, s) / 1000 });
    }
  }
}

function fakeDb() {
  const snap = (docs) => ({ docs: docs.map(([id, data]) => ({ id, data: () => data })) });
  return {
    collection(name) {
      const filters = [];
      const q = {
        where(field, op, value) { filters.push([field, op, value]); return q; },
        async get() {
          if (name === 'productores') return snap(Object.entries(producers));
          // Simula el filtro por rango que aplica Firestore.
          const rows = receptions.filter((r) => filters.every(([f, op, v]) => (op === '>=' ? r[f] >= v : r[f] <= v)));
          return snap(rows.map((r, i) => [`r${i}`, r]));
        },
      };
      return q;
    },
  };
}

function metric(prueba, ms, presupuesto, extra = {}) {
  console.log(`METRICA ${JSON.stringify({ prueba, ms: Math.round(ms), presupuesto_ms: presupuesto, ...extra })}`);
  assert.ok(ms < presupuesto, `${prueba}: ${Math.round(ms)} ms > ${presupuesto} ms`);
}

const expectedMilli = (from, to) => {
  let t = 0;
  for (let p = 0; p < PRODUCERS; p++) for (let d = from; d <= to; d++) t += milli(p, d, 0) + milli(p, d, 1);
  return t;
};

test(`consultar_produccion agrega ${PRODUCERS * DAYS * 2} entregas con exactitud`, async () => {
  const t0 = performance.now();
  const r = await queryProduction(fakeDb(), {
    desde: iso(0), hasta: iso(DAYS - 1), agrupar_por: 'productor', productor_codigo: null, vereda: null, limite: 10,
  });
  metric('Asistente: consulta de 300.000 entregas agrupadas por productor', performance.now() - t0, 3000, { entregas: receptions.length });
  assert.equal(r.total_entregas, receptions.length);
  assert.equal(Math.round(r.total_litros * 1000), expectedMilli(0, DAYS - 1));
  assert.equal(r.filas.length, 10);
  assert.ok(r.filas[0].litros >= r.filas[9].litros, 'ranking ordenado de mayor a menor');
});

test('50 consultas concurrentes devuelven resultados exactos', async () => {
  const groups = ['productor', 'dia', 'semana', 'mes', 'vereda', 'jornada', 'total'];
  const t0 = performance.now();
  const results = await Promise.all(Array.from({ length: 50 }, (_, i) => queryProduction(fakeDb(), {
    desde: iso(i), hasta: iso(i + 30), agrupar_por: groups[i % groups.length], productor_codigo: null, vereda: null, limite: null,
  })));
  metric('Asistente: 50 consultas concurrentes (ráfaga)', performance.now() - t0, 15000, { consultas: 50 });
  results.forEach((r, i) => {
    assert.equal(Math.round(r.total_litros * 1000), expectedMilli(i, i + 30), `consulta ${i}`);
  });
});

test('saneamiento de un informe malicioso de 100.000 filas no bloquea el servidor', () => {
  const payload = {
    titulo: 'x'.repeat(1e6),
    formato: 'excel',
    secciones: [{
      tipo: 'tabla',
      columnas: Array.from({ length: 200 }, (_, i) => `c${i}`),
      filas: Array.from({ length: 100000 }, () => Array.from({ length: 20 }, () => 'y'.repeat(50))),
    }],
  };
  const t0 = performance.now();
  const r = sanitizeReport(payload);
  metric('Asistente: saneamiento de informe gigante (100.000 filas)', performance.now() - t0, 2000);
  assert.equal(r.secciones[0].filas.length, 1000);
  assert.equal(r.titulo.length, 140);
});

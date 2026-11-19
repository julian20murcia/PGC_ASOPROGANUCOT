/**
 * Espejo en servidor de `lib/core/security/permissions.dart`.
 * Mantener ambos sincronizados.
 */
const MODULES = {
  dashboard: ['ver'],
  recepcion: ['ver', 'crear', 'editar', 'eliminar', 'exportar'],
  productores: ['ver', 'crear', 'editar', 'eliminar', 'exportar'],
  liquidaciones: ['ver', 'crear', 'editar', 'exportar'],
  tarifas: ['ver', 'crear'],
  reportes: ['ver', 'exportar'],
  usuarios: ['ver', 'crear', 'editar', 'eliminar'],
  comunicados: ['ver', 'crear', 'eliminar'],
  asistente: ['ver'],
};

const OPERARIO_DEFAULTS = {
  dashboard: ['ver'],
  recepcion: ['ver', 'crear', 'exportar'],
  productores: ['ver'],
  liquidaciones: ['ver'],
  tarifas: ['ver'],
  comunicados: ['ver'],
  asistente: ['ver'],
};

function effective(profile) {
  if (!profile || profile.activo !== true) return {};
  if (profile.rol === 'ADMIN') return MODULES;
  if (profile.rol !== 'OPERARIO') return {};
  return profile.permisos && typeof profile.permisos === 'object' ? profile.permisos : OPERARIO_DEFAULTS;
}

function can(profile, module, action = 'ver') {
  if (profile?.rol === 'ADMIN' && profile.activo === true) return true;
  const list = effective(profile)[module];
  return Array.isArray(list) && list.includes(action);
}

/** Limpia un mapa de permisos y evita que un no-admin otorgue más de lo que tiene. */
function sanitizePermissions(raw, actor) {
  if (!raw || typeof raw !== 'object' || Array.isArray(raw)) return null;
  const out = {};
  for (const [module, actions] of Object.entries(raw)) {
    const allowed = MODULES[module];
    if (!allowed || !Array.isArray(actions)) continue;
    let list = [...new Set(actions.filter((a) => typeof a === 'string' && allowed.includes(a)))];
    if (actor?.rol !== 'ADMIN') list = list.filter((a) => can(actor, module, a));
    if (list.length && !list.includes('ver')) list.unshift('ver');
    if (list.length) out[module] = list;
  }
  return out;
}

module.exports = { MODULES, OPERARIO_DEFAULTS, can, sanitizePermissions };

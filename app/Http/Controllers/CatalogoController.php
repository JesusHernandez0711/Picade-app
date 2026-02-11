<?php

namespace App\Http\Controllers;

use Illuminate\Support\Facades\DB;

class CatalogoController extends Controller
{
    /* ============================================================================================
       CONTROLADOR: CatalogoController
       ============================================================================================

       PROPÓSITO:
       Centraliza todos los endpoints AJAX de catálogos dependientes (cascadas) para que
       cualquier módulo de PICADE pueda consumirlos sin duplicar lógica.

       ¿POR QUÉ UN CONTROLADOR SEPARADO?
       ──────────────────────────────────
       Las cascadas geográficas (País→Estado→Municipio) y organizacionales
       (Dirección→Subdirección→Gerencia) se necesitan en MÚLTIPLES módulos:
         - Usuarios    → Formulario de alta/edición de adscripción
         - Cursos      → Selección de Sede (depende de Municipio)
         - Sedes       → Alta de nueva sede (cascada geográfica completa)
         - Reportes    → Filtros por región geográfica u organizacional
         - (Futuro)    → Cualquier módulo que toque adscripción

       Si estas cascadas vivieran en UsuarioController, los demás módulos tendrían que
       duplicar los métodos o hacer llamadas cruzadas entre controladores (antipatrón).

       MÓDULOS QUE CONSUMEN ESTE CONTROLADOR:
       ───────────────────────────────────────
         Módulo              Cascada que usa                    Formulario
         ─────────────────   ──────────────────────────────     ──────────────────
         Usuarios            Geográfica + Organizacional        create, edit, perfil
         Cursos              Geográfica (para Sede)             create, edit
         Sedes               Geográfica completa                create, edit
         Reportes            Ambas (filtros de dashboard)       filtros
         Catálogos Admin     Ambas (CRUD de catálogos hijos)    edit

       MAPEO DE MÉTODOS → STORED PROCEDURES:
       ─────────────────────────────────────
       CASCADA GEOGRÁFICA:
         estadosPorPais($id)              → SP_ListarEstadosPorPais
         municipiosPorEstado($id)         → SP_ListarMunicipiosPorEstado

       CASCADA ORGANIZACIONAL:
         subdireccionesPorDireccion($id)  → SP_ListarSubdireccionesPorDireccion
         gerenciasPorSubdireccion($id)    → SP_ListarGerenciasPorSubdireccion

       ARQUITECTURA DE SEGURIDAD (4 CAPAS):
       ────────────────────────────────────
       CAPA 1 - SP DE LECTURA (este controlador):
         Valida padre activo + candado jerárquico → SIGNAL si falla.
       CAPA 2 - LARAVEL AJAX (este controlador):
         Valida input básico (>0) + doble catch (QueryException + genérico).
       CAPA 3 - SP DE ESCRITURA (en el controlador que persiste, ej: UsuarioController):
         Anti-zombie en INSERT/UPDATE → última línea antes de persistir.
       CAPA 4 - BD FÍSICA:
         FOREIGN KEY + UNIQUE → barrera definitiva si todo lo demás falla.

       FORMATO DE RESPUESTA:
       ─────────────────────
       Éxito  → 200 JSON: [{Id, Codigo/Clave, Nombre}, ...]
       Vacío  → 200 JSON: []  (el SP no encontró hijos, el front deshabilita el select)
       SIGNAL → 422 JSON: {"error": "Mensaje limpio del SP"}
       Falla  → 500 JSON: {"error": "Error interno al cargar [catálogo]."}
       Input  → 400 JSON: {"error": "ID de [padre] inválido."}
       ============================================================================================ */

    /**
     * Middleware: Solo usuarios autenticados pueden consumir estos endpoints.
     */
    public function __construct()
    {
        $this->middleware('auth');
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 1: CASCADA GEOGRÁFICA (País → Estado → Municipio)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * ESTADOS POR PAÍS (NIVEL 2)
     * ══════════════════════════
     * SP UTILIZADO: SP_ListarEstadosPorPais
     *
     * VALIDACIONES DEL SP:
     *   - _Id_Pais > 0
     *   - País existe en BD
     *   - País Activo=1 (Candado de contrato: no se listan hijos de padres inactivos)
     *
     * CONSUMIDO POR: JavaScript al seleccionar un País en cualquier formulario.
     * RETORNA: JSON [{Id_Estado, Codigo, Nombre}]
     *
     * EJEMPLO DE USO EN EL FRONT:
     *   fetch('/api/catalogos/estados-por-pais/1')
     *     .then(r => r.json())
     *     .then(estados => { // llenar <select id="select-estado"> })
     */
    public function estadosPorPais(int $idPais)
    {
        /* RED DE SEGURIDAD LARAVEL: Validación antes de llegar al SP */
        if ($idPais <= 0) {
            return response()->json(['error' => 'ID de País inválido.'], 400);
        }

        try {
            $estados = DB::select('CALL SP_ListarEstadosPorPais(?)', [$idPais]);

            return response()->json($estados);

        } catch (\Illuminate\Database\QueryException $e) {
            /* CAPA 1: El SP disparó SIGNAL (padre inactivo, inexistente, etc.) */
            return response()->json([
                'error' => $this->extraerMensajeSP($e->getMessage())
            ], 422);

        } catch (\Exception $e) {
            /* CAPA 2: Error inesperado (conexión BD, timeout, etc.) */
            return response()->json([
                'error' => 'Error interno al cargar los estados.'
            ], 500);
        }
    }

    /**
     * MUNICIPIOS POR ESTADO (NIVEL 3)
     * ═══════════════════════════════
     * SP UTILIZADO: SP_ListarMunicipiosPorEstado
     *
     * VALIDACIONES DEL SP (CANDADO JERÁRQUICO):
     *   - _Id_Estado > 0
     *   - Estado existe en BD
     *   - Estado Activo=1 Y su País padre Activo=1
     *   (Si el País fue desactivado, aunque el Estado esté activo, se bloquea)
     *
     * CONSUMIDO POR: JavaScript al seleccionar un Estado en cualquier formulario.
     * RETORNA: JSON [{Id_Municipio, Codigo, Nombre}]
     */
    public function municipiosPorEstado(int $idEstado)
    {
        if ($idEstado <= 0) {
            return response()->json(['error' => 'ID de Estado inválido.'], 400);
        }

        try {
            $municipios = DB::select('CALL SP_ListarMunicipiosPorEstado(?)', [$idEstado]);

            return response()->json($municipios);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'error' => $this->extraerMensajeSP($e->getMessage())
            ], 422);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Error interno al cargar los municipios.'
            ], 500);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 2: CASCADA ORGANIZACIONAL (Dirección → Subdirección → Gerencia)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * SUBDIRECCIONES POR DIRECCIÓN (NIVEL 2)
     * ═════════════════════════════════════
     * SP UTILIZADO: SP_ListarSubdireccionesPorDireccion
     *
     * VALIDACIONES DEL SP:
     *   - _Id_CatDirecc > 0
     *   - Dirección existe en BD
     *   - Dirección Activo=1 (Candado de contrato)
     *
     * CONSUMIDO POR: JavaScript al seleccionar una Dirección en cualquier formulario.
     * RETORNA: JSON [{Id_CatSubDirec, Clave, Nombre}]
     */
    public function subdireccionesPorDireccion(int $idDireccion)
    {
        if ($idDireccion <= 0) {
            return response()->json(['error' => 'ID de Dirección inválido.'], 400);
        }

        try {
            $subdirecciones = DB::select('CALL SP_ListarSubdireccionesPorDireccion(?)', [$idDireccion]);

            return response()->json($subdirecciones);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'error' => $this->extraerMensajeSP($e->getMessage())
            ], 422);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Error interno al cargar las subdirecciones.'
            ], 500);
        }
    }

    /**
     * GERENCIAS POR SUBDIRECCIÓN (NIVEL 3)
     * ════════════════════════════════════
     * SP UTILIZADO: SP_ListarGerenciasPorSubdireccion
     *
     * VALIDACIONES DEL SP (CANDADO JERÁRQUICO):
     *   - _Id_CatSubDirec > 0
     *   - Subdirección existe en BD
     *   - Subdirección Activo=1 Y su Dirección padre Activo=1
     *   (Si la Dirección fue desactivada, aunque la Subdirección esté activa, se bloquea)
     *
     * CONSUMIDO POR: JavaScript al seleccionar una Subdirección en cualquier formulario.
     * RETORNA: JSON [{Id_CatGeren, Clave, Nombre}]
     */
    public function gerenciasPorSubdireccion(int $idSubdireccion)
    {
        if ($idSubdireccion <= 0) {
            return response()->json(['error' => 'ID de Subdirección inválido.'], 400);
        }

        try {
            $gerencias = DB::select('CALL SP_ListarGerenciasPorSubdireccion(?)', [$idSubdireccion]);

            return response()->json($gerencias);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'error' => $this->extraerMensajeSP($e->getMessage())
            ], 422);

        } catch (\Exception $e) {
            return response()->json([
                'error' => 'Error interno al cargar las gerencias.'
            ], 500);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 3: MÉTODOS PRIVADOS (UTILIDADES INTERNAS)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * Extrae el mensaje limpio del SIGNAL del Stored Procedure.
     *
     * PROBLEMA:
     *   Laravel envuelve el error SQL en capas de texto:
     *   "SQLSTATE[45000]: <<1644>>: 7 ERROR [400]: El ID del País debe ser mayor a cero."
     *
     * SOLUCIÓN:
     *   Buscamos el patrón de nuestros códigos de error personalizados.
     *   Si lo encontramos, extraemos desde ahí.
     *   Si no, retornamos un mensaje genérico amigable.
     *
     * NOTA:
     *   Este método es idéntico al de UsuarioController. Si se necesita en un tercer
     *   controlador, considerar extraer a un Trait (App\Traits\ParseaErroresSP).
     *
     * @param  string  $mensajeCompleto  El mensaje crudo de la excepción de Laravel.
     * @return string  El mensaje limpio del SP listo para mostrar al usuario.
     */
    private function extraerMensajeSP(string $mensajeCompleto): string
    {
        if (preg_match('/(ERROR DE .+|CONFLICTO .+|ACCIÓN DENEGADA .+|BLOQUEO .+|ERROR .+)/i', $mensajeCompleto, $matches)) {
            return rtrim($matches[1], ' .)');
        }

        return 'Ocurrió un error al procesar la solicitud. Intente nuevamente.';
    }
}

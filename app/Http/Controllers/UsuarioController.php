<?php

namespace App\Http\Controllers;

use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class UsuarioController extends Controller
{
    /* ============================================================================================
       CONTROLADOR: UsuarioController
       ============================================================================================

       PROPÓSITO:
       Orquesta todas las operaciones CRUD y de gestión del módulo de Usuarios en PICADE.
       Cada método público mapea a uno o más Stored Procedures que contienen la lógica de negocio.

       MAPEO DE MÉTODOS → STORED PROCEDURES:
       ──────────────────────────────────────
       RESOURCE (Admin):
         index()    → Vista_Usuarios (Vista SQL con JOIN de 3 tablas)
         create()   → Muestra formulario de alta administrativa
         store()    → SP_RegistrarUsuarioPorAdmin (20 parámetros)
         show($id)  → SP_ConsultarUsuarioPorAdmin (Radiografía completa)
         edit($id)  → SP_ConsultarUsuarioPorAdmin (Mismos datos, para formulario)
         update()   → SP_EditarUsuarioPorAdmin (21 parámetros, con reset de password)
         destroy()  → SP_EliminarUsuarioDefinitivamente (Hard Delete con análisis forense)

       PERFIL PROPIO (Usuario autenticado):
         perfil()                → SP_ConsultarPerfilPropio
         actualizarPerfil()      → SP_EditarPerfilPropio
         actualizarCredenciales()→ SP_ActualizarCredencialesPropio

       GESTIÓN DE ESTATUS (Admin):
         cambiarEstatus()        → SP_CambiarEstatusUsuario (Baja/Alta lógica)

       LISTADOS PARA DROPDOWNS:
         listarInstructoresActivos()   → SP_ListarInstructoresActivos
         listarInstructoresHistorial() → SP_ListarTodosInstructores_Historial

       PATRÓN DE MANEJO DE ERRORES:
       ────────────────────────────
       Todos los SPs lanzan SIGNAL SQLSTATE '45000' con códigos personalizados:
         [400] → Validación fallida
         [403] → Permisos/Auditoría
         [404] → No encontrado
         [409] → Conflicto (duplicado, concurrencia, dependencia operativa)
         [409-A] → Duplicado activo
         [409-B] → Duplicado inactivo
       
       Laravel atrapa estos SIGNAL como QueryException, los parsea con extraerMensajeSP()
       y los clasifica con clasificarAlerta() para mostrar alertas Bootstrap en el front.
       ============================================================================================ */

    /**
     * Middleware: Solo usuarios autenticados pueden acceder a este controlador.
     * La autorización por rol (Admin vs Usuario normal) se maneja con Gates en cada método.
     */
    public function __construct()
    {
        $this->middleware('auth');
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 1: MÉTODOS RESOURCE (CRUD ADMINISTRATIVO)
       Estos métodos son exclusivos para Administradores y personal de RH.
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * LISTADO GENERAL DE USUARIOS (TABLA CRUD ADMIN)
     * ═══════════════════════════════════════════════
     * SP UTILIZADO: Ninguno — Usa la Vista SQL "Vista_Usuarios"
     *
     * ¿POR QUÉ UNA VISTA Y NO UN SP?
     *   La Vista_Usuarios ya tiene el INNER JOIN de Usuarios + Info_Personal + Cat_Roles
     *   optimizado a nivel de índices. Para un listado paginado, Laravel necesita un
     *   Query Builder (para ->paginate()), y las Vistas SQL se consultan como tablas normales.
     *   Un SP retorna un resultset que no es paginable nativamente por Laravel.
     *
     * NOTA: En un futuro, si se necesitan filtros complejos (por Región, Gerencia, etc.),
     *       se puede crear un SP específico para listados con parámetros de búsqueda.
     */
    public function index()
    {
        $usuarios = DB::table('Vista_Usuarios')
            ->orderBy('Apellido_Paterno', 'asc')
            ->paginate(20);

        return view('admin.usuarios.index', compact('usuarios'));
    }

    /**
     * FORMULARIO DE ALTA ADMINISTRATIVA
     * ══════════════════════════════════
     * SP UTILIZADO: Ninguno — Solo renderiza la vista con los catálogos para los dropdowns.
     *
     * ¿POR QUÉ CARGAR CATÁLOGOS AQUÍ?
     *   El formulario de alta administrativa requiere TODOS los dropdowns
     *   (Régimen, Puesto, CT, Depto, Región, Gerencia, Rol) pre-cargados.
     *   Los catálogos se filtran por Activo=1 para que solo aparezcan opciones válidas.
     */
    public function create()
    {
        $catalogos = $this->cargarCatalogos();

        return view('admin.usuarios.create', compact('catalogos'));
    }

    /**
     * REGISTRAR USUARIO POR ADMIN (ALTA ADMINISTRATIVA)
     * ══════════════════════════════════════════════════
     * SP UTILIZADO: SP_RegistrarUsuarioPorAdmin (20 parámetros)
     *
     * FLUJO:
     * 1. CAPA LARAVEL: Valida formato (campos obligatorios, tipos, longitudes).
     * 2. Laravel hashea la contraseña con Bcrypt.
     * 3. CAPA SP: Ejecuta SP_RegistrarUsuarioPorAdmin que valida:
     *    - Auditoría (¿Quién lo está creando?)
     *    - Vigencia de catálogos (¿El Puesto/Depto/CT sigue activo?)
     *    - Anti-duplicados (Ficha, Email, Huella Humana)
     *    - Integridad atómica (INSERT en 2 tablas o ROLLBACK)
     * 4. Si todo pasa → redirect con éxito.
     * 5. Si falla SP → atrapa SIGNAL, parsea código, manda alerta al front.
     *
     * DIFERENCIA VS REGISTRO PÚBLICO:
     *   - Aquí TODOS los campos de adscripción son OBLIGATORIOS.
     *   - Se asigna un Rol específico (no default 4=Participante).
     *   - Se registra quién creó al usuario (Auditoría con _Id_Admin_Ejecutor).
     *   - Se puede subir foto de perfil al momento del alta.
     */
    public function store(Request $request)
    {
        /* CAPA 1: VALIDACIÓN LARAVEL (Formato y UX) */
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            'password'          => ['required', 'string', 'min:8', 'confirmed'],
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['required', 'integer', 'min:1'],
            'id_centro_trabajo' => ['required', 'integer', 'min:1'],
            'id_departamento'   => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['required', 'integer', 'min:1'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ], [
            'ficha.required'             => 'La Ficha es obligatoria.',
            'email.required'             => 'El Correo es obligatorio.',
            'email.email'                => 'El formato del correo no es válido.',
            'password.required'          => 'La Contraseña es obligatoria.',
            'password.min'               => 'La Contraseña debe tener al menos 8 caracteres.',
            'password.confirmed'         => 'Las contraseñas no coinciden.',
            'nombre.required'            => 'El Nombre es obligatorio.',
            'apellido_paterno.required'  => 'El Apellido Paterno es obligatorio.',
            'apellido_materno.required'  => 'El Apellido Materno es obligatorio.',
            'fecha_nacimiento.required'  => 'La Fecha de Nacimiento es obligatoria.',
            'fecha_ingreso.required'     => 'La Fecha de Ingreso es obligatoria.',
            'id_rol.required'            => 'El Rol es obligatorio.',
            'id_regimen.required'        => 'El Régimen es obligatorio.',
            'id_puesto.required'         => 'El Puesto es obligatorio.',
            'id_centro_trabajo.required' => 'El Centro de Trabajo es obligatorio.',
            'id_departamento.required'   => 'El Departamento es obligatorio.',
            'id_region.required'         => 'La Región es obligatoria.',
            'id_gerencia.required'       => 'La Gerencia es obligatoria.',
        ]);

        /* CAPA 2: LLAMADA AL STORED PROCEDURE */
        try {
            $resultado = DB::select('CALL SP_RegistrarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                          // _Id_Admin_Ejecutor (Auditoría)
                $request->ficha,                     // _Ficha
                $request->foto_perfil,               // _Url_Foto (puede ser NULL)
                $request->nombre,                    // _Nombre
                $request->apellido_paterno,          // _Apellido_Paterno
                $request->apellido_materno,          // _Apellido_Materno
                $request->fecha_nacimiento,          // _Fecha_Nacimiento
                $request->fecha_ingreso,             // _Fecha_Ingreso
                $request->email,                     // _Email
                Hash::make($request->password),      // _Contrasena (Bcrypt hash)
                $request->id_rol,                    // _Id_Rol
                $request->id_regimen,                // _Id_Regimen
                $request->id_puesto,                 // _Id_Puesto
                $request->id_centro_trabajo,         // _Id_CentroTrabajo
                $request->id_departamento,           // _Id_Departamento
                $request->id_region,                 // _Id_Region
                $request->id_gerencia,               // _Id_Gerencia
                $request->nivel,                     // _Nivel
                $request->clasificacion,             // _Clasificacion
            ]);

            return redirect()->route('usuarios.index')
                ->with('success', 'Colaborador registrado exitosamente. ID: ' . $resultado[0]->Id_Usuario);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * VER DETALLE DE USUARIO (MODAL / VISTA DE AUDITORÍA)
     * ════════════════════════════════════════════════════
     * SP UTILIZADO: SP_ConsultarUsuarioPorAdmin
     *
     * Retorna la "Radiografía Técnica Completa" del usuario:
     *   - Identidad, Credenciales, Foto
     *   - Datos Personales completos
     *   - Adscripción con IDs de cascada (País→Estado→Municipio→CT)
     *   - Jerarquía organizacional (Dirección→Subdirección→Gerencia)
     *   - Auditoría (Quién creó, quién modificó, cuándo)
     *   - Seguridad (Rol, Estatus Activo/Inactivo)
     */
    public function show(string $id)
    {
        try {
            $usuario = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$id]);

            if (empty($usuario)) {
                return redirect()->route('usuarios.index')
                    ->with('danger', 'El usuario solicitado no existe.');
            }

            return view('admin.usuarios.show', [
                'usuario' => $usuario[0],
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('usuarios.index')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * FORMULARIO DE EDICIÓN (ADMIN)
     * ═════════════════════════════
     * SP UTILIZADO: SP_ConsultarUsuarioPorAdmin (para pre-llenar el formulario)
     *
     * FLUJO:
     * 1. Llama al SP para obtener los datos actuales del usuario.
     * 2. Carga todos los catálogos activos para los dropdowns.
     * 3. Manda ambos a la vista para el "Data Binding" automático.
     *
     * Los IDs de cascada (Id_Pais_CT, Id_Estado_CT, Id_Municipio_CT) permiten
     * que los selectores dependientes se pre-carguen correctamente en el front.
     */
    public function edit(string $id)
    {
        try {
            $usuario = DB::select('CALL SP_ConsultarUsuarioPorAdmin(?)', [$id]);

            if (empty($usuario)) {
                return redirect()->route('usuarios.index')
                    ->with('danger', 'El usuario solicitado no existe.');
            }

            $catalogos = $this->cargarCatalogos();

            return view('admin.usuarios.edit', [
                'usuario'   => $usuario[0],
                'catalogos' => $catalogos,
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect()->route('usuarios.index')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * ACTUALIZAR USUARIO POR ADMIN
     * ════════════════════════════
     * SP UTILIZADO: SP_EditarUsuarioPorAdmin (21 parámetros)
     *
     * CARACTERÍSTICAS EXCLUSIVAS DEL ADMIN:
     *   - Puede cambiar Email (el usuario normal no puede desde su perfil).
     *   - Puede cambiar Rol (escalar/degradar privilegios).
     *   - Puede resetear Contraseña sin conocer la anterior.
     *   - Puede modificar TODOS los campos de adscripción.
     *
     * CONTRASEÑA CONDICIONAL:
     *   Si el campo 'nueva_password' viene vacío → el SP preserva la contraseña actual.
     *   Si tiene valor → se hashea con Bcrypt y se envía al SP para sobrescribir.
     *
     * IDEMPOTENCIA:
     *   El SP tiene un "Motor de Detección de Cambios" que compara campo por campo.
     *   Si no hay cambios reales, retorna 'SIN_CAMBIOS' sin tocar disco.
     */
    public function update(Request $request, string $id)
    {
        /* CAPA 1: VALIDACIÓN LARAVEL */
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            'nueva_password'    => ['nullable', 'string', 'min:8'],
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_rol'            => ['required', 'integer', 'min:1'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        /* Contraseña Condicional:
           Si el admin escribió una nueva contraseña → hasheamos.
           Si dejó el campo vacío → mandamos NULL al SP (COALESCE preservará la actual). */
        $passwordHasheado = $request->filled('nueva_password')
            ? Hash::make($request->nueva_password)
            : null;

        /* CAPA 2: LLAMADA AL STORED PROCEDURE */
        try {
            $resultado = DB::select('CALL SP_EditarUsuarioPorAdmin(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                          // _Id_Admin_Ejecutor
                $id,                                 // _Id_Usuario_Objetivo
                $request->ficha,                     // _Ficha
                $request->foto_perfil,               // _Url_Foto
                $request->nombre,                    // _Nombre
                $request->apellido_paterno,          // _Apellido_Paterno
                $request->apellido_materno,          // _Apellido_Materno
                $request->fecha_nacimiento,          // _Fecha_Nacimiento
                $request->fecha_ingreso,             // _Fecha_Ingreso
                $request->email,                     // _Email
                $passwordHasheado,                   // _Nueva_Contrasena (NULL si no cambió)
                $request->id_rol,                    // _Id_Rol
                $request->id_regimen,                // _Id_Regimen
                $request->id_puesto ?? 0,            // _Id_Puesto (0 si no seleccionó → SP lo convierte a NULL)
                $request->id_centro_trabajo ?? 0,    // _Id_CentroTrabajo
                $request->id_departamento ?? 0,      // _Id_Departamento
                $request->id_region,                 // _Id_Region
                $request->id_gerencia ?? 0,          // _Id_Gerencia
                $request->nivel,                     // _Nivel
                $request->clasificacion,             // _Clasificacion
            ]);

            /* Determinar tipo de éxito según la Accion retornada por el SP */
            $accion = $resultado[0]->Accion ?? 'ACTUALIZADA';
            $mensaje = $resultado[0]->Mensaje ?? 'Usuario actualizado.';

            if ($accion === 'SIN_CAMBIOS') {
                return redirect()->route('usuarios.edit', $id)
                    ->with('info', $mensaje);
            }

            return redirect()->route('usuarios.show', $id)
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * ELIMINAR USUARIO DEFINITIVAMENTE (HARD DELETE)
     * ══════════════════════════════════════════════
     * SP UTILIZADO: SP_EliminarUsuarioDefinitivamente
     *
     * ⚠️  ACCIÓN IRREVERSIBLE — SOLO PARA CORRECCIÓN DE ERRORES INMEDIATOS.
     *
     * ANÁLISIS FORENSE PREVIO (ejecutado por el SP):
     *   1. Anti-Suicidio: El admin no puede eliminarse a sí mismo.
     *   2. Huella de Instructor: Si tiene cursos asignados (pasados o futuros) → BLOQUEO.
     *   3. Huella Académica: Si tiene registros como participante → BLOQUEO.
     *   4. Si está limpio → DELETE en Usuarios + Info_Personal (cascada manual).
     *
     * NOTA LEGAL:
     *   Para gestionar bajas laborales (despido, renuncia, jubilación) se debe usar
     *   SP_CambiarEstatusUsuario (baja lógica), NUNCA este método.
     */
    public function destroy(string $id)
    {
        try {
            $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
                Auth::id(),  // _Id_Admin_Ejecutor
                $id,         // _Id_Usuario_Objetivo
            ]);

            $mensaje = $resultado[0]->Mensaje ?? 'Usuario eliminado.';

            return redirect()->route('usuarios.index')
                ->with('success', $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return redirect()->route('usuarios.index')
                ->with($tipoAlerta, $mensajeSP);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 2: MÉTODOS DE PERFIL PROPIO (USUARIO AUTENTICADO)
       Estos métodos son para que CUALQUIER usuario gestione su propia información.
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * VER MI PERFIL
     * ═════════════
     * SP UTILIZADO: SP_ConsultarPerfilPropio
     *
     * Retorna el expediente del usuario autenticado con estrategia "Lean Payload":
     *   - Solo IDs de catálogos (el front ya tiene los textos en sus dropdowns).
     *   - IDs de cascada geográfica (País→Estado→Municipio→CT/Depto).
     *   - IDs de cascada organizacional (Dirección→Subdirección→Gerencia).
     *   - LEFT JOINs para robustez (datos visibles aunque haya catálogos rotos).
     */
    public function perfil()
    {
        try {
            $perfil = DB::select('CALL SP_ConsultarPerfilPropio(?)', [Auth::id()]);

            if (empty($perfil)) {
                return redirect('/dashboard')
                    ->with('danger', 'No se pudo cargar tu perfil.');
            }

            $catalogos = $this->cargarCatalogos();

            return view('usuario.perfil', [
                'perfil'    => $perfil[0],
                'catalogos' => $catalogos,
            ]);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            return redirect('/dashboard')
                ->with('danger', $mensajeSP);
        }
    }

    /**
     * ACTUALIZAR MI PERFIL
     * ════════════════════
     * SP UTILIZADO: SP_EditarPerfilPropio (16 parámetros)
     *
     * RESTRICCIONES VS EDICIÓN ADMIN:
     *   - El usuario NO puede cambiar su Email aquí (se delega a actualizarCredenciales).
     *   - El usuario NO puede cambiar su Rol (solo el Admin puede escalar privilegios).
     *   - Régimen y Región son OBLIGATORIOS; Puesto, CT, Depto, Gerencia son OPCIONALES.
     *
     * PROTECCIONES DEL SP:
     *   - Bloqueo pesimista (FOR UPDATE) contra edición concurrente.
     *   - Detección de cambios (idempotencia): si no cambió nada → 'SIN_CAMBIOS'.
     *   - Anti-colisión de Ficha: si cambió la Ficha, verifica que no exista en otro usuario.
     *   - Anti-zombie: valida vigencia de todos los catálogos seleccionados.
     */
    public function actualizarPerfil(Request $request)
    {
        /* CAPA 1: VALIDACIÓN LARAVEL */
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
            'id_regimen'        => ['required', 'integer', 'min:1'],
            'id_region'         => ['required', 'integer', 'min:1'],
            'id_puesto'         => ['nullable', 'integer'],
            'id_centro_trabajo' => ['nullable', 'integer'],
            'id_departamento'   => ['nullable', 'integer'],
            'id_gerencia'       => ['nullable', 'integer'],
            'nivel'             => ['nullable', 'string', 'max:50'],
            'clasificacion'     => ['nullable', 'string', 'max:100'],
            'foto_perfil'       => ['nullable', 'string', 'max:255'],
        ]);

        /* CAPA 2: LLAMADA AL STORED PROCEDURE */
        try {
            $resultado = DB::select('CALL SP_EditarPerfilPropio(?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)', [
                Auth::id(),                          // _Id_Usuario_Sesion
                $request->ficha,                     // _Ficha
                $request->foto_perfil,               // _Url_Foto
                $request->nombre,                    // _Nombre
                $request->apellido_paterno,          // _Apellido_Paterno
                $request->apellido_materno,          // _Apellido_Materno
                $request->fecha_nacimiento,          // _Fecha_Nacimiento
                $request->fecha_ingreso,             // _Fecha_Ingreso
                $request->id_regimen,                // _Id_Regimen
                $request->id_puesto ?? 0,            // _Id_Puesto (0 → SP convierte a NULL)
                $request->id_centro_trabajo ?? 0,    // _Id_CentroTrabajo
                $request->id_departamento ?? 0,      // _Id_Departamento
                $request->id_region,                 // _Id_Region
                $request->id_gerencia ?? 0,          // _Id_Gerencia
                $request->nivel,                     // _Nivel
                $request->clasificacion,             // _Clasificacion
            ]);

            $accion = $resultado[0]->Accion ?? 'ACTUALIZADA';
            $mensaje = $resultado[0]->Mensaje ?? 'Perfil actualizado.';

            $tipoFlash = ($accion === 'SIN_CAMBIOS') ? 'info' : 'success';

            return redirect()->route('perfil')
                ->with($tipoFlash, $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()->withInput()->with($tipoAlerta, $mensajeSP);
        }
    }

    /**
     * ACTUALIZAR MIS CREDENCIALES (EMAIL Y/O CONTRASEÑA)
     * ══════════════════════════════════════════════════
     * SP UTILIZADO: SP_ActualizarCredencialesPropio
     *
     * FLUJO DE SEGURIDAD:
     *   1. El usuario escribe su CONTRASEÑA ACTUAL como verificación de identidad.
     *   2. Laravel verifica Hash::check(actual vs BD) ANTES de llamar al SP.
     *   3. Si pasa → se manda el nuevo Email y/o nueva Contraseña (hasheada) al SP.
     *   4. El SP valida unicidad de Email, detecta cambios, y persiste.
     *
     * ¿POR QUÉ LA VERIFICACIÓN ES EN LARAVEL Y NO EN EL SP?
     *   Porque el SP recibe el hash de la contraseña, no el texto plano.
     *   La comparación bcrypt (Hash::check) solo puede hacerla PHP con la librería password_verify.
     *   MariaDB no tiene una función nativa para comparar hashes bcrypt.
     *
     * FLEXIBILIDAD:
     *   - Solo Email nuevo → se actualiza Email, Contraseña se preserva.
     *   - Solo Contraseña nueva → se actualiza Contraseña, Email se preserva.
     *   - Ambos → se actualizan ambos.
     */
    public function actualizarCredenciales(Request $request)
    {
        /* CAPA 1: VALIDACIÓN LARAVEL */
        $request->validate([
            'password_actual'   => ['required', 'string'],
            'nuevo_email'       => ['nullable', 'string', 'email', 'max:255'],
            'nueva_password'    => ['nullable', 'string', 'min:8', 'confirmed'],
        ], [
            'password_actual.required'  => 'Debes escribir tu contraseña actual para confirmar los cambios.',
            'nuevo_email.email'         => 'El formato del nuevo correo no es válido.',
            'nueva_password.min'        => 'La nueva contraseña debe tener al menos 8 caracteres.',
            'nueva_password.confirmed'  => 'Las nuevas contraseñas no coinciden.',
        ]);

        /* Debe proporcionar al menos un dato nuevo */
        if (!$request->filled('nuevo_email') && !$request->filled('nueva_password')) {
            return back()->with('danger', 'Debe proporcionar al menos un dato para actualizar (Email o Contraseña).');
        }

        /* VERIFICACIÓN DE IDENTIDAD:
           Comparamos la contraseña actual escrita por el usuario contra el hash en BD.
           Esto es OBLIGATORIO antes de permitir cualquier cambio de seguridad. */
        $usuario = Auth::user();

        if (!Hash::check($request->password_actual, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'password_actual' => 'La contraseña actual es incorrecta.',
            ]);
        }

        /* Preparar datos para el SP:
           Si hay nueva contraseña → hashearla.
           Si no → mandar NULL (el SP la preservará con COALESCE). */
        $nuevoEmailLimpio = $request->filled('nuevo_email') ? $request->nuevo_email : null;
        $nuevaPassHasheada = $request->filled('nueva_password') ? Hash::make($request->nueva_password) : null;

        /* CAPA 2: LLAMADA AL STORED PROCEDURE */
        try {
            $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
                Auth::id(),           // _Id_Usuario_Sesion
                $nuevoEmailLimpio,    // _Nuevo_Email (NULL si no cambió)
                $nuevaPassHasheada,   // _Nueva_Contrasena (NULL si no cambió)
            ]);

            $accion = $resultado[0]->Accion ?? 'ACTUALIZADA';
            $mensaje = $resultado[0]->Mensaje ?? 'Credenciales actualizadas.';

            $tipoFlash = ($accion === 'SIN_CAMBIOS') ? 'info' : 'success';

            return redirect()->route('perfil')
                ->with($tipoFlash, $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()->with($tipoAlerta, $mensajeSP);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 3: GESTIÓN DE ESTATUS (ADMIN)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * ACTIVAR / DESACTIVAR USUARIO (BAJA LÓGICA)
     * ═══════════════════════════════════════════
     * SP UTILIZADO: SP_CambiarEstatusUsuario
     *
     * PROTECCIONES DEL SP:
     *   - Anti-Lockout: El admin no puede desactivar su propia cuenta.
     *   - Candado Operativo Dinámico: Si el usuario es INSTRUCTOR de un curso activo → BLOQUEO.
     *   - Candado Académico: Si el usuario es PARTICIPANTE inscrito en un curso activo → BLOQUEO.
     *   - Sincronización en cascada: Desactiva/activa AMBAS tablas (Usuarios + Info_Personal).
     *   - Idempotencia: Si ya tiene el estatus solicitado → 'SIN_CAMBIOS'.
     *
     * CUÁNDO USAR ESTO VS ELIMINAR:
     *   - CambiarEstatus → Despidos, renuncias, jubilaciones, suspensiones temporales.
     *   - EliminarDefinitivamente → SOLO errores de captura inmediatos (usuario duplicado).
     */
    public function cambiarEstatus(Request $request, string $id)
    {
        $request->validate([
            'nuevo_estatus' => ['required', 'integer', 'in:0,1'],
        ]);

        try {
            $resultado = DB::select('CALL SP_CambiarEstatusUsuario(?, ?, ?)', [
                Auth::id(),                  // _Id_Admin_Ejecutor
                $id,                         // _Id_Usuario_Objetivo
                $request->nuevo_estatus,     // _Nuevo_Estatus (1=Activar, 0=Desactivar)
            ]);

            $accion = $resultado[0]->Accion ?? '';
            $mensaje = $resultado[0]->Mensaje ?? 'Estatus actualizado.';

            $tipoFlash = ($accion === 'SIN_CAMBIOS') ? 'info' : 'success';

            return redirect()->route('usuarios.show', $id)
                ->with($tipoFlash, $mensaje);

        } catch (\Illuminate\Database\QueryException $e) {
            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return redirect()->route('usuarios.show', $id)
                ->with($tipoAlerta, $mensajeSP);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 4: LISTADOS PARA DROPDOWNS Y REPORTES
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * LISTAR INSTRUCTORES ACTIVOS (PARA DROPDOWNS DE ASIGNACIÓN)
     * ═════════════════════════════════════════════════════════
     * SP UTILIZADO: SP_ListarInstructoresActivos
     *
     * CONSUMIDO POR: Formularios de Coordinación (asignar instructor a un curso).
     * FILTROS: Solo usuarios Activos + Roles 1 (Admin), 2 (Coord), 3 (Instructor).
     * FORMATO: [{Id_Usuario, Ficha, Nombre_Completo}]
     * RETORNA: JSON para consumo de componentes Vue.js (Select2/Dropdown).
     */
    public function listarInstructoresActivos()
    {
        try {
            $instructores = DB::select('CALL SP_ListarInstructoresActivos()');

            return response()->json($instructores);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'error' => 'Error al cargar la lista de instructores.'
            ], 500);
        }
    }

    /**
     * LISTAR TODOS LOS INSTRUCTORES (HISTORIAL COMPLETO)
     * ══════════════════════════════════════════════════
     * SP UTILIZADO: SP_ListarTodosInstructores_Historial
     *
     * CONSUMIDO POR: Filtros de reportes y dashboards históricos.
     * FILTROS: Roles 1, 2, 3 (SIN filtro de Activo → incluye bajas).
     * ENRIQUECIMIENTO: Los inactivos llevan sufijo " (BAJA/INACTIVO)".
     * FORMATO: [{Id_Usuario, Ficha, Nombre_Completo_Filtro}]
     * RETORNA: JSON para consumo de componentes Vue.js.
     */
    public function listarInstructoresHistorial()
    {
        try {
            $instructores = DB::select('CALL SP_ListarTodosInstructores_Historial()');

            return response()->json($instructores);

        } catch (\Illuminate\Database\QueryException $e) {
            return response()->json([
                'error' => 'Error al cargar el historial de instructores.'
            ], 500);
        }
    }

    /* ========================================================================================
       ████████████████████████████████████████████████████████████████████████████████████████
       SECCIÓN 5: MÉTODOS PRIVADOS (UTILIDADES INTERNAS)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * Carga todos los catálogos activos necesarios para los formularios de usuario.
     *
     * Se usa en: create(), edit(), perfil()
     *
     * ESTRATEGIA:
     *   Cada catálogo se consulta con Activo=1 y se ordena alfabéticamente.
     *   Se retorna como un array asociativo para que la vista Blade pueda iterar cada uno
     *   en su respectivo dropdown: @foreach($catalogos['roles'] as $rol) ...
     *
     * @return array  Array asociativo con las colecciones de cada catálogo.
     */
    private function cargarCatalogos(): array
    {
        return [
            'roles'            => DB::table('Cat_Roles')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'regimenes'        => DB::table('Cat_Regimenes_Trabajo')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'puestos'          => DB::table('Cat_Puestos_Trabajo')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'centros_trabajo'  => DB::table('Cat_Centros_Trabajo')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'departamentos'    => DB::table('Cat_Departamentos')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'regiones'         => DB::table('Cat_Regiones_Trabajo')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
            'gerencias'        => DB::table('Cat_Gerencias_Activos')
                                    ->where('Activo', 1)->orderBy('Nombre')->get(),
        ];
    }

    /**
     * Extrae el mensaje limpio del SIGNAL del Stored Procedure.
     *
     * PROBLEMA:
     *   Laravel envuelve el error SQL en capas de texto:
     *   "SQLSTATE[45000]: <<1644>>: 7 CONFLICTO [409-A]: La Ficha ya está registrada y activa..."
     *
     * SOLUCIÓN:
     *   Buscamos el patrón de nuestros códigos de error personalizados.
     *   Si lo encontramos, extraemos desde ahí.
     *   Si no, retornamos un mensaje genérico amigable.
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

    /**
     * Clasifica el tipo de alerta Bootstrap según el código de error del SP.
     *
     * MAPEO DE CÓDIGOS → ALERTAS BOOTSTRAP:
     *   [409-A] → 'warning'  (amarilla): Duplicado activo, hay acción sugerida.
     *   [409-B] → 'danger'   (roja):     Cuenta bloqueada, requiere admin.
     *   [409]   → 'warning'  (amarilla): Conflicto operativo o concurrencia.
     *   [403]   → 'danger'   (roja):     Permisos/Seguridad denegada.
     *   [400]   → 'danger'   (roja):     Error de validación.
     *   [404]   → 'danger'   (roja):     No encontrado.
     *   Otro    → 'danger'   (roja):     Error inesperado.
     *
     * @param  string  $mensaje  Mensaje limpio del SP.
     * @return string  Tipo de alerta Bootstrap ('warning', 'danger', 'info').
     */
    private function clasificarAlerta(string $mensaje): string
    {
        if (str_contains($mensaje, '409-A')) {
            return 'warning';
        }

        if (str_contains($mensaje, '409-B')) {
            return 'danger';
        }

        /* Conflictos operativos (cursos activos, concurrencia) → Warning */
        if (str_contains($mensaje, 'CONFLICTO OPERATIVO') || str_contains($mensaje, 'CONCURRENCIA')) {
            return 'warning';
        }

        /* Bloqueos de integridad (historial instructor/participante) → Danger */
        if (str_contains($mensaje, 'BLOQUEO')) {
            return 'danger';
        }

        /* Acciones denegadas (anti-lockout, anti-suicidio) → Danger */
        if (str_contains($mensaje, 'DENEGADA')) {
            return 'danger';
        }

        /* 409 genérico → Warning */
        if (str_contains($mensaje, '409')) {
            return 'warning';
        }

        return 'danger';
    }
}
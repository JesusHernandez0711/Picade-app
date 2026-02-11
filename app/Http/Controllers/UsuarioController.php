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

       CASCADAS AJAX (Dropdowns dependientes):
         ⮕ MIGRADO A CatalogoController (reutilizable por todos los módulos).
         Ver: App\Http\Controllers\CatalogoController

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
     */
    public function create()
    {
        $catalogos = $this->cargarCatalogos();

        return view('admin.usuarios.create', compact('catalogos'));
    }

    /**
     * REGISTRAR USUARIO POR ADMIN (ALTA ADMINISTRATIVA)
     * SP UTILIZADO: SP_RegistrarUsuarioPorAdmin (20 parámetros)
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
                $request->foto_perfil,               // _Url_Foto
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
     * SP UTILIZADO: SP_ConsultarUsuarioPorAdmin
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
     * SP UTILIZADO: SP_ConsultarUsuarioPorAdmin (para pre-llenar el formulario)
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
     * SP UTILIZADO: SP_EditarUsuarioPorAdmin (21 parámetros)
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
                $request->id_puesto ?? 0,            // _Id_Puesto (0 → SP convierte a NULL)
                $request->id_centro_trabajo ?? 0,    // _Id_CentroTrabajo
                $request->id_departamento ?? 0,      // _Id_Departamento
                $request->id_region,                 // _Id_Region
                $request->id_gerencia ?? 0,          // _Id_Gerencia
                $request->nivel,                     // _Nivel
                $request->clasificacion,             // _Clasificacion
                $request->foto_perfil,               // _Url_Foto
            ]);

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
     * SP UTILIZADO: SP_EliminarUsuarioDefinitivamente
     * ⚠️  ACCIÓN IRREVERSIBLE — SOLO PARA CORRECCIÓN DE ERRORES INMEDIATOS.
     */
    public function destroy(string $id)
    {
        try {
            $resultado = DB::select('CALL SP_EliminarUsuarioDefinitivamente(?, ?)', [
                Auth::id(),
                $id,
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
     * SP UTILIZADO: SP_ConsultarPerfilPropio
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
     * SP UTILIZADO: SP_EditarPerfilPropio (16 parámetros)
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
                Auth::id(),
                $request->ficha,
                $request->foto_perfil,
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
                $request->id_regimen,
                $request->id_puesto ?? 0,
                $request->id_centro_trabajo ?? 0,
                $request->id_departamento ?? 0,
                $request->id_region,
                $request->id_gerencia ?? 0,
                $request->nivel,
                $request->clasificacion,
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
     * SP UTILIZADO: SP_ActualizarCredencialesPropio
     *
     * FLUJO: Verificar password actual en Laravel (Hash::check) → luego llamar SP.
     * MariaDB no puede comparar hashes bcrypt, por eso la verificación es en PHP.
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

        /* VERIFICACIÓN DE IDENTIDAD */
        $usuario = Auth::user();

        if (!Hash::check($request->password_actual, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'password_actual' => 'La contraseña actual es incorrecta.',
            ]);
        }

        $nuevoEmailLimpio = $request->filled('nuevo_email') ? $request->nuevo_email : null;
        $nuevaPassHasheada = $request->filled('nueva_password') ? Hash::make($request->nueva_password) : null;

        /* CAPA 2: LLAMADA AL STORED PROCEDURE */
        try {
            $resultado = DB::select('CALL SP_ActualizarCredencialesPropio(?, ?, ?)', [
                Auth::id(),
                $nuevoEmailLimpio,
                $nuevaPassHasheada,
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
     * SP UTILIZADO: SP_CambiarEstatusUsuario
     */
    public function cambiarEstatus(Request $request, string $id)
    {
        $request->validate([
            'nuevo_estatus' => ['required', 'integer', 'in:0,1'],
        ]);

        try {
            $resultado = DB::select('CALL SP_CambiarEstatusUsuario(?, ?, ?)', [
                Auth::id(),
                $id,
                $request->nuevo_estatus,
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
       SECCIÓN 4: MÉTODOS PRIVADOS (UTILIDADES INTERNAS)
       ████████████████████████████████████████████████████████████████████████████████████████
       ======================================================================================== */

    /**
     * Carga todos los catálogos activos necesarios para los formularios de usuario.
     *
     * Se usa en: create(), edit(), perfil()
     *
     * ESTRATEGIA:
     *   Cada catálogo se consulta mediante su SP de Dropdown dedicado (SP_Listar*Activos).
     *   Los SPs ya aplican filtro Activo=1, ordenamiento alfabético, y proyección mínima
     *   (Id + Codigo/Clave + Nombre). No se duplica lógica en Laravel.
     *
     * CARGA INICIAL vs CASCADA:
     *   Los catálogos aquí son "Entidades Raíz" o independientes que se cargan al abrir el form.
     *   Los catálogos dependientes (Estados, Municipios, Subdirecciones, Gerencias) se cargan
     *   por AJAX vía CatalogoController cuando el usuario selecciona un padre.
     *
     * CONTRATOS DE RETORNO DE CADA SP:
     *   roles           → [{Id_Rol, Codigo, Nombre}]
     *   regimenes       → [{Id_CatRegimen, Codigo, Nombre}]
     *   regiones        → [{Id_CatRegion, Codigo, Nombre}]
     *   puestos         → [{Id_CatPuesto, Codigo, Nombre}]
     *   centros_trabajo → [{Id_CatCT, Codigo, Nombre}]
     *   departamentos   → [{Id_CatDep, Codigo, Nombre}]  (con candado de Municipio padre activo)
     *   paises          → [{Id_Pais, Codigo, Nombre}]     ← RAÍZ de cascada geográfica
     *   direcciones     → [{Id_CatDirecc, Clave, Nombre}] ← RAÍZ de cascada organizacional
     *
     * @return array  Array asociativo con las colecciones de cada catálogo.
     */
    private function cargarCatalogos(): array
    {
        return [
            // ═══ SEGURIDAD ═══
            'roles'            => DB::select('CALL SP_ListarRolesActivos()'),

            // ═══ ADSCRIPCIÓN (Entidades independientes, sin cascada) ═══
            'regimenes'        => DB::select('CALL SP_ListarRegimenesActivos()'),
            'regiones'         => DB::select('CALL SP_ListarRegionesActivas()'),
            'puestos'          => DB::select('CALL SP_ListarPuestosActivos()'),
            'centros_trabajo'  => DB::select('CALL SP_ListarCTActivos()'),
            'departamentos'    => DB::select('CALL SP_ListarDepActivos()'),

            // ═══ CASCADA GEOGRÁFICA (Solo nivel raíz) ═══
            // Hijos: CatalogoController::estadosPorPais() → municipiosPorEstado() [AJAX]
            'paises'           => DB::select('CALL SP_ListarPaisesActivos()'),

            // ═══ CASCADA ORGANIZACIONAL (Solo nivel raíz) ═══
            // Hijos: CatalogoController::subdireccionesPorDireccion() → gerenciasPorSubdireccion() [AJAX]
            'direcciones'      => DB::select('CALL SP_ListarDireccionesActivas()'),
        ];
    }

    /**
     * Extrae el mensaje limpio del SIGNAL del Stored Procedure.
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

        if (str_contains($mensaje, 'CONFLICTO OPERATIVO') || str_contains($mensaje, 'CONCURRENCIA')) {
            return 'warning';
        }

        if (str_contains($mensaje, 'BLOQUEO')) {
            return 'danger';
        }

        if (str_contains($mensaje, 'DENEGADA')) {
            return 'danger';
        }

        if (str_contains($mensaje, '409')) {
            return 'warning';
        }

        return 'danger';
    }
}
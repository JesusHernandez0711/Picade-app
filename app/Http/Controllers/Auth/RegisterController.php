<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;

class RegisterController extends Controller
{
    /**
     * Middleware: Solo usuarios NO autenticados pueden acceder al registro público.
     * Si ya estás logueado, Laravel te redirige automáticamente.
     */
    public function __construct()
    {
        $this->middleware('guest');
    }

    /**
     * Muestra el formulario de registro público.
     * Este formulario solicita los datos mínimos (sin perfil laboral completo).
     * El perfil completo solo lo llena un Admin vía SP_RegistrarUsuarioPorAdmin.
     */
    public function showRegistrationForm()
    {
        return view('auth.register');
    }

    /**
     * Procesa el registro público de un nuevo usuario.
     *
     * ARQUITECTURA DE DOBLE VALIDACIÓN:
     * ─────────────────────────────────
     * CAPA 1 — LARAVEL (Validación de formato y UX):
     *   Verifica tipos de dato, longitudes, formato de email, que las contraseñas coincidan.
     *   Si falla aquí, regresa al form con errores inline de Bootstrap (rápido, sin tocar BD).
     *
     * CAPA 2 — STORED PROCEDURE (Validación de negocio):
     *   SP_RegistrarUsuarioNuevo ejecuta las reglas pesadas:
     *   - Anti-Duplicados: Ficha, Email, Huella Humana (Nombre+Apellidos+FechaNac).
     *   - Anti-Paradoja Temporal: Fecha_Ingreso >= Fecha_Nacimiento.
     *   - Restricción de Edad: Mayor de 18 años.
     *   - Control de Concurrencia: Handler 1062 para inserciones simultáneas.
     *   - Auditoría Recursiva: Created_By = el propio usuario recién creado.
     *   Si falla aquí, el SP lanza un SIGNAL con mensaje descriptivo que atrapamos.
     *
     * ¿POR QUÉ VALIDAR EN AMBOS LADOS?
     *   Laravel atrapa errores tontos rápido (campo vacío, email malformado) sin ir a BD.
     *   El SP atrapa errores de negocio que solo la BD puede verificar (duplicados, concurrencia).
     *   Resultado: UX rápida + Integridad blindada.
     *
     * FLUJO COMPLETO:
     *   1. Laravel valida formato → Si falla: errores inline en el form.
     *   2. Laravel hashea la contraseña con Bcrypt.
     *   3. Laravel llama al SP_RegistrarUsuarioNuevo con los 8 parámetros.
     *   4. SP valida reglas de negocio → Si falla: SIGNAL con código y mensaje.
     *   5. Laravel atrapa el SIGNAL → Parsea el código → Manda alerta al front.
     *   6. SP inserta en Info_Personal + Usuarios atómicamente.
     *   7. SP retorna {Mensaje, Id_Usuario, Accion='CREADA'}.
     *   8. Laravel loguea automáticamente al usuario y redirige al dashboard.
     */
    public function register(Request $request)
    {
        /* ========================================================================================
           CAPA 1: VALIDACIÓN LARAVEL (Formato y UX)
           Errores aquí regresan al form con mensajes inline de Bootstrap.
           No toca la BD — es instantánea.
           ======================================================================================== */
        $request->validate([
            'ficha'             => ['required', 'string', 'max:50'],
            'email'             => ['required', 'string', 'email', 'max:255'],
            'password'          => ['required', 'string', 'min:8', 'confirmed'],
            'nombre'            => ['required', 'string', 'max:255'],
            'apellido_paterno'  => ['required', 'string', 'max:255'],
            'apellido_materno'  => ['required', 'string', 'max:255'],
            'fecha_nacimiento'  => ['required', 'date'],
            'fecha_ingreso'     => ['required', 'date'],
        ], [
            /* ---------------------------------------------------------------
               MENSAJES PERSONALIZADOS EN ESPAÑOL
               Estos mensajes aparecen debajo de cada campo en el formulario.
               --------------------------------------------------------------- */
            'ficha.required'            => 'La Ficha es obligatoria.',
            'email.required'            => 'El Correo electrónico es obligatorio.',
            'email.email'               => 'El formato del correo no es válido.',
            'password.required'         => 'La contraseña es obligatoria.',
            'password.min'              => 'La contraseña debe tener al menos 8 caracteres.',
            'password.confirmed'        => 'Las contraseñas no coinciden.',
            'nombre.required'           => 'El Nombre es obligatorio.',
            'apellido_paterno.required' => 'El Apellido Paterno es obligatorio.',
            'apellido_materno.required' => 'El Apellido Materno es obligatorio.',
            'fecha_nacimiento.required' => 'La Fecha de Nacimiento es obligatoria.',
            'fecha_nacimiento.date'     => 'La Fecha de Nacimiento no es válida.',
            'fecha_ingreso.required'    => 'La Fecha de Ingreso es obligatoria.',
            'fecha_ingreso.date'        => 'La Fecha de Ingreso no es válida.',
        ]);

        /* ========================================================================================
           CAPA 2: LLAMADA AL STORED PROCEDURE (Lógica de Negocio)
           
           SP_RegistrarUsuarioNuevo recibe 8 parámetros:
             1. _Ficha            → Identificador corporativo (UNIQUE)
             2. _Email            → Correo institucional (UNIQUE)
             3. _Contrasena       → Hash Bcrypt generado por Laravel (NUNCA texto plano)
             4. _Nombre           → Nombre(s) de pila
             5. _Apellido_Paterno → Primer apellido
             6. _Apellido_Materno → Segundo apellido
             7. _Fecha_Nacimiento → Para validar edad (+18) y Huella Humana
             8. _Fecha_Ingreso    → Para cálculo de antigüedad
           
           El SP puede lanzar SIGNAL con estos códigos:
             [400]   → Validación fallida (campos vacíos, paradoja temporal, menor de edad)
             [409-A] → Duplicado ACTIVO (Ficha, Email o Huella Humana ya existe y está activo)
             [409-B] → Duplicado INACTIVO (existe pero cuenta desactivada, contactar admin)
             [409]   → Concurrencia (otro usuario registró los mismos datos al mismo tiempo)
           ======================================================================================== */
        try {
            $resultado = DB::select('CALL SP_RegistrarUsuarioNuevo(?, ?, ?, ?, ?, ?, ?, ?)', [
                $request->ficha,
                $request->email,
                Hash::make($request->password),     // Bcrypt hash — el SP NUNCA recibe texto plano
                $request->nombre,
                $request->apellido_paterno,
                $request->apellido_materno,
                $request->fecha_nacimiento,
                $request->fecha_ingreso,
            ]);

            /* ====================================================================================
               ÉXITO: El SP retornó el resultset {Mensaje, Id_Usuario, Accion='CREADA'}
               
               FLUJO POST-REGISTRO:
               1. Buscamos al usuario recién creado por su ID.
               2. Lo logueamos automáticamente (no lo mandamos al login de nuevo).
               3. Regeneramos la sesión por seguridad (prevenir Session Fixation).
               4. Redirigimos al dashboard según su rol (que por default es 4=Participante).
               ==================================================================================== */
            $idUsuario = $resultado[0]->Id_Usuario;

            // Buscar al usuario recién creado para loguearlo
            $usuario = \App\Models\Usuario::find($idUsuario);

            if ($usuario) {
                Auth::login($usuario);
                $request->session()->regenerate();
            }

            return redirect('/dashboard')
                ->with('success', '¡Bienvenido! Tu cuenta ha sido creada exitosamente.');

        } catch (\Illuminate\Database\QueryException $e) {
            /* ====================================================================================
               ERROR: El SP lanzó un SIGNAL (SQLSTATE 45000)
               
               ESTRATEGIA DE PARSEO:
               El mensaje del SIGNAL viene en $e->getMessage() con este formato:
                 "SQLSTATE[45000]: <<1644>>: 7 CONFLICTO [409-A]: La Ficha ya está registrada..."
               
               Extraemos el mensaje limpio (después del último ":") y detectamos el código
               [409-A], [409-B], [400] o [409] para decidir qué tipo de alerta mostrar.
               
               MAPEO DE CÓDIGOS A ALERTAS FRONT:
                 [409-A] → Alerta WARNING  (amarilla): Duplicado activo, sugerir recuperar contraseña.
                 [409-B] → Alerta DANGER   (roja):     Cuenta desactivada, contactar administrador.
                 [400]   → Alerta DANGER   (roja):     Error de validación (fecha, edad, campos).
                 [409]   → Alerta WARNING  (amarilla): Concurrencia, pedir que reintente.
                 Otro    → Alerta DANGER   (roja):     Error técnico inesperado.
               ==================================================================================== */

            $mensajeSP = $this->extraerMensajeSP($e->getMessage());
            $tipoAlerta = $this->clasificarAlerta($mensajeSP);

            return back()
                ->withInput()
                ->with($tipoAlerta, $mensajeSP);
        }
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
        // Buscar nuestros patrones de error: ERROR DE..., CONFLICTO..., etc.
        if (preg_match('/(ERROR DE .+|CONFLICTO .+|ERROR .+)/i', $mensajeCompleto, $matches)) {
            // Limpiar posibles caracteres residuales del driver SQL
            return rtrim($matches[1], ' .)');
        }

        // Fallback: Si no pudimos parsear, mensaje genérico (no exponer errores SQL al usuario)
        return 'Ocurrió un error al procesar el registro. Intente nuevamente.';
    }

    /**
     * Clasifica el tipo de alerta Bootstrap según el código de error del SP.
     *
     * MAPEO:
     *   [409-A] → 'warning'  : Duplicado activo, acción sugerida (recuperar contraseña).
     *   [409-B] → 'danger'   : Cuenta bloqueada, requiere intervención del admin.
     *   [409]   → 'warning'  : Concurrencia, acción sugerida (reintentar).
     *   [400]   → 'danger'   : Error de validación de datos.
     *   [403]   → 'danger'   : Error de auditoría/permisos.
     *   Otro    → 'danger'   : Error inesperado.
     *
     * Estos valores ('warning', 'danger') corresponden directamente a las clases
     * de Bootstrap: alert-warning (amarilla), alert-danger (roja).
     * En la vista Blade se usa: @if(session('warning')) o @if(session('danger')).
     *
     * @param  string  $mensaje  El mensaje ya limpio del SP.
     * @return string  El tipo de alerta de Bootstrap ('warning' o 'danger').
     */
    private function clasificarAlerta(string $mensaje): string
    {
        // [409-A]: Duplicado activo → Warning (hay acción que el usuario puede tomar)
        if (str_contains($mensaje, '409-A')) {
            return 'warning';
        }

        // [409-B]: Cuenta desactivada → Danger (requiere intervención externa)
        if (str_contains($mensaje, '409-B')) {
            return 'danger';
        }

        // [409] sin A/B: Concurrencia → Warning (puede reintentar)
        if (str_contains($mensaje, '409')) {
            return 'warning';
        }

        // Todo lo demás: [400], [403], errores técnicos → Danger
        return 'danger';
    }
}
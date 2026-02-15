<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;

class LoginController extends Controller
{
    /**
     * Middleware: Solo usuarios NO autenticados pueden ver login/register.
     * Usuarios YA autenticados son redirigidos automáticamente.
     * Excepción: logout siempre debe estar accesible para usuarios autenticados.
     */
    public function __construct()
    {
        $this->middleware('guest')->except('logout');
    }

    /**
     * Muestra el formulario de login.
     * La vista Blade maneja el fondo (imagen webp) directamente en su CSS.
     */
    public function showLoginForm()
    {
        return view('auth.login');
    }

    /**
     * Procesa la autenticación del usuario.
     *
     * FLUJO (3 CAPAS DE VERIFICACIÓN):
     * 1. Valida que los campos requeridos vengan llenos.
     * 2. Detecta automáticamente si el usuario escribió un Email o una Ficha
     *    usando filter_var(FILTER_VALIDATE_EMAIL).
     * 3. Busca al usuario en la BD por Email o Ficha (sin verificar password aún).
     * 4. CAPA 1 - EXISTENCIA: Si no existe -> error genérico.
     * 5. CAPA 2 - ESTATUS: Si existe pero Activo=0 -> mensaje específico
     *    indicando que su cuenta está desactivada y debe contactar al admin.
     * 6. CAPA 3 - CONTRASEÑA: Si existe y está activo, verifica el hash.
     *    Si el hash no coincide -> error genérico (no revelamos que la cuenta sí existe).
     * 7. Si todo pasa: regenera sesión y redirige según el rol.
     */
    /*public function login(Request $request)
    {
        // 1. Validación básica de entrada
        $request->validate([
            'credencial' => ['required', 'string'],
            'password'   => ['required', 'string'],
        ], [
            // Aquí definimos los mensajes manualmente
            'credencial.required' => 'El campo usuario o ficha es obligatorio.',
            'password.required'   => 'La contraseña es obligatoria.',
        ]);

        // 2. Detección automática: ¿Email o Ficha?
        //    Si pasa el filtro de email -> busca en columna 'Email'
        //    Si no pasa               -> busca en columna 'Ficha'
        $campo = filter_var($request->credencial, FILTER_VALIDATE_EMAIL)
            ? 'Email'
            : 'Ficha';

        // 3. Buscar al usuario en BD (sin verificar contraseña aún)
        //    Esto nos permite diferenciar entre "no existe" y "está desactivado"
        $usuario = \App\Models\Usuario::where($campo, $request->credencial)->first();

        // 4. CAPA 1: ¿Existe el usuario?
        //    Mensaje genérico por seguridad: no revelamos si la cuenta existe o no
        if (!$usuario) {
            return back()->withErrors([
                'credencial' => 'Credenciales incorrectas.',
            ])->onlyInput('credencial');
        }

        // 5. CAPA 2: ¿Está activo?
        //    Si la cuenta fue desactivada por un Admin (SP_CambiarEstatusUsuario
        //    puso Activo=0), mostramos un mensaje específico para que el usuario
        //    sepa exactamente qué hacer y a quién contactar.
        if (!$usuario->Activo) {
            return back()->withErrors([
                'credencial' => 'Su cuenta ha sido desactivada. Contacte al administrador del sistema para reactivar su acceso.',
            ])->onlyInput('credencial');
        }

        // 6. CAPA 3: ¿La contraseña es correcta?
        //    Hash::check() compara el texto plano contra el hash bcrypt
        //    almacenado en la columna 'Contraseña' (vía getAuthPassword() del modelo).
        //    Mensaje genérico: no revelamos que la cuenta sí existe.
        // 6. CAPA 3: Verificación Híbrida (Hash vs Texto Plano)
        $passwordBd = $usuario->getAuthPassword(); // La contraseña que está en la base de datos
        $esValido = false;
        $requiereEncriptar = false;

        // --- EL ESCUDO ---
        // Verificamos si parece un hash (los hashes de Laravel siempre empiezan con $)
        $esHashValido = !empty($passwordBd) && str_starts_with($passwordBd, '$');

        // A) INTENTO 1: ¿Es un Hash seguro (Bcrypt)?
        // Esto es lo estándar. Si ya está encriptada, entra aquí.
        if (Hash::check($request->password, $passwordBd)) {
            $esValido = true;
            // Verificamos si el algoritmo necesita actualización (mantenimiento interno)
            if (Hash::needsRehash($passwordBd)) {
                $requiereEncriptar = true;
            }
        } 
        // B) INTENTO 2: ¿Es texto plano (Legacy/Antiguo)?
        // AQUÍ ESTÁ LA SOLUCIÓN AL ERROR: Comparamos el texto tal cual.
        // Si la contraseña en BD es "Amorcito51." y el usuario escribió "Amorcito51.", entra.
        elseif ($request->password === $passwordBd) {
            $esValido = true;
            $requiereEncriptar = true; // ¡IMPORTANTE! Marcar para encriptar inmediatamente.
        }

        // Si fallaron ambos intentos, adiós.
        if (!$esValido) {
            return back()->withErrors([
                'credencial' => 'Credenciales incorrectas.',
            ])->onlyInput('credencial');
        }

        // 7. AUTO-MIGRACIÓN DE SEGURIDAD
        // Si detectamos que era texto plano (Intento 2), la encriptamos AHORA MISMO.
        // Así, la próxima vez entrará por el Intento 1 y ya será seguro.
        if ($requiereEncriptar) {
            $usuario->Contraseña = Hash::make($request->password);
            $usuario->save(); 
        }

        // 8. TODO PASÓ: Autenticar y regenerar sesión (Igual que antes)
        $remember = $request->boolean('recordar');
        Auth::login($usuario, $remember);
        $request->session()->regenerate();

        return redirect()->intended('/dashboard');

        // 7. TODO PASÓ: Autenticar manualmente y regenerar sesión
        //    Auth::login() registra al usuario en la sesión de Laravel.
        //    session()->regenerate() previene Session Fixation Attack.
        $remember = $request->boolean('recordar');
        Auth::login($usuario, $remember);
        $request->session()->regenerate();

        // 8. Redirigir según el rol del usuario autenticado
        //return redirect()->intended($this->rutaPorRol());
        // 8. REDIRECCIÓN MAESTRA (Aquí estaba tu error de sintaxis)
        // Simplemente redirigimos a /dashboard. El DashboardController se encarga del resto.
        return redirect()->intended('/dashboard');
    }*/

/**
     * Procesa la autenticación del usuario.
     *
     * FLUJO DE VERIFICACIÓN (ESTÁNDAR PLATINUM FORENSIC):
     * 1. VALIDACIÓN: Integridad de campos requeridos.
     * 2. DETECCIÓN: Identificación de canal (Email vs Ficha).
     * 3. BÚSQUEDA: Recuperación de registro en BD (Usuarios).
     * 4. CAPA 1 (EXISTENCIA): Verificación de presencia del registro.
     * 5. CAPA 2 (ESTATUS): Validación de bit de actividad (Baja lógica).
     * 6. CAPA 3 (AUTENTICACIÓN HÍBRIDA): 
     * A) Verificación de Texto Plano (Legacy): Prioritaria para evitar excepciones de motor Hash.
     * B) Verificación de Hash (Bcrypt): Procesamiento estándar de Laravel.
     * 7. AUTO-MIGRACIÓN: Encriptación inmediata de credenciales legacy tras éxito.
     * 8. SESIÓN: Autenticación de estado, regeneración de ID y redirección maestra.
     */
    public function login(Request $request)
    {
        // 1. Validación básica de entrada con mensajes en español
        $request->validate([
            'credencial' => ['required', 'string'],
            'password'   => ['required', 'string'],
        ], [
            'credencial.required' => 'El campo usuario o ficha es obligatorio.',
            'password.required'   => 'La contraseña es obligatoria.',
        ]);

        // 2. Detección automática de canal de acceso
        $campo = filter_var($request->credencial, FILTER_VALIDATE_EMAIL) ? 'Email' : 'Ficha';

        // 3. Recuperación del modelo de Usuario
        $usuario = \App\Models\Usuario::where($campo, $request->credencial)->first();

        // 4. CAPA 1: Validación de Existencia
        if (!$usuario) {
            return back()->withErrors(['credencial' => 'Credenciales incorrectas.'])->onlyInput('credencial');
        }

        // 5. CAPA 2: Validación de Estatus Activo
        if (!$usuario->Activo) {
            return back()->withErrors([
                'credencial' => 'Su cuenta ha sido desactivada. Contacte al administrador del sistema para reactivar su acceso.'
            ])->onlyInput('credencial');
        }

        // 6. CAPA 3: Verificación Híbrida Blindada
        $passwordBd = $usuario->getAuthPassword(); 
        $esValido = false;
        $requiereEncriptar = false;

        // A) INTENTO 1: Texto Plano (Legacy) 
        // Se evalúa primero para prevenir RuntimeException en motores estrictos de Bcrypt
        if (!empty($passwordBd) && $request->password === $passwordBd) {
            $esValido = true;
            $requiereEncriptar = true; 
        } 
        // B) INTENTO 2: Hash Seguro (Bcrypt)
        // Solo se ejecuta si el valor en BD cumple con el formato de Hash ($)
        elseif (!empty($passwordBd) && str_starts_with($passwordBd, '$')) {
            if (Hash::check($request->password, $passwordBd)) {
                $esValido = true;
                // Verificación de mantenimiento de Hash (Necesidad de Rehash)
                if (Hash::needsRehash($passwordBd)) {
                    $requiereEncriptar = true;
                }
            }
        }

        // Validación final de éxito en autenticación
        if (!$esValido) {
            return back()->withErrors(['credencial' => 'Credenciales incorrectas.'])->onlyInput('credencial');
        }

        // 7. AUTO-MIGRACIÓN DE SEGURIDAD (Transparente al usuario)
        // Convierte el texto plano detectado en un Hash Bcrypt seguro
        if ($requiereEncriptar) {
            $usuario->Contraseña = Hash::make($request->password);
            $usuario->save(); 
        }

        // 8. AUTENTICACIÓN Y PERSISTENCIA DE SESIÓN
        $remember = $request->boolean('recordar');
        Auth::login($usuario, $remember);
        $request->session()->regenerate();

        // Redirección maestra al controlador de Dashboard (Maneja roles internos)
        return redirect()->intended('/dashboard');
    }

    /**
     * Cierra la sesión del usuario.
     *
     * FLUJO:
     * 1. Auth::logout()        -> Desvincula al usuario de la sesión actual.
     * 2. invalidate()          -> Destruye todos los datos de la sesión.
     * 3. regenerateToken()     -> Genera nuevo token CSRF para prevenir ataques.
     */
    public function logout(Request $request)
    {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect('/login');
    }

    /**
     * Determina la ruta de redirección según el rol del usuario autenticado.
     *
     * MAPEO DE ROLES (según Cat_Roles en BD):
     *   Fk_Rol = 1 -> Administrador   -> /admin/dashboard
     *   Fk_Rol = 2 -> Coordinador     -> /coordinador/dashboard
     *   Fk_Rol = 3 -> Instructor      -> /instructor/dashboard
     *   Fk_Rol = 4 -> Participante    -> /dashboard (default)
     *
     * Usa match() de PHP 8 (equivalente a switch pero más limpio y seguro).
     */
    /**private function rutaPorRol(): string
    {
        $rol = Auth::user()->Fk_Rol;

        return match ($rol) {
            1 => '/admin/dashboard',
            2 => '/coordinador/dashboard',
            3 => '/instructor/dashboard',
            default => '/dashboard',
        };
    }**/

        
}
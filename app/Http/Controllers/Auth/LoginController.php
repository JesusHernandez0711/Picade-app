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
    public function login(Request $request)
    {
        // 1. Validación básica de entrada
        $request->validate([
            'credencial' => ['required', 'string'],
            'password'   => ['required', 'string'],
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
        if (!Hash::check($request->password, $usuario->getAuthPassword())) {
            return back()->withErrors([
                'credencial' => 'Credenciales incorrectas.',
            ])->onlyInput('credencial');
        }

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
<?php

namespace App\Http\Controllers\Auth;

use App\Http\Controllers\Controller;
use Illuminate\Foundation\Auth\VerifiesEmails;
use Illuminate\Http\Request;

class VerificationController extends Controller
{
    /*
    |--------------------------------------------------------------------------
    | Email Verification Controller
    |--------------------------------------------------------------------------
    |
    | Este controlador maneja la verificación de correo:
    | 1. Mostrar la vista de "Por favor verifica tu email".
    | 2. Procesar el link cuando el usuario hace clic en el correo.
    | 3. Reenviar el correo si se perdió.
    |
    */

    use VerifiesEmails;

    /**
     * A dónde ir después de verificar exitosamente.
     */
    protected $redirectTo = '/dashboard';

    /**
     * Constructor: Define los middlewares de seguridad.
     */
    public function __construct()
    {
        // Solo usuarios logueados pueden ver esto
        $this->middleware('auth');
        
        // El link del correo debe estar firmado (seguridad criptográfica)
        $this->middleware('signed')->only('verify');
        
        // Limitar reenvíos (6 intentos por minuto)
        $this->middleware('throttle:6,1')->only('verify', 'resend');
    }

    /**
     * Muestra el formulario de verificación.
     * Sobrescribimos para apuntar a nuestra vista personalizada.
     */
    public function show(Request $request)
    {
        // Si ya está verificado, lo mandamos al dashboard directo
        return $request->user()->hasVerifiedEmail()
                        ? redirect($this->redirectPath())
                        : view('auth.verify'); // <--- Nuestra vista blade
    }
}
<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

// 2. Importar el Trait Notifiable
use Illuminate\Notifications\Notifiable;

use Illuminate\Contracts\Auth\MustVerifyEmail; // 1. IMPORTAR ESTO

// 2. AGREGAR 'implements MustVerifyEmail'
class Usuario extends Authenticatable implements MustVerifyEmail
{
    use Notifiable; // ⬅️ 2. CRÍTICO: Esto activa el método notify(). Si falta, falla.
    /**
     * Tabla real en la BD.
     * (Laravel buscaría 'usuarios' por convención)
     */
    protected $table = 'Usuarios';

    /**
     * Primary Key.
     * (Laravel buscaría 'id' por convención)
     */
    protected $primaryKey = 'Id_Usuario';

    /**
     * Desactivar timestamps automáticos.
     * (Tus SPs manejan Fecha_Creacion / Fecha_Actualizacion)
     */
    public $timestamps = false;

    /**
     * Columnas que se pueden asignar masivamente.
     * (Protección contra inyección de campos no deseados)
     */
    protected $fillable = [
        'Ficha',
        'Email',
        'Contraseña',
        'Foto_Perfil_Url',
        'Fk_Id_InfoPersonal',
        'Fk_Rol',
        'Activo',
    ];

    /**
     * Campos ocultos en serialización JSON.
     * (Nunca exponer la contraseña en respuestas API)
     */
    protected $hidden = [
        'Contraseña',
    ];

    /**
     * Le dice a Laravel dónde está el hash de la contraseña.
     * Sin esto, Auth::attempt() busca una columna 'password' que no existe.
     */
    public function getAuthPassword()
    {
        return $this->Contraseña;
    }

    /**
     * [NUEVO] Mapeo para Reset Password:
     * Laravel busca el email en la propiedad ->email (minúscula).
     * Aquí le decimos que use la columna 'Email' (Mayúscula).
     */
    public function getEmailForPasswordReset()
    {
        return $this->Email;
    }

    /**
     * [NUEVO] Para que las notificaciones de correo sepan a qué columna enviar.
     */
    public function routeNotificationForMail($notification)
    {
        return $this->Email;
    }

    /**
     * Relación uno a uno con Info_Personal
     */
    public function infoPersonal()
    {
        // 'Fk_Id_InfoPersonal' es la llave foránea en tu tabla Usuarios
        // 'Id_InfoPersonal' es la llave primaria en la tabla Info_Personal
        return $this->belongsTo(InfoPersonal::class, 'Fk_Id_InfoPersonal', 'Id_InfoPersonal');
    }

    /**
     * Accessor para obtener el nombre completo automáticamente.
     * Uso: $usuario->nombre_completo
     */
    public function getNombreCompletoAttribute()
    {
        if ($this->infoPersonal) {
            return "{$this->infoPersonal->Nombre} {$this->infoPersonal->Apellido_Paterno} {$this->infoPersonal->Apellido_Materno}";
        }
        return "Usuario sin nombre";
    }
}
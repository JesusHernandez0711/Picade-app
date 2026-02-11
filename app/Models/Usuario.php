<?php

namespace App\Models;

use Illuminate\Foundation\Auth\User as Authenticatable;

class Usuario extends Authenticatable
{
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
}

# Pomes de la Sarga · Stock

Aplicación web para controlar la cámara, los mercados, la tienda y el historial de Pomes de la Sarga.

## Arquitectura

- Frontend estático publicado con GitHub Pages.
- Supabase Auth para que Laura y su madre entren con su propia cuenta.
- Supabase Postgres como fuente central de los datos compartidos.
- GitHub Actions/GitHub Pages para publicar actualizaciones del frontend.
- Los cambios de código no deben modificar ni reiniciar las tablas de datos.

## Configuración pendiente

1. Crear un proyecto en Supabase.
2. Ejecutar `supabase/schema.sql` en el SQL Editor.
3. Copiar la URL del proyecto y la clave publicable (anon/publishable) a `config.js`.
4. Crear las cuentas de las dos usuarias en Supabase Auth y desactivar el registro público después.
5. En GitHub, ir a Settings → Pages y elegir GitHub Actions como origen.
6. Comprobar acceso desde ambos móviles antes de registrar stock real.

**Seguridad:** no poner nunca una clave `service_role` o secret key en el frontend. Solo se debe usar la clave publicable, con Row Level Security activada.

## Datos

El stock inicial se crea a cero. El historial de movimientos queda guardado en Supabase y no en el almacenamiento local del navegador. Los cambios de código no borran los datos de la base de datos.

## Publicación

Cada push a `main` puede publicar la web mediante el workflow de GitHub Pages. En móviles se podrá añadir la web a la pantalla de inicio.

# Contribucion

## Flujo

1. Crea una rama desde `main`.
2. Limita el cambio a una responsabilidad.
3. Añade tests unitarios, de integracion o invariantes.
4. Actualiza documentacion y changelog cuando cambie una interfaz.
5. Ejecuta `npm run ci` antes de abrir el pull request.

## Reglas

- Codigo y comentarios de codigo en ingles.
- Documentacion operativa en español.
- Solidity formateado con `forge fmt`.
- Sin secretos, endpoints privados ni datos de usuarios.
- Cambios economicos acompañados de ejemplo numerico e invariante.
- No reduzcas fuzzing ni cobertura para obtener una suite verde.

Las incidencias de seguridad siguen el canal privado descrito en [SECURITY.md](./SECURITY.md).

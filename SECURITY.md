# Política de seguridad

La seguridad de MeridianVaultProtocol incluye los contratos, su configuración y los procesos
operativos que controlan reportes, límites, estrategias y permisos.

## Modelo de seguridad

El protocolo separa custodia, emisión de shares, registro de estrategias, política de
valoración y ejecución operativa. El modelo presupone que:

- el activo ERC-20 configurado respeta su interfaz y precisión declarada;
- las estrategias son adaptadores revisados y registrados por gobierno;
- keeper, allocator, guardian y administrador usan credenciales independientes;
- los parámetros iniciales se revisan antes de aceptar depósitos;
- los operadores publican reportes dentro de las ventanas configuradas;
- las integraciones consultan los límites ERC-4626 inmediatamente antes de operar.

Los componentes externos pueden imponer pausas, límites o ventanas propias. Esos estados
forman parte de la operación del protocolo y deben monitorizarse junto con los eventos del
vault.

## Invariantes esperadas

- Una asignación entre reserva y estrategia conserva los activos administrados.
- La deuda de una estrategia nunca supera su límite configurado.
- La suma de objetivos de asignación no supera 10.000 basis points.
- La cola contiene estrategias registradas y no contiene direcciones repetidas.
- Solo el vault enlazado modifica deuda y reportes del registry.
- Depósitos y mint respetan caps globales, límites por receptor y pausa.
- Retiros y redenciones consumen allowance cuando el caller no es el propietario.
- Las comisiones se transfieren exclusivamente al treasury configurado.
- Los shares virtuales y el redondeo conservador se aplican en todas las conversiones.
- Los cambios de gobierno, pausa y operación requieren el rol correspondiente.

## Validación automatizada

La suite local cubre unidades, integración, fuzzing y propiedades contables:

```bash
forge fmt --check
forge build --sizes
forge test -vvv
```

La validación completa usada en CI está disponible como:

```bash
bash scripts/ci.sh
```

## Dependencias

El código Solidity es autocontenido y no enlaza librerías de contratos externas. Foundry
proporciona compilador, runner de tests y herramientas de formato. GitHub Actions instala una
versión estable de Foundry y Dependabot supervisa las acciones utilizadas por el workflow.

## Versiones soportadas

Mientras el proyecto permanezca antes de su primera versión estable, solo la revisión más
reciente de la rama principal recibe actualizaciones de seguridad. Los commits, forks y
despliegues anteriores deben considerarse no soportados.

## Comunicación responsable

Utiliza un **GitHub Security Advisory privado** del repositorio para comunicar una incidencia.
No incluyas detalles sensibles en un issue público, una discusión, un pull request ni redes
sociales.

El informe debería contener:

- componente y revisión afectados;
- condiciones previas y configuración necesaria;
- descripción del impacto y activos expuestos;
- pasos mínimos para reproducir el comportamiento;
- prueba de concepto, si puede compartirse de forma segura;
- mitigación propuesta, si existe;
- nombre o alias para los agradecimientos, si se desean.

No interactúes con despliegues de terceros ni con fondos reales. Las pruebas deben realizarse
en un entorno local, un fork aislado o una red expresamente autorizada.

## Proceso de respuesta

El equipo intentará:

1. acusar recibo en un máximo de tres días laborables;
2. validar alcance y severidad en un máximo de siete días laborables;
3. acordar con la persona informante una ventana de corrección y divulgación;
4. publicar una actualización una vez que la mitigación pueda aplicarse de forma segura.

Estos plazos son objetivos y pueden variar según la complejidad, dependencias externas o
necesidad de coordinar despliegues.

## Alcance prioritario

Se consideran especialmente relevantes los asuntos que puedan afectar a:

- custodia, depósitos, retiros, redenciones o conversión de shares;
- contabilidad de activos, deuda, reportes, ganancias o pérdidas;
- límites de capacidad y exposición;
- cola de retirada y recuperación de liquidez;
- autenticación, roles, pausas y acciones de emergencia;
- aislamiento entre estrategias;
- precisión numérica, decimales y redondeos;
- reentrancia, disponibilidad y consistencia de estado.

Los errores exclusivamente documentales, las recomendaciones de estilo y los hallazgos que
requieran claves administrativas ya comprometidas normalmente no tienen prioridad, salvo que
demuestren un impacto adicional concreto.

## Recomendaciones para despliegues

- Realizar auditorías independientes antes de aceptar depósitos.
- Utilizar multisig y timelock para las acciones de gobierno.
- Separar las claves de gobierno, guardián y operación.
- Configurar límites conservadores por vault y estrategia.
- Monitorizar reportes, deuda, liquidez, pausas y cambios de permisos.
- Preparar y ensayar procedimientos de emergencia.
- Verificar bytecode, parámetros y direcciones tras cada despliegue.

Esta política no constituye una garantía de seguridad ni sustituye una revisión específica del
entorno de producción.

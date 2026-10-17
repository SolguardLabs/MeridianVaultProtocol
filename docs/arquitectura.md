# Arquitectura y limites de confianza

## Capas

MeridianVaultProtocol divide el sistema en cuatro capas: interfaz ERC-4626, registro de estrategias,
adaptadores de capital y politicas auxiliares. Esta separacion evita que una estrategia pueda
modificar directamente shares, caps o fees.

```mermaid
flowchart TB
    API[ERC-4626 API] --> V[MeridianVault]
    V --> FP[FeePolicy]
    V --> R[StrategyRegistry]
    R --> VP[ValuationPolicy]
    R --> Q[Withdrawal queue]
    Q --> BS[BaseStrategy]
    BS --> RS[Reserve]
    BS --> LS[Lending]
    BS --> YS[Locked yield]
    RE[Risk Engine] -. telemetry .-> R
```

## Propiedad del estado

| Estado                  | Propietario     | Escritura autorizada            |
| ----------------------- | --------------- | ------------------------------- |
| Shares y supply         | Vault           | deposit, mint, withdraw, redeem |
| Caps y reserva objetivo | Vault           | gobierno                        |
| Deuda y reportes        | Registry        | vault, keeper, allocator        |
| Posicion externa        | Estrategia      | operadores de estrategia        |
| Fee schedule            | FeePolicy       | administracion                  |
| Bounds de valoracion    | ValuationPolicy | administracion                  |
| Reporte de riesgo       | Sin estado      | llamada pura                    |

## Fronteras externas

Los mercados y fuentes de yield pueden pausar, redondear o limitar retiradas. El adapter traduce esa
semantica a `estimatedTotalAssets`, `liquidTotalAssets`, `deployFunds` y `freeFunds`. La capa
superior no debe suponer que una estimacion implica salida inmediata.

## Flujo de retirada

```mermaid
flowchart LR
    W[Solicitud] --> I{Idle suficiente}
    I -->|si| P[Pago]
    I -->|no| Q[Recorrer cola]
    Q --> S[freeFunds]
    S --> L[Medir recibido y perdida]
    L --> C{Objetivo cubierto}
    C -->|no| Q
    C -->|si| P
```

## Actualizaciones

La version 1.0.0 no incorpora proxy. Un cambio de bytecode requiere un nuevo despliegue y una
migracion gobernada. Los consumidores deben fijar interfaces y tags, no ramas mutables.

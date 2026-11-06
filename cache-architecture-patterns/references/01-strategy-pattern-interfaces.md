# 01. Patrón Strategy e Interfaces Hexagonales para Caché

## El Dilema Arquitectónico: ¿Memoria Local o Redis?

Al construir aplicaciones web, suele cometerse uno de dos errores comunes:

1. **Sobre-ingeniería temprana**: Conectar Redis desde el primer día para almacenar listas pequeñas (ej. 100 usuarios u operadores). Cada lectura añade la latencia de ida y vuelta de red (RTT) de 2 a 5 ms, serialización/deserialización JSON y costos de servidores externos.
2. **Acoplamiento de bajo nivel**: Usar `const cache = new Map()` directamente dentro de los controladores o servicios de negocio. Cuando la aplicación escala a múltiples contenedores o pods detrás de un balanceador de carga, migrar a Redis requiere modificar decenas de archivos en toda la base de código.

---

## La Solución: Interfaces de Caché como Puertos Hexagonales

Definir contratos de caché abstractos en la capa de puertos (`ports/cache-strategy.port.ts`). El código de dominio solo conoce estas interfaces y desconoce por completo si los datos residen en la RAM local o en un clúster de Redis.

### 1. `IHashCacheStrategy<K, V>` (Semántica Hash Multi-Tenant)
Modela almacenamiento particionado por tenant o región, donde cada tenant contiene pares clave-valor individuales (`field`, `value`), análogo exacto a los comandos `HGET`, `HSET`, `HDEL`, `HGETALL` de Redis:

```typescript
export interface CacheMemoryStats {
  entries: number;
  estimatedBytes: number;
  hits: number;
  misses: number;
  hitRatio: number;
}

export interface IHashCacheStrategy<K extends string | number, V> {
  /** ¿Está el tenant inicializado e hidratado en memoria? */
  isHydrated(tenant: string): boolean;

  /** Obtiene un campo individual en O(1) */
  hget(tenant: string, field: K): V | undefined;

  /** Obtiene todos los valores del tenant */
  hgetall(tenant: string): V[];

  /** Obtiene el mapa completo de campos y valores del tenant */
  hentries(tenant: string): Map<K, V>;

  /** Asigna o actualiza un campo específico en O(1) */
  hset(tenant: string, field: K, value: V): void;

  /** Hidrata un lote de pares clave-valor */
  hmset(tenant: string, entries: Iterable<[K, V]>, ttlMs?: number): void;

  /** Elimina campos específicos */
  hdel(tenant: string, fields: K[]): number;

  /** Invalida la partición completa del tenant */
  invalidateTenant(tenant: string): void;

  /** Limpia todas las particiones */
  clear(): void;

  /** Telemetría de consumo de memoria */
  getStats(tenant?: string): CacheMemoryStats;
}
```

---

## Implementación de los Adaptadores

### Adaptador 1: `InMemoryHashCacheStrategy` (Local, 0 ms)

```typescript
class HashBucket<K, V> {
  data = new Map<K, V>();
  updatedAt = Date.now();
  hydrated = true;
}

export class InMemoryHashCacheStrategy<K extends string | number, V>
  implements IHashCacheStrategy<K, V> {
  private buckets = new Map<string, HashBucket<K, V>>();
  private hits = 0;
  private misses = 0;

  hget(tenant: string, field: K): V | undefined {
    const bucket = this.buckets.get(tenant);
    if (!bucket || !bucket.hydrated) {
      this.misses++;
      return undefined;
    }
    const val = bucket.data.get(field);
    if (val !== undefined) this.hits++;
    else this.misses++;
    return val;
  }

  hset(tenant: string, field: K, value: V): void {
    let bucket = this.buckets.get(tenant);
    if (!bucket) {
      bucket = new HashBucket<K, V>();
      this.buckets.set(tenant, bucket);
    }
    bucket.data.set(field, value);
    bucket.updatedAt = Date.now();
  }

  // Resto de la interfaz...
}
```

### Adaptador 2: `RedisHashCacheStrategy` (Distribuido, Multi-Pod)

Si en el futuro el sistema requiere sincronización entre 10 pods de Kubernetes:

```typescript
import { createClient } from 'redis';

export class RedisHashCacheStrategy<K extends string | number, V>
  implements IHashCacheStrategy<K, V> {
  constructor(private redis: ReturnType<typeof createClient>) {}

  async hget(tenant: string, field: K): Promise<V | undefined> {
    const raw = await this.redis.hGet(`cache:${tenant}`, String(field));
    return raw ? JSON.parse(raw) : undefined;
  }

  async hset(tenant: string, field: K, value: V): Promise<void> {
    await this.redis.hSet(`cache:${tenant}`, String(field), JSON.stringify(value));
  }

  // Mismos métodos, cero cambios en los servicios de negocio
}
```

---

## Regla de Oro de Diseño
> **Inversión de Dependencias (DIP):** Los servicios de tu aplicación (`UsuarioService`, `OrdenService`) deben recibir y consumir la interfaz `IHashCacheStrategy`, inyectando la implementación en el contenedor de dependencias o archivo de configuración.

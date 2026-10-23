// Runtime configuration loader.
//
// All configuration (and secrets) for the function live in SSM Parameter Store
// under CONFIG_PARAMETER_PATH, e.g. /important-api/production. The execution
// role is only allowed to read that path, and only to decrypt with the key that
// protects it. Values are fetched once per container and cached for
// CONFIG_CACHE_TTL_MS so a rotated secret is picked up without a redeploy.

// Hard defaults for anything that is allowed to be absent from Parameter Store.
export const DEFAULTS = Object.freeze({
  'response-valid-period-ms': 300_000,
});

/** Reads every parameter directly under `path` from SSM, decrypted. */
export async function fetchFromParameterStore(path) {
  // Lazy import keeps unit tests free of the SDK and shaves cold-start time
  // on the (rare) path where the cache is already warm.
  const { SSMClient, GetParametersByPathCommand } = await import('@aws-sdk/client-ssm');
  const ssm = new SSMClient({});

  const values = {};
  let nextToken;
  do {
    const page = await ssm.send(
      new GetParametersByPathCommand({
        Path: path,
        Recursive: false,
        WithDecryption: true,
        NextToken: nextToken,
      }),
    );
    for (const p of page.Parameters ?? []) {
      values[p.Name.slice(path.length + 1)] = p.Value;
    }
    nextToken = page.NextToken;
  } while (nextToken);

  return values;
}

/**
 * Builds a cached `getConfig()` function.
 *
 * @param {object} opts
 * @param {string} opts.path       Parameter Store path prefix.
 * @param {number} opts.ttlMs      How long fetched values are cached.
 * @param {(path: string) => Promise<Record<string,string>>} [opts.fetch]
 *                                 Fetcher; defaults to Parameter Store.
 */
export function createConfigLoader({ path, ttlMs, fetch = fetchFromParameterStore }) {
  let cache = { values: null, expiresAt: 0 };

  return async function getConfig() {
    const now = Date.now();
    if (cache.values && now < cache.expiresAt) {
      return cache.values;
    }
    if (!path) {
      throw new Error('CONFIG_PARAMETER_PATH is not set');
    }

    try {
      const fetched = await fetch(path);
      cache = { values: { ...DEFAULTS, ...fetched }, expiresAt: now + ttlMs };
    } catch (err) {
      if (!cache.values) throw err;
      // Serve stale rather than fail: a transient SSM blip must not take the API down.
      console.warn('config refresh failed, serving cached values', { error: err.message });
      cache.expiresAt = now + ttlMs;
    }
    return cache.values;
  };
}

/** The loader used by the deployed function, configured from the environment. */
export const getConfig = createConfigLoader({
  path: process.env.CONFIG_PARAMETER_PATH,
  ttlMs: Number(process.env.CONFIG_CACHE_TTL_MS ?? 60_000),
});

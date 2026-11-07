import { describe, it, expect } from 'vitest';
import { assertPublicSupabaseConfig, resolvePublicConfig } from './supabase';

function token(role) {
  const header = Buffer.from(JSON.stringify({ alg: 'none' })).toString('base64url');
  const payload = Buffer.from(JSON.stringify({ role })).toString('base64url');
  return `${header}.${payload}.signature`;
}

describe('assertPublicSupabaseConfig', () => {
  it('rejects a missing url or key without echoing them', () => {
    expect(() => assertPublicSupabaseConfig('', token('anon'))).toThrow(/URL is missing/);
    expect(() => assertPublicSupabaseConfig('https://example.supabase.co', '')).toThrow(/key is missing/);
    try {
      assertPublicSupabaseConfig('https://example.supabase.co', '');
    } catch (err) {
      expect(String(err.message)).not.toContain('eyJ');
    }
  });

  it('rejects a service-role key and accepts an anon key', () => {
    const service = token('service_role');
    expect(() => assertPublicSupabaseConfig('https://example.supabase.co', service)).toThrow(/service-role/);
    try {
      assertPublicSupabaseConfig('https://example.supabase.co', service);
    } catch (err) {
      expect(String(err.message)).not.toContain(service);
    }
    expect(() => assertPublicSupabaseConfig('https://example.supabase.co', token('anon'))).not.toThrow();
  });

  it('drops the debug fallback in a production build and keeps it for local dev', () => {
    const production = resolvePublicConfig({ url: '', key: '', production: true });
    expect(production.url).toBe('');
    expect(production.key).toBe('');
    expect(() => assertPublicSupabaseConfig(production.url, production.key)).toThrow(/missing/);

    const local = resolvePublicConfig({ url: '', key: '', production: false });
    expect(local.url.startsWith('https://')).toBe(true);
    expect(local.key.length).toBeGreaterThan(20);
    expect(local.key).not.toContain('service_role');
  });
});

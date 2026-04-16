import { useConnectionStore } from '../store/connectionStore';

/** JWT-authenticated fetch wrapper. Reads token from localStorage. */
export function useRestApi() {
  const backendUrl = useConnectionStore((s) => s.backendUrl);

  async function apiFetch<T>(
    path: string,
    options: RequestInit = {},
  ): Promise<T> {
    const jwt = localStorage.getItem('aksa-jwt');
    const headers: Record<string, string> = {
      'Content-Type': 'application/json',
      ...(options.headers as Record<string, string> | undefined),
    };
    if (jwt) headers['Authorization'] = `Bearer ${jwt}`;

    const res = await fetch(`${backendUrl}${path}`, { ...options, headers });
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`${res.status} ${path}: ${body}`);
    }
    return res.json() as Promise<T>;
  }

  return { apiFetch, backendUrl };
}

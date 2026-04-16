import { useState, type FormEvent } from 'react';
import { useNavigate } from 'react-router-dom';
import { useConnectionStore } from '../store/connectionStore';

export default function LoginPage() {
  const navigate = useNavigate();
  const connect = useConnectionStore((s) => s.connect);
  const backendUrl = useConnectionStore((s) => s.backendUrl);
  const setBackendUrl = useConnectionStore((s) => s.setBackendUrl);
  const status = useConnectionStore((s) => s.status);

  const [email, setEmail] = useState(localStorage.getItem('aksa-email') ?? '');
  const [password, setPassword] = useState('');
  const [error, setError] = useState('');

  async function handleSubmit(e: FormEvent) {
    e.preventDefault();
    setError('');

    try {
      // Get JWT for REST calls, store it before connecting WS
      const res = await fetch(`${backendUrl}/auth/login`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ email, password }),
      });
      const json = await res.json();
      if (!res.ok) throw new Error(json.message ?? 'Login failed');

      localStorage.setItem('aksa-jwt', json.data.accessToken);
      localStorage.setItem('aksa-email', email);

      // Connect WS (WsClient does its own auth + device registration)
      await connect(backendUrl, email, password);
      navigate('/', { replace: true });
    } catch (err) {
      setError((err as Error).message);
    }
  }

  const loading = status === 'connecting';

  return (
    <div className="min-h-screen bg-[#0d0d14] flex items-center justify-center p-4">
      <div className="w-full max-w-sm">
        {/* Logo */}
        <div className="text-center mb-8">
          <div className="inline-flex items-center justify-center w-16 h-16 rounded-2xl bg-[#00e5ff]/10 border border-[#00e5ff]/20 mb-4">
            <span className="text-[#00e5ff] text-2xl font-bold">A</span>
          </div>
          <h1 className="text-2xl font-semibold text-gray-100">Aksa</h1>
          <p className="text-sm text-gray-500 mt-1">Your AI desk companion</p>
        </div>

        <form onSubmit={handleSubmit} className="space-y-4">
          {/* Backend URL */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wide">
              Backend URL
            </label>
            <input
              type="url"
              value={backendUrl}
              onChange={(e) => setBackendUrl(e.target.value)}
              className="w-full bg-[#12121c] border border-[#2a2a40] rounded-xl px-4 py-2.5 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:border-[#00e5ff]/50 focus:ring-1 focus:ring-[#00e5ff]/20 transition"
              placeholder="http://localhost:4280"
            />
          </div>

          {/* Email */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wide">
              Email
            </label>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
              autoComplete="email"
              className="w-full bg-[#12121c] border border-[#2a2a40] rounded-xl px-4 py-2.5 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:border-[#00e5ff]/50 focus:ring-1 focus:ring-[#00e5ff]/20 transition"
              placeholder="you@example.com"
            />
          </div>

          {/* Password */}
          <div>
            <label className="block text-xs font-medium text-gray-500 mb-1.5 uppercase tracking-wide">
              Password
            </label>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              required
              autoComplete="current-password"
              className="w-full bg-[#12121c] border border-[#2a2a40] rounded-xl px-4 py-2.5 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:border-[#00e5ff]/50 focus:ring-1 focus:ring-[#00e5ff]/20 transition"
              placeholder="••••••••"
            />
          </div>

          {error && (
            <p className="text-sm text-red-400 bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">
              {error}
            </p>
          )}

          <button
            type="submit"
            disabled={loading}
            className="w-full mt-2 py-3 px-4 rounded-xl text-sm font-semibold bg-[#00e5ff] text-[#0d0d14] hover:bg-[#00ccee] active:scale-[0.98] disabled:opacity-50 disabled:cursor-not-allowed transition-all"
          >
            {loading ? 'Connecting…' : 'Connect'}
          </button>
        </form>
      </div>
    </div>
  );
}

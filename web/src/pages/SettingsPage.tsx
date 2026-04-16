import { useState, useEffect, type FormEvent } from 'react';
import { Save, Check } from 'lucide-react';
import { useRestApi } from '../hooks/useRestApi';
import { useConnectionStore } from '../store/connectionStore';

interface DeviceSettings {
  voicePreset?: string;
  voiceSpeed?: number;
  voiceStability?: number;
  volume?: number;
  brightness?: number;
}

interface Device {
  id: string;
  name: string;
  settings?: DeviceSettings;
}

const VOICE_PRESETS = ['Ziggy', 'Aria', 'Roger', 'Sarah'];

export default function SettingsPage() {
  const { apiFetch } = useRestApi();
  const backendUrl = useConnectionStore((s) => s.backendUrl);
  const [device, setDevice] = useState<Device | null>(null);
  const [loading, setLoading] = useState(true);
  const [saved, setSaved] = useState(false);
  const [error, setError] = useState('');

  // Form state
  const [voicePreset, setVoicePreset] = useState('Ziggy');
  const [voiceSpeed, setVoiceSpeed] = useState(1.0);
  const [voiceStability, setVoiceStability] = useState(0.5);
  const [volume, setVolume] = useState(80);

  useEffect(() => {
    apiFetch<{ data: Device[] }>('/devices')
      .then((res) => {
        const d = res.data?.[0];
        if (d) {
          setDevice(d);
          setVoicePreset(d.settings?.voicePreset ?? 'Ziggy');
          setVoiceSpeed(d.settings?.voiceSpeed ?? 1.0);
          setVoiceStability(d.settings?.voiceStability ?? 0.5);
          setVolume(d.settings?.volume ?? 80);
        }
      })
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function handleSave(e: FormEvent) {
    e.preventDefault();
    if (!device) return;
    setError('');
    try {
      await apiFetch(`/devices/${device.id}/settings`, {
        method: 'PATCH',
        body: JSON.stringify({ voicePreset, voiceSpeed, voiceStability, volume }),
      });
      setSaved(true);
      setTimeout(() => setSaved(false), 2000);
    } catch (err) {
      setError((err as Error).message);
    }
  }

  const email = localStorage.getItem('aksa-email') ?? '—';

  return (
    <div className="flex flex-col h-full overflow-hidden">
      {/* Header */}
      <div className="flex-shrink-0 px-5 pt-5 pb-4 border-b border-[#2a2a40]">
        <h1 className="text-lg font-semibold text-gray-100">Settings</h1>
      </div>

      <div className="flex-1 overflow-y-auto px-4 py-4 space-y-4">
        {loading && (
          <div className="flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-[#00e5ff]/30 border-t-[#00e5ff] rounded-full animate-spin" />
          </div>
        )}

        {!loading && (
          <form onSubmit={handleSave} className="space-y-4">
            {/* Account */}
            <section className="bg-[#12121c] border border-[#2a2a40] rounded-xl p-4">
              <h2 className="text-xs font-semibold text-gray-500 uppercase tracking-wide mb-3">Account</h2>
              <div className="flex items-center justify-between">
                <div>
                  <p className="text-sm text-gray-200">{email}</p>
                  <p className="text-xs text-gray-600 mt-0.5">{backendUrl}</p>
                </div>
              </div>
            </section>

            {/* Voice */}
            <section className="bg-[#12121c] border border-[#2a2a40] rounded-xl p-4 space-y-4">
              <h2 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Voice</h2>

              {/* Preset */}
              <div>
                <label className="block text-xs text-gray-500 mb-2">Voice preset</label>
                <div className="grid grid-cols-2 sm:grid-cols-4 gap-2">
                  {VOICE_PRESETS.map((p) => (
                    <button
                      key={p}
                      type="button"
                      onClick={() => setVoicePreset(p)}
                      className={`py-2 px-3 rounded-lg text-sm font-medium border transition-colors ${
                        voicePreset === p
                          ? 'bg-[#00e5ff]/15 border-[#00e5ff]/50 text-[#00e5ff]'
                          : 'bg-[#1a1a28] border-[#2a2a40] text-gray-400 hover:border-gray-500'
                      }`}
                    >
                      {p}
                    </button>
                  ))}
                </div>
              </div>

              {/* Speed */}
              <div>
                <label className="flex items-center justify-between text-xs text-gray-500 mb-2">
                  <span>Speed</span>
                  <span className="text-gray-400">{voiceSpeed.toFixed(1)}x</span>
                </label>
                <input
                  type="range" min={0.5} max={2.0} step={0.1}
                  value={voiceSpeed}
                  onChange={(e) => setVoiceSpeed(Number(e.target.value))}
                  className="w-full accent-[#00e5ff]"
                />
              </div>

              {/* Stability */}
              <div>
                <label className="flex items-center justify-between text-xs text-gray-500 mb-2">
                  <span>Stability</span>
                  <span className="text-gray-400">{Math.round(voiceStability * 100)}%</span>
                </label>
                <input
                  type="range" min={0} max={1} step={0.05}
                  value={voiceStability}
                  onChange={(e) => setVoiceStability(Number(e.target.value))}
                  className="w-full accent-[#00e5ff]"
                />
              </div>
            </section>

            {/* Device */}
            <section className="bg-[#12121c] border border-[#2a2a40] rounded-xl p-4 space-y-4">
              <h2 className="text-xs font-semibold text-gray-500 uppercase tracking-wide">Device</h2>
              <div>
                <label className="flex items-center justify-between text-xs text-gray-500 mb-2">
                  <span>Volume</span>
                  <span className="text-gray-400">{volume}%</span>
                </label>
                <input
                  type="range" min={0} max={100} step={5}
                  value={volume}
                  onChange={(e) => setVolume(Number(e.target.value))}
                  className="w-full accent-[#00e5ff]"
                />
              </div>
            </section>

            {error && (
              <p className="text-sm text-red-400 bg-red-500/10 border border-red-500/20 rounded-lg px-3 py-2">
                {error}
              </p>
            )}

            <button
              type="submit"
              disabled={!device}
              className="w-full py-3 px-4 rounded-xl text-sm font-semibold flex items-center justify-center gap-2 bg-[#00e5ff] text-[#0d0d14] hover:bg-[#00ccee] disabled:opacity-40 disabled:cursor-not-allowed transition-all active:scale-[0.98]"
            >
              {saved ? <><Check size={16} /> Saved</> : <><Save size={16} /> Save settings</>}
            </button>
          </form>
        )}
      </div>
    </div>
  );
}

import { useEffect, useRef, useState } from 'react';
import { X, Bell, Coffee, Zap, Timer } from 'lucide-react';
import { useFaceStore, type ProactiveData } from '../store/faceStore';
import { useConnectionStore } from '../store/connectionStore';

const ICONS: Record<ProactiveData['type'], typeof Bell> = {
  reminder: Bell,
  nudge: Zap,
  briefing: Coffee,
  pomodoro: Timer,
};

function useCountdown(seconds: number | undefined) {
  const [remaining, setRemaining] = useState(seconds ?? 0);
  useEffect(() => {
    if (!seconds) return;
    setRemaining(seconds);
    const id = setInterval(() => setRemaining((s) => Math.max(0, s - 1)), 1000);
    return () => clearInterval(id);
  }, [seconds]);
  return remaining;
}

function formatTime(s: number) {
  const m = Math.floor(s / 60).toString().padStart(2, '0');
  const sec = (s % 60).toString().padStart(2, '0');
  return `${m}:${sec}`;
}

export default function ProactiveOverlay() {
  const proactive = useFaceStore((s) => s.proactive);
  const dismissProactive = useFaceStore((s) => s.dismissProactive);
  const send = useConnectionStore((s) => s.send);
  const timerRef = useRef<ReturnType<typeof setTimeout> | null>(null);
  const remaining = useCountdown(proactive?.pomodoroRemaining);

  // Auto-dismiss after durationMs (except pomodoro — stays until stop event)
  useEffect(() => {
    if (!proactive || proactive.type === 'pomodoro') return;
    if (timerRef.current) clearTimeout(timerRef.current);
    timerRef.current = setTimeout(() => {
      dismissProactive();
    }, proactive.durationMs);
    return () => { if (timerRef.current) clearTimeout(timerRef.current); };
  }, [proactive, dismissProactive]);

  if (!proactive) return null;

  const Icon = ICONS[proactive.type];

  function handleDismiss() {
    send('proactive:dismiss');
    dismissProactive();
  }

  return (
    <div className="absolute top-4 left-1/2 -translate-x-1/2 z-50 w-[calc(100%-2rem)] max-w-sm animate-in slide-in-from-top-4 duration-300">
      <div className="bg-[#1a1a28] border border-[#2a2a40] rounded-2xl shadow-2xl overflow-hidden">
        {/* Accent bar */}
        <div
          className={`h-1 ${
            proactive.type === 'reminder' ? 'bg-amber-400'
            : proactive.type === 'nudge' ? 'bg-[#00e5ff]'
            : proactive.type === 'briefing' ? 'bg-violet-400'
            : 'bg-emerald-400'
          }`}
        />
        <div className="px-4 py-3 flex items-start gap-3">
          <div
            className={`mt-0.5 flex-shrink-0 w-8 h-8 rounded-lg flex items-center justify-center ${
              proactive.type === 'reminder' ? 'bg-amber-400/15 text-amber-400'
              : proactive.type === 'nudge' ? 'bg-[#00e5ff]/15 text-[#00e5ff]'
              : proactive.type === 'briefing' ? 'bg-violet-400/15 text-violet-400'
              : 'bg-emerald-400/15 text-emerald-400'
            }`}
          >
            <Icon size={16} />
          </div>

          <div className="flex-1 min-w-0">
            <p className="text-xs font-medium text-gray-500 uppercase tracking-wide mb-0.5">
              {proactive.type === 'pomodoro'
                ? `Pomodoro · Cycle ${proactive.pomodoroCycle}/${proactive.pomodoroTotalCycles}`
                : proactive.type.charAt(0).toUpperCase() + proactive.type.slice(1)}
            </p>
            <p className="text-sm text-gray-100 leading-snug">{proactive.text}</p>
            {proactive.type === 'pomodoro' && (
              <p className="mt-1 text-2xl font-mono font-bold text-emerald-400">
                {formatTime(remaining)}
              </p>
            )}
          </div>

          <button
            onClick={handleDismiss}
            className="flex-shrink-0 w-6 h-6 rounded-md text-gray-600 hover:text-gray-300 hover:bg-[#2a2a40] flex items-center justify-center transition-colors"
          >
            <X size={14} />
          </button>
        </div>
      </div>
    </div>
  );
}

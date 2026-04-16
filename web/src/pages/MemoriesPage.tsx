import { useEffect, useState } from 'react';
import { Brain } from 'lucide-react';
import { useRestApi } from '../hooks/useRestApi';

interface Memory {
  id: string;
  content: string;
  confidence: number;
  createdAt: string;
  updatedAt: string;
}

export default function MemoriesPage() {
  const { apiFetch } = useRestApi();
  const [memories, setMemories] = useState<Memory[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');

  useEffect(() => {
    apiFetch<{ data: Memory[] }>('/memories')
      .then((res) => setMemories(res.data ?? []))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  return (
    <div className="flex flex-col h-full overflow-hidden">
      {/* Header */}
      <div className="flex-shrink-0 px-5 pt-5 pb-4 border-b border-[#2a2a40]">
        <h1 className="text-lg font-semibold text-gray-100">Memories</h1>
        <p className="text-xs text-gray-500 mt-0.5">What Aksa remembers about you</p>
      </div>

      {/* List */}
      <div className="flex-1 overflow-y-auto px-4 py-3 space-y-2">
        {loading && (
          <div className="flex items-center justify-center py-16">
            <div className="w-6 h-6 border-2 border-[#00e5ff]/30 border-t-[#00e5ff] rounded-full animate-spin" />
          </div>
        )}

        {!loading && error && (
          <p className="text-sm text-red-400 text-center py-8">{error}</p>
        )}

        {!loading && !error && memories.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <Brain size={32} className="text-gray-700" />
            <p className="text-sm text-gray-600">No memories yet — start a conversation!</p>
          </div>
        )}

        {memories.map((m) => (
          <div key={m.id} className="bg-[#12121c] border border-[#2a2a40] rounded-xl px-4 py-3">
            <p className="text-sm text-gray-200 leading-relaxed">{m.content}</p>

            {/* Confidence bar */}
            <div className="mt-2.5 flex items-center gap-2">
              <div className="flex-1 h-1 bg-[#2a2a40] rounded-full overflow-hidden">
                <div
                  className="h-full bg-[#00e5ff] rounded-full transition-all"
                  style={{ width: `${Math.round(m.confidence * 100)}%` }}
                />
              </div>
              <span className="text-[11px] text-gray-600 flex-shrink-0">
                {Math.round(m.confidence * 100)}% confidence
              </span>
            </div>

            <p className="text-[11px] text-gray-700 mt-1.5">
              {new Date(m.updatedAt).toLocaleDateString(undefined, {
                month: 'short', day: 'numeric', year: 'numeric',
              })}
            </p>
          </div>
        ))}
      </div>
    </div>
  );
}

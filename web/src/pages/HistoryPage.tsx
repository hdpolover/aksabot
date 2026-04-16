import { useEffect, useState } from 'react';
import { MessageSquare, ChevronDown, ChevronUp, Search } from 'lucide-react';
import { useRestApi } from '../hooks/useRestApi';

interface Conversation {
  id: string;
  createdAt: string;
  messageCount: number;
  preview?: string;
}

interface Message {
  id: string;
  role: 'user' | 'assistant';
  content: string;
  createdAt: string;
}

export default function HistoryPage() {
  const { apiFetch } = useRestApi();
  const [conversations, setConversations] = useState<Conversation[]>([]);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [search, setSearch] = useState('');
  const [expanded, setExpanded] = useState<string | null>(null);
  const [messages, setMessages] = useState<Record<string, Message[]>>({});

  useEffect(() => {
    setLoading(true);
    const q = search ? `?q=${encodeURIComponent(search)}` : '';
    apiFetch<{ data: Conversation[] }>(`/conversations${q}`)
      .then((res) => setConversations(res.data ?? []))
      .catch((e) => setError(e.message))
      .finally(() => setLoading(false));
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [search]);

  async function toggleConversation(id: string) {
    if (expanded === id) {
      setExpanded(null);
      return;
    }
    setExpanded(id);
    if (!messages[id]) {
      try {
        const res = await apiFetch<{ data: Message[] }>(`/conversations/${id}/messages`);
        setMessages((m) => ({ ...m, [id]: res.data ?? [] }));
      } catch {
        // ignore
      }
    }
  }

  return (
    <div className="flex flex-col h-full overflow-hidden">
      {/* Header */}
      <div className="flex-shrink-0 px-5 pt-5 pb-4 border-b border-[#2a2a40]">
        <h1 className="text-lg font-semibold text-gray-100 mb-3">Conversation History</h1>
        <div className="relative">
          <Search size={15} className="absolute left-3 top-1/2 -translate-y-1/2 text-gray-500" />
          <input
            type="search"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder="Search conversations…"
            className="w-full bg-[#12121c] border border-[#2a2a40] rounded-xl pl-9 pr-4 py-2 text-sm text-gray-200 placeholder-gray-600 focus:outline-none focus:border-[#00e5ff]/40 transition"
          />
        </div>
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

        {!loading && !error && conversations.length === 0 && (
          <div className="flex flex-col items-center justify-center py-16 gap-3">
            <MessageSquare size={32} className="text-gray-700" />
            <p className="text-sm text-gray-600">No conversations yet</p>
          </div>
        )}

        {conversations.map((c) => (
          <div key={c.id} className="bg-[#12121c] border border-[#2a2a40] rounded-xl overflow-hidden">
            {/* Summary row */}
            <button
              onClick={() => toggleConversation(c.id)}
              className="w-full flex items-center gap-3 px-4 py-3 hover:bg-[#1a1a28] transition-colors text-left"
            >
              <div className="flex-shrink-0 w-8 h-8 rounded-lg bg-[#00e5ff]/10 flex items-center justify-center">
                <MessageSquare size={15} className="text-[#00e5ff]" />
              </div>
              <div className="flex-1 min-w-0">
                <p className="text-sm text-gray-200 truncate">
                  {c.preview ?? 'Conversation'}
                </p>
                <p className="text-xs text-gray-600 mt-0.5">
                  {new Date(c.createdAt).toLocaleDateString(undefined, {
                    month: 'short', day: 'numeric', year: 'numeric',
                    hour: '2-digit', minute: '2-digit',
                  })}
                  {' · '}
                  {c.messageCount} {c.messageCount === 1 ? 'message' : 'messages'}
                </p>
              </div>
              {expanded === c.id ? (
                <ChevronUp size={16} className="text-gray-500 flex-shrink-0" />
              ) : (
                <ChevronDown size={16} className="text-gray-500 flex-shrink-0" />
              )}
            </button>

            {/* Expanded messages */}
            {expanded === c.id && (
              <div className="border-t border-[#2a2a40] px-4 py-3 space-y-2 max-h-[360px] overflow-y-auto">
                {(messages[c.id] ?? []).map((msg) => (
                  <div
                    key={msg.id}
                    className={`flex ${msg.role === 'user' ? 'justify-end' : 'justify-start'}`}
                  >
                    <div
                      className={`max-w-[85%] px-3 py-2 rounded-xl text-sm ${
                        msg.role === 'user'
                          ? 'bg-[#00e5ff]/10 text-gray-200'
                          : 'bg-[#22223a] text-gray-300'
                      }`}
                    >
                      {msg.content}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        ))}
      </div>
    </div>
  );
}

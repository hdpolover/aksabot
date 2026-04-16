import { useEffect, useRef } from 'react';
import { useConversationStore, type ChatMessage } from '../store/conversationStore';

function Bubble({ msg }: { msg: ChatMessage }) {
  const isUser = msg.role === 'user';
  return (
    <div className={`flex ${isUser ? 'justify-end' : 'justify-start'}`}>
      <div
        className={`max-w-[80%] px-4 py-2.5 rounded-2xl text-sm leading-relaxed break-words ${
          isUser
            ? 'bg-[#00e5ff]/15 text-gray-100 rounded-br-sm'
            : 'bg-[#1a1a28] text-gray-200 rounded-bl-sm'
        }`}
      >
        {msg.text}
      </div>
    </div>
  );
}

export default function ChatTranscript() {
  const messages = useConversationStore((s) => s.messages);
  const partialTranscript = useConversationStore((s) => s.partialTranscript);
  const currentResponse = useConversationStore((s) => s.currentResponse);
  const bottomRef = useRef<HTMLDivElement>(null);

  // Auto-scroll to bottom on new content
  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: 'smooth' });
  }, [messages, partialTranscript, currentResponse]);

  const isEmpty = messages.length === 0 && !partialTranscript && !currentResponse;

  return (
    <div className="flex-1 overflow-y-auto px-4 py-4 space-y-3 min-h-0">
      {isEmpty && (
        <div className="flex items-center justify-center h-full">
          <p className="text-gray-600 text-sm text-center">
            Hold the mic button and start talking to Aksa
          </p>
        </div>
      )}

      {messages.map((msg) => (
        <Bubble key={msg.id} msg={msg} />
      ))}

      {/* STT partial — what the user is currently saying */}
      {partialTranscript && (
        <div className="flex justify-end">
          <div className="max-w-[80%] px-4 py-2.5 rounded-2xl rounded-br-sm text-sm leading-relaxed bg-[#00e5ff]/8 text-gray-400 italic">
            {partialTranscript}
          </div>
        </div>
      )}

      {/* LLM streaming — Aksa's current response */}
      {currentResponse && (
        <div className="flex justify-start">
          <div className="max-w-[80%] px-4 py-2.5 rounded-2xl rounded-bl-sm text-sm leading-relaxed bg-[#1a1a28] text-gray-300">
            {currentResponse}
            <span className="inline-block w-1.5 h-4 bg-[#00e5ff]/60 ml-1 align-middle animate-pulse rounded-sm" />
          </div>
        </div>
      )}

      <div ref={bottomRef} />
    </div>
  );
}

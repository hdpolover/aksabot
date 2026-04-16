import { create } from 'zustand';

export type MessageRole = 'user' | 'bot';

export interface ChatMessage {
  id: string;
  role: MessageRole;
  text: string;
  timestamp: number;
}

interface ConversationState {
  messages: ChatMessage[];
  partialTranscript: string | null; // STT in-progress
  currentResponse: string;          // LLM streaming, accumulated per response

  addMessage: (role: MessageRole, text: string) => void;
  setPartialTranscript: (text: string | null) => void;
  startResponse: () => void;
  appendResponse: (text: string) => void;
  commitResponse: () => void;
  clear: () => void;
}

let msgCounter = 0;

export const useConversationStore = create<ConversationState>((set, get) => ({
  messages: [],
  partialTranscript: null,
  currentResponse: '',

  addMessage(role, text) {
    const msg: ChatMessage = {
      id: `msg-${++msgCounter}`,
      role,
      text,
      timestamp: Date.now(),
    };
    set((s) => ({ messages: [...s.messages, msg] }));
  },

  setPartialTranscript(text) {
    set({ partialTranscript: text });
  },

  startResponse() {
    set({ currentResponse: '' });
  },

  appendResponse(text) {
    set((s) => ({
      currentResponse: s.currentResponse ? s.currentResponse + ' ' + text : text,
    }));
  },

  commitResponse() {
    const { currentResponse, addMessage } = get();
    if (currentResponse.trim()) {
      addMessage('bot', currentResponse.trim());
    }
    set({ currentResponse: '' });
  },

  clear() {
    set({ messages: [], partialTranscript: null, currentResponse: '' });
  },
}));

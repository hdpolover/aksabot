import { create } from 'zustand';
import { WsClient } from '../ws/WsClient';
import { handleWsEvent } from './wsEventBridge';
import { audioStore } from './audioStore';
import { useFaceStore } from './faceStore';
import { Expression } from '../types';

export type WsStatus = 'disconnected' | 'connecting' | 'connected';

interface ConnectionState {
  status: WsStatus;
  backendUrl: string;
  client: WsClient;

  connect: (backendUrl: string, email: string, password: string) => Promise<void>;
  disconnect: () => void;
  send: (event: string, data?: Record<string, unknown>) => void;
  sendBinary: (data: ArrayBuffer) => void;
  setBackendUrl: (url: string) => void;
}

export const useConnectionStore = create<ConnectionState>((set, get) => {
  const client = new WsClient(
    // JSON events
    (event, data) => {
      handleWsEvent(event, data, (e, d) => client.send(e, d ?? {}));
    },
    // Binary: Opus frames from backend → AudioPlayer
    async (data) => {
      const { audioPlayer, isPlaying } = audioStore.getState();
      if (isPlaying) {
        await audioPlayer.feedOpusFrame(data);
      }
    },
    // Connection status
    (connected) => {
      set({ status: connected ? 'connected' : 'disconnected' });
      useFaceStore.getState().setExpression(connected ? Expression.IDLE : Expression.OFFLINE);
    },
  );

  return {
    status: 'disconnected',
    backendUrl: localStorage.getItem('aksa-backend-url') ?? 'http://localhost:4280',
    client,

    async connect(backendUrl, email, password) {
      set({ status: 'connecting', backendUrl });
      localStorage.setItem('aksa-backend-url', backendUrl);

      const { audioPlayer } = audioStore.getState();
      await audioPlayer.init();
      await audioPlayer.resume();

      await client.connect(backendUrl, email, password, 'Aksa Web');
    },

    disconnect() {
      client.disconnect();
      set({ status: 'disconnected' });
      useFaceStore.getState().setExpression(Expression.OFFLINE);
    },

    send(event, data = {}) {
      client.send(event, data);
    },

    sendBinary(data) {
      client.sendBinary(data);
    },

    setBackendUrl(url) {
      set({ backendUrl: url });
      localStorage.setItem('aksa-backend-url', url);
    },
  };
});

import { create } from 'zustand';
import { AudioPlayer } from '../ws/AudioPlayer';
import { AudioRecorder } from '../ws/AudioRecorder';
import { useFaceStore } from './faceStore';
import { Expression } from '../types';

// Module-level frame callback — set before each recording session
let _sendFrame: ((pcm: ArrayBuffer) => void) | null = null;

const _player = new AudioPlayer((amp) => {
  audioStore.getState().setAmplitude(amp);
});

const _recorder = new AudioRecorder((pcm) => {
  _sendFrame?.(pcm);
});

interface AudioState {
  audioPlayer: AudioPlayer;
  audioRecorder: AudioRecorder;
  isRecording: boolean;
  isPlaying: boolean;
  amplitude: number;

  startRecording: (onFrame: (pcm: ArrayBuffer) => void) => Promise<void>;
  stopRecording: () => void;
  setAmplitude: (amp: number) => void;
  setPlaying: (playing: boolean) => void;
}

export const audioStore = create<AudioState>((set, get) => ({
  audioPlayer: _player,
  audioRecorder: _recorder,
  isRecording: false,
  isPlaying: false,
  amplitude: 0,

  async startRecording(onFrame) {
    if (get().isRecording) return;
    _sendFrame = onFrame;
    set({ isRecording: true });
    useFaceStore.getState().setExpression(Expression.LISTENING);
    try {
      await _recorder.start();
    } catch (err) {
      set({ isRecording: false });
      throw err;
    }
  },

  stopRecording() {
    if (!get().isRecording) return;
    _recorder.stop();
    _sendFrame = null;
    set({ isRecording: false });
  },

  setAmplitude(amp) {
    set({ amplitude: amp });
  },

  setPlaying(playing) {
    set({ isPlaying: playing });
  },
}));

export const useAudioStore = audioStore;

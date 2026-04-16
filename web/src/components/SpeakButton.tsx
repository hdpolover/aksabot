import { useRef, useCallback } from 'react';
import { Mic } from 'lucide-react';
import { useAudioStore } from '../store/audioStore';
import { useConnectionStore } from '../store/connectionStore';

export default function SpeakButton() {
  const isRecording = useAudioStore((s) => s.isRecording);
  const startRecording = useAudioStore((s) => s.startRecording);
  const stopRecording = useAudioStore((s) => s.stopRecording);
  const send = useConnectionStore((s) => s.send);
  const sendBinary = useConnectionStore((s) => s.sendBinary);
  const status = useConnectionStore((s) => s.status);
  const pressedRef = useRef(false);

  const handleStart = useCallback(async () => {
    if (pressedRef.current || status !== 'connected') return;
    pressedRef.current = true;
    send('audio:start', { format: 'pcm16' });
    try {
      await startRecording((pcm) => sendBinary(pcm));
    } catch {
      pressedRef.current = false;
    }
  }, [status, send, sendBinary, startRecording]);

  const handleStop = useCallback(() => {
    if (!pressedRef.current) return;
    pressedRef.current = false;
    stopRecording();
    send('audio:end');
  }, [stopRecording, send]);

  const disabled = status !== 'connected';

  return (
    <div className="flex flex-col items-center gap-2 select-none">
      {/* Ripple rings when recording */}
      <div className="relative flex items-center justify-center">
        {isRecording && (
          <>
            <span className="absolute w-20 h-20 rounded-full border border-red-500/40 animate-ping" />
            <span className="absolute w-28 h-28 rounded-full border border-red-500/20 animate-ping [animation-delay:150ms]" />
          </>
        )}

        <button
          onMouseDown={handleStart}
          onMouseUp={handleStop}
          onMouseLeave={handleStop}
          onTouchStart={(e) => { e.preventDefault(); handleStart(); }}
          onTouchEnd={(e) => { e.preventDefault(); handleStop(); }}
          disabled={disabled}
          aria-label={isRecording ? 'Recording — release to stop' : 'Hold to speak'}
          className={`
            relative w-16 h-16 rounded-full flex items-center justify-center
            transition-all duration-150 touch-none
            ${disabled
              ? 'bg-[#1a1a28] border border-[#2a2a40] text-gray-600 cursor-not-allowed'
              : isRecording
                ? 'bg-red-600 border-2 border-red-400 text-white shadow-lg shadow-red-900/50 scale-110'
                : 'bg-[#00e5ff]/10 border-2 border-[#00e5ff]/40 text-[#00e5ff] hover:bg-[#00e5ff]/20 hover:border-[#00e5ff]/70 active:scale-95'
            }
          `}
        >
          <Mic size={24} />
        </button>
      </div>

      <span className="text-[11px] text-gray-600">
        {disabled ? 'Not connected' : isRecording ? 'Listening…' : 'Hold to speak'}
      </span>
    </div>
  );
}

import AksaFace from '../components/AksaFace';
import ChatTranscript from '../components/ChatTranscript';
import SpeakButton from '../components/SpeakButton';
import ProactiveOverlay from '../components/ProactiveOverlay';
import { usePresence } from '../hooks/usePresence';

export default function HomePage() {
  usePresence();

  return (
    /*
     * Layout:
     *   Mobile  (< md): flex-col — face top, transcript middle, speak button bottom
     *   Desktop (≥ md): flex-row — face panel left (~320px), transcript fills right
     */
    <div className="flex flex-col md:flex-row h-full overflow-hidden">

      {/* ── Face panel ── */}
      <div className="
        relative flex flex-col items-center justify-center gap-5
        flex-shrink-0
        md:w-[340px] md:h-full md:border-r md:border-[#2a2a40]
        py-6 px-4
      ">
        {/* Proactive overlay floats above the face panel on desktop */}
        <ProactiveOverlay />

        {/* The face canvas — scales between mobile and desktop sizes */}
        <AksaFace className="
          w-[180px] h-[240px]
          sm:w-[210px] sm:h-[280px]
          md:w-[240px] md:h-[320px]
          rounded-xl shadow-2xl shadow-black/50
        " />

        {/* Speak button — sits below face on desktop, hidden on mobile (shown in footer) */}
        <div className="hidden md:flex flex-col items-center">
          <SpeakButton />
        </div>
      </div>

      {/* ── Transcript panel ── */}
      <div className="flex-1 flex flex-col min-h-0 overflow-hidden">
        <ChatTranscript />

        {/* Speak button footer — mobile only */}
        <div className="md:hidden flex items-center justify-center py-4 border-t border-[#2a2a40] bg-[#0d0d14]">
          <SpeakButton />
        </div>
      </div>
    </div>
  );
}

import { useEffect, useRef } from 'react';
import { useConnectionStore } from '../store/connectionStore';

const IDLE_TIMEOUT_MS = 5 * 60 * 1000; // 5 minutes

/** Detects browser presence via tab visibility + idle mouse/keyboard.
 *  Sends presence:arrived / presence:departed to backend over WebSocket. */
export function usePresence() {
  const send = useConnectionStore((s) => s.send);
  const status = useConnectionStore((s) => s.status);
  const idleTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const isPresent = useRef(true);

  function markArrived() {
    if (isPresent.current) return;
    isPresent.current = true;
    if (status === 'connected') send('presence:arrived');
  }

  function markDeparted() {
    if (!isPresent.current) return;
    isPresent.current = false;
    if (status === 'connected') send('presence:departed');
  }

  function resetIdleTimer() {
    if (idleTimer.current) clearTimeout(idleTimer.current);
    markArrived();
    idleTimer.current = setTimeout(markDeparted, IDLE_TIMEOUT_MS);
  }

  useEffect(() => {
    if (status !== 'connected') return;

    // Initial arrival
    markArrived();
    resetIdleTimer();

    // Tab visibility
    function onVisibilityChange() {
      if (document.hidden) {
        markDeparted();
      } else {
        markArrived();
        resetIdleTimer();
      }
    }

    // Activity events
    const activityEvents = ['mousemove', 'keydown', 'pointerdown', 'touchstart', 'scroll'];
    function onActivity() {
      resetIdleTimer();
    }

    document.addEventListener('visibilitychange', onVisibilityChange);
    activityEvents.forEach((e) => window.addEventListener(e, onActivity, { passive: true }));

    return () => {
      if (idleTimer.current) clearTimeout(idleTimer.current);
      document.removeEventListener('visibilitychange', onVisibilityChange);
      activityEvents.forEach((e) => window.removeEventListener(e, onActivity));
    };
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [status]);
}

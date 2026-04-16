import { useEffect, useRef } from 'react';
import { DisplayManager } from '../display/DisplayManager';
import { LCD_WIDTH, LCD_HEIGHT } from '../types';
import { useFaceStore } from '../store/faceStore';
import { useAudioStore } from '../store/audioStore';

interface Props {
  className?: string;
}

export default function AksaFace({ className }: Props) {
  const canvasRef = useRef<HTMLCanvasElement>(null);
  const displayRef = useRef<DisplayManager | null>(null);
  const rafRef = useRef<number>(0);

  const expression = useFaceStore((s) => s.expression);
  const amplitude = useAudioStore((s) => s.amplitude);

  // Initialize DisplayManager + render loop
  useEffect(() => {
    const canvas = canvasRef.current;
    if (!canvas) return;

    const ctx = canvas.getContext('2d')!;
    const display = new DisplayManager(ctx);
    display.init(performance.now());
    displayRef.current = display;

    const tick = () => {
      display.tick(performance.now());
      rafRef.current = requestAnimationFrame(tick);
    };
    rafRef.current = requestAnimationFrame(tick);

    return () => {
      cancelAnimationFrame(rafRef.current);
      displayRef.current = null;
    };
  }, []);

  // Sync expression
  useEffect(() => {
    displayRef.current?.face.setExpression(expression);
  }, [expression]);

  // Sync audio amplitude → mouth animation
  useEffect(() => {
    displayRef.current?.face.feedAudioAmplitude(amplitude);
  }, [amplitude]);

  return (
    <canvas
      ref={canvasRef}
      width={LCD_WIDTH}
      height={LCD_HEIGHT}
      className={className}
      style={{ imageRendering: 'pixelated' }}
    />
  );
}

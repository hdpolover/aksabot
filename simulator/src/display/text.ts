/**
 * Text rendering helpers that match the firmware's LovyanGFX text behavior.
 *
 * LovyanGFX uses a 6x8 bitmap font. setTextSize(N) scales it to (6*N)x(8*N) pixels.
 * We use a monospace font scaled to match the same pixel height.
 */

/** Get CSS font string matching LovyanGFX textSize */
export function tftFont(textSize: number): string {
  const pxHeight = textSize * 8;
  return `bold ${pxHeight}px monospace`;
}

/** Approximate character width for LovyanGFX textSize */
export function tftCharWidth(textSize: number): number {
  return textSize * 6;
}

/** Approximate text width for a string at a given textSize */
export function tftTextWidth(text: string, textSize: number): number {
  return text.length * tftCharWidth(textSize);
}

/**
 * Word-wrap text to fit within maxWidth pixels at the given textSize.
 * Returns array of lines.
 */
export function wordWrap(text: string, textSize: number, maxWidth: number): string[] {
  const charW = tftCharWidth(textSize);
  const maxChars = Math.floor(maxWidth / charW);
  if (maxChars < 1) return [text];

  const words = text.split(' ');
  const lines: string[] = [];
  let current = '';

  for (const word of words) {
    const test = current ? `${current} ${word}` : word;
    if (test.length > maxChars && current) {
      lines.push(current);
      // If a single word is longer than maxChars, force-break it
      if (word.length > maxChars) {
        let remaining = word;
        while (remaining.length > maxChars) {
          lines.push(remaining.slice(0, maxChars));
          remaining = remaining.slice(maxChars);
        }
        current = remaining;
      } else {
        current = word;
      }
    } else {
      current = test;
    }
  }
  if (current) lines.push(current);
  return lines;
}

/**
 * Draw text with word wrapping. Returns the Y position after the last line.
 */
export function drawWrappedText(
  ctx: CanvasRenderingContext2D,
  text: string,
  x: number,
  y: number,
  maxWidth: number,
  textSize: number,
  color: string,
  align: CanvasTextAlign = 'start',
): number {
  const lineH = textSize * 8 + Math.max(2, textSize * 2); // line height with spacing
  const lines = wordWrap(text, textSize, maxWidth);

  ctx.font = tftFont(textSize);
  ctx.fillStyle = color;
  ctx.textAlign = align;
  ctx.textBaseline = 'top';

  for (const line of lines) {
    ctx.fillText(line, x, y);
    y += lineH;
  }

  return y;
}

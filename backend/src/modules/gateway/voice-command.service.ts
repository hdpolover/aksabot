import { Injectable, Logger } from '@nestjs/common';

export interface VoiceCommandMatch {
  command: string;
  args?: string;
}

interface CommandPattern {
  command: string;
  patterns: RegExp[];
}

const COMMANDS: CommandPattern[] = [
  {
    command: 'pomodoro:start',
    patterns: [
      /\b(start|begin|launch)\b.+\bpomodoro\b/i,
      /\bpomodoro\b.+\b(start|begin|go)\b/i,
      /\bpomodoro\b\s*(mode|time|timer)?\s*$/i,
    ],
  },
  {
    command: 'pomodoro:stop',
    patterns: [
      /\b(stop|end|cancel|finish)\b.+\bpomodoro\b/i,
      /\bpomodoro\b.+\b(stop|end|cancel|off|done)\b/i,
    ],
  },
  {
    command: 'focus:start',
    patterns: [
      /\b(start|begin|enable|activate)\b.+\bfocus\b/i,
      /\bfocus\b\s*(mode)?\s*(on|start|begin|go)?\s*$/i,
      /\bi need to focus\b/i,
      /\blet me focus\b/i,
    ],
  },
  {
    command: 'focus:stop',
    patterns: [
      /\b(stop|end|cancel|disable|exit)\b.+\bfocus\b/i,
      /\bfocus\b.+\b(stop|end|off|cancel|done)\b/i,
    ],
  },
  {
    command: 'sleep',
    patterns: [
      /\b(go to sleep|shut up|be quiet|silence|mute)\b/i,
      /\bsleep\s*(mode)?\s*$/i,
      /\bleave me alone\b/i,
      /\bstop talking\b/i,
    ],
  },
  {
    command: 'memories:list',
    patterns: [
      /\bwhat do you (know|remember)\b/i,
      /\bwhat.+(remember|know).+about me\b/i,
      /\bmy memories\b/i,
      /\blist.+memories\b/i,
      /\btell me what you (know|remember)\b/i,
    ],
  },
  {
    command: 'mood:history',
    patterns: [
      /\bhow (have i|was i|am i) been feeling\b/i,
      /\bmy mood\b/i,
      /\bmood (history|journal|log|check)\b/i,
      /\bhow.+my (mood|feeling|vibe)\b/i,
      /\bvibe check\b/i,
    ],
  },
  {
    command: 'cancel',
    patterns: [/^(never\s*mind|cancel|nah|forget it|nvm)\s*[.!?]*$/i],
  },
  {
    command: 'reminder:set',
    patterns: [/\b(remind me|set a reminder|reminder)\b(.+)/i],
  },
];

@Injectable()
export class VoiceCommandService {
  private readonly logger = new Logger(VoiceCommandService.name);

  /**
   * Check if a transcript matches a known voice command.
   * Returns the command match or null if no command detected.
   */
  match(transcript: string): VoiceCommandMatch | null {
    const cleaned = transcript.trim();
    if (!cleaned) return null;

    for (const { command, patterns } of COMMANDS) {
      for (const pattern of patterns) {
        const m = cleaned.match(pattern);
        if (m) {
          // Extract args for commands that need them (e.g., reminder text)
          let args: string | undefined;
          if (command === 'reminder:set' && m[2]) {
            args = m[2].trim().replace(/^(to|that|about)\s+/i, '');
          }

          this.logger.log(
            `Voice command matched: "${command}" from "${cleaned.slice(0, 50)}"`,
          );
          return { command, args };
        }
      }
    }

    return null;
  }
}

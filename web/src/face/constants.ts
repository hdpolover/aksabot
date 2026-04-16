import type { Palette, EyeShape } from '../types';

// ── Palette per expression ──
// Direct port of C++ PAL[12] — converted from RGB565 to RGB888

export const PAL: Palette[] = [
  /* IDLE */    { bg: {r:5,g:5,b:20},    iris: {r:0,g:200,b:220},   irisRing: {r:0,g:140,b:160},   accent: {r:0,g:255,b:255},   mouth: {r:200,g:210,b:230}, label: {r:80,g:90,b:110},    sclera: {r:235,g:235,b:245} },
  /* LISTEN */  { bg: {r:5,g:15,b:15},   iris: {r:0,g:230,b:100},   irisRing: {r:0,g:160,b:70},    accent: {r:0,g:255,b:120},   mouth: {r:190,g:230,b:200}, label: {r:0,g:200,b:90},     sclera: {r:230,g:245,b:235} },
  /* THINK */   { bg: {r:15,g:5,b:20},   iris: {r:240,g:180,b:40},  irisRing: {r:180,g:130,b:20},  accent: {r:255,g:200,b:60},  mouth: {r:210,g:190,b:150}, label: {r:220,g:170,b:30},   sclera: {r:245,g:240,b:230} },
  /* SPEAK */   { bg: {r:5,g:8,b:25},    iris: {r:80,g:180,b:255},  irisRing: {r:50,g:130,b:200},  accent: {r:100,g:200,b:255}, mouth: {r:190,g:210,b:245}, label: {r:70,g:170,b:240},   sclera: {r:230,g:238,b:250} },
  /* CONFUS */  { bg: {r:20,g:10,b:5},   iris: {r:255,g:160,b:40},  irisRing: {r:200,g:110,b:20},  accent: {r:255,g:180,b:60},  mouth: {r:230,g:195,b:140}, label: {r:240,g:150,b:30},   sclera: {r:250,g:240,b:230} },
  /* SLEEP */   { bg: {r:3,g:3,b:15},    iris: {r:80,g:80,b:150},   irisRing: {r:50,g:50,b:110},   accent: {r:60,g:60,b:120},   mouth: {r:110,g:110,b:170}, label: {r:50,g:50,b:90},     sclera: {r:200,g:200,b:220} },
  /* OFFLN */   { bg: {r:15,g:5,b:5},    iris: {r:255,g:50,b:50},   irisRing: {r:190,g:30,b:30},   accent: {r:255,g:60,b:60},   mouth: {r:170,g:90,b:90},   label: {r:240,g:40,b:40},    sclera: {r:240,g:220,b:220} },
  /* ENCOU */   { bg: {r:15,g:15,b:5},   iris: {r:255,g:210,b:60},  irisRing: {r:200,g:160,b:30},  accent: {r:255,g:220,b:80},  mouth: {r:235,g:215,b:145}, label: {r:245,g:200,b:50},   sclera: {r:250,g:248,b:230} },
  /* CALM */    { bg: {r:5,g:15,b:10},   iris: {r:80,g:220,b:120},  irisRing: {r:50,g:170,b:80},   accent: {r:100,g:240,b:140}, mouth: {r:170,g:225,b:190}, label: {r:70,g:210,b:110},   sclera: {r:230,g:248,b:238} },
  /* FOCUS */   { bg: {r:5,g:5,b:25},    iris: {r:50,g:120,b:255},  irisRing: {r:30,g:80,b:200},   accent: {r:70,g:140,b:255},  mouth: {r:175,g:195,b:250}, label: {r:40,g:110,b:240},   sclera: {r:230,g:235,b:255} },
  /* HAPPY */   { bg: {r:20,g:5,b:15},   iris: {r:255,g:100,b:180}, irisRing: {r:200,g:60,b:140},  accent: {r:255,g:120,b:200}, mouth: {r:250,g:195,b:215}, label: {r:245,g:90,b:170},   sclera: {r:255,g:235,b:245} },
  /* SAD */     { bg: {r:8,g:8,b:15},    iris: {r:100,g:120,b:180}, irisRing: {r:70,g:85,b:140},   accent: {r:80,g:100,b:160},  mouth: {r:135,g:145,b:175}, label: {r:90,g:110,b:170},   sclera: {r:225,g:228,b:240} },
];

// ── Eye shape per expression ──

export const EYES: EyeShape[] = [
  /* IDLE */    { r: 28, pupilR: 10, pupilOX:   0, pupilOY:   0, canBlink: true,  hasBrows: false },
  /* LISTEN */  { r: 34, pupilR: 11, pupilOX:   0, pupilOY:   0, canBlink: false, hasBrows: false },
  /* THINK */   { r: 28, pupilR: 10, pupilOX: -12, pupilOY: -10, canBlink: false, hasBrows: false },
  /* SPEAK */   { r: 28, pupilR: 10, pupilOX:   0, pupilOY:   4, canBlink: true,  hasBrows: false },
  /* CONFUS */  { r: 28, pupilR: 11, pupilOX:  12, pupilOY:  -5, canBlink: false, hasBrows: false },
  /* SLEEP */   { r:  0, pupilR:  0, pupilOX:   0, pupilOY:   0, canBlink: false, hasBrows: false },
  /* OFFLN */   { r: 24, pupilR: 10, pupilOX:   0, pupilOY:   5, canBlink: false, hasBrows: false },
  /* ENCOU */   { r: 30, pupilR:  9, pupilOX:   0, pupilOY:  -8, canBlink: true,  hasBrows: true  },
  /* CALM */    { r: 28, pupilR: 12, pupilOX:   0, pupilOY:   0, canBlink: true,  hasBrows: false },
  /* FOCUS */   { r: 28, pupilR:  9, pupilOX:   0, pupilOY:   5, canBlink: true,  hasBrows: false },
  /* HAPPY */   { r: 30, pupilR:  9, pupilOX:   0, pupilOY:  -6, canBlink: true,  hasBrows: true  },
  /* SAD */     { r: 26, pupilR: 11, pupilOX:   0, pupilOY:  10, canBlink: false, hasBrows: false },
];

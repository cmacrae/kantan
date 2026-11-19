// The waveform module: the sound the Mac is playing, drawn in its style.
// Its sample is `{ levels }`, the level of each band of the sound from 0 to
// 1, the lowest first; without a level above 0, there is no sound.
import { plainState } from "../output.js";
import { bool, dict, int, list, num, str } from "../values.js";
import { shuffledRainbow } from "./workspace.js";

// The most bars the module draws, which is the bands kantan measures.
const BANDS = 256;

// What the module draws the sound as. The first is what it draws unless
// told otherwise.
const STYLES = ["bars", "wave", "flow", "scroll", "spectrogram", "line", "dots"];

// What the `wave` style adds to its line.
const WAVE_OPTIONS = ["lock", "glow", "loudness", "tone", "curve", "fill", "stereo"];

// The width of a bar and the space between two, for a style that draws a
// bar or a column for each band, or undefined for one that doesn't.
export function barGeometry(style) {
  if (style === "bars") return { width: 2, spacing: 2 };
  if (style === "dots") return { width: 2, spacing: 1 };
  return undefined;
}

// `levels` as `count` levels, each the highest of the levels it covers.
function resampled(levels, count) {
  if (!levels.length) return Array(count).fill(0);
  return Array.from({ length: count }, (_, index) => {
    const first = Math.floor(index * levels.length / count);
    const last = Math.max(Math.floor((index + 1) * levels.length / count), first + 1);
    return Math.max(...levels.slice(first, last));
  });
}

// `levels` as the levels of `count` bars: those between them when there
// are more bars to draw than levels measured.
export function barLevels(levels, count) {
  if (count <= levels.length || levels.length < 2) return resampled(levels, count);
  return Array.from({ length: count }, (_, index) => {
    const at = index * (levels.length - 1) / (count - 1), low = Math.floor(at);
    return levels[low] + ((levels[low + 1] ?? levels[low]) - levels[low]) * (at - low);
  });
}

// How many bars a waveform of at least `bars` draws beside a module
// `matched` points wide: as many as fit that width, each as wide and as far
// apart as `style` draws them.
export function matchedBars(bars, matched, style = "bars") {
  const { width, spacing } = barGeometry(style);
  return Math.min(Math.max(Math.floor((matched + spacing) / (width + spacing)), bars), BANDS);
}

// The colours a module's `gradient` or `rainbow` gives its bars, as
// written: the `stops` a gradient passes through, which are its `colors`
// or its `low` and `high`, or a rainbow's palette, shuffled for `bars`
// unless it isn't `random`.
function colors(config, bars) {
  const gradient = dict(config?.gradient), rainbow = dict(config?.rainbow);
  const stops = (list(gradient?.colors) ?? []).filter(color => typeof color === "string");
  if (stops.length > 1) return { stops };
  if (str(gradient?.low) !== undefined && str(gradient?.high) !== undefined) return { stops: [gradient.low, gradient.high] };
  const palette = (list(rainbow?.colors) ?? []).filter(color => typeof color === "string");
  if (rainbow?.enabled !== true || !palette.length) return undefined;
  return { palette: (bool(rainbow.random) ?? true) ? shuffledRainbow(palette, bars) : palette };
}

export default {
  load(config) {
    const bars = Math.min(Math.max(int(config?.bars) ?? 8, 1), BANDS);
    const style = str(config?.style), wave = dict(config?.wave);
    return {
      style: STYLES.includes(style) ? style : STYLES[0],
      options: Object.fromEntries(WAVE_OPTIONS.map(option => [option, bool(wave?.[option]) ?? false])),
      bars, colors: colors(config, bars),
      width: Math.max(num(config?.width) ?? 40, 4),
      height: Math.max(num(config?.height) ?? 14, 2),
      hidesWhenSilent: str(config?.hide) !== "never",
      matchWidth: str(config?.matchWidth),
    };
  },

  state(loaded, sample) {
    const state = plainState("");
    const levels = (list(sample?.levels) ?? []).map(level => Math.min(Math.max(num(level) ?? 0, 0), 1));
    const silent = !levels.some(level => level > 0);
    state.hidden = silent && loaded.hidesWhenSilent;
    state.variables = { state: silent ? "Silent" : "Playing" };
    state.waveform = {
      style: loaded.style, options: loaded.options, width: loaded.width, height: loaded.height, bars: loaded.bars, colors: loaded.colors,
      levels: resampled(levels, barGeometry(loaded.style) ? loaded.bars : Math.max(levels.length, 2)),
    };
    // A waveform following another module's width keeps the levels it was
    // given, to draw as many bars of as that width fits.
    if (loaded.matchWidth !== undefined) Object.assign(state.waveform, { matchWidth: loaded.matchWidth, bands: levels });
    return state;
  },
};

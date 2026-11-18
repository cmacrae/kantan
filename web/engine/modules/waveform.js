// The waveform module: the sound the Mac is playing, as bars or as a wave.
// Its sample is `{ levels }`, the level of each band of the sound from 0 to
// 1, the lowest first; without a level above 0, there is no sound.
import { plainState } from "../output.js";
import { bool, dict, int, list, num, str } from "../values.js";
import { shuffledRainbow } from "./workspace.js";

// The most bars the module draws, which is the bands kantan measures.
const BANDS = 256;

// `levels` as `count` levels, each the highest of the levels it covers.
function resampled(levels, count) {
  if (!levels.length) return Array(count).fill(0);
  return Array.from({ length: count }, (_, index) => {
    const first = Math.floor(index * levels.length / count);
    const last = Math.max(Math.floor((index + 1) * levels.length / count), first + 1);
    return Math.max(...levels.slice(first, last));
  });
}

// The colours a module's `gradient` or `rainbow` gives its bars, as
// written: a gradient's `low` and `high`, or a rainbow's palette, shuffled
// for `bars` unless it isn't `random`.
function colors(config, bars) {
  const gradient = dict(config?.gradient), rainbow = dict(config?.rainbow);
  if (str(gradient?.low) !== undefined && str(gradient?.high) !== undefined) return { low: gradient.low, high: gradient.high };
  const palette = (list(rainbow?.colors) ?? []).filter(color => typeof color === "string");
  if (rainbow?.enabled !== true || !palette.length) return undefined;
  return { palette: (bool(rainbow.random) ?? true) ? shuffledRainbow(palette, bars) : palette };
}

export default {
  load(config) {
    const bars = Math.min(Math.max(int(config?.bars) ?? 8, 1), BANDS);
    return {
      style: str(config?.style) === "wave" ? "wave" : "bars",
      bars, colors: colors(config, bars),
      width: Math.max(num(config?.width) ?? 40, 4),
      height: Math.max(num(config?.height) ?? 14, 2),
      hidesWhenSilent: str(config?.hide) !== "never",
    };
  },

  state(loaded, sample) {
    const state = plainState("");
    const levels = (list(sample?.levels) ?? []).map(level => Math.min(Math.max(num(level) ?? 0, 0), 1));
    const silent = !levels.some(level => level > 0);
    state.hidden = silent && loaded.hidesWhenSilent;
    state.variables = { state: silent ? "Silent" : "Playing" };
    state.waveform = {
      style: loaded.style, width: loaded.width, height: loaded.height, bars: loaded.bars, colors: loaded.colors,
      levels: resampled(levels, loaded.style === "wave" ? Math.max(levels.length, 2) : loaded.bars),
    };
    return state;
  },
};

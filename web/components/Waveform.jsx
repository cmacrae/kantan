// Draws a waveform the engine resolved, in its style: a still of what
// kantan draws moving, made from the levels of the sound's bands.
import { useId } from "react";
import { barLevels } from "../engine/index.js";
import { cssColor } from "./system.js";

// How much of a style's width fades out at an end, and of the `line`
// style's height at the bottom.
const FADE = 20, BOTTOM_FADE = 35;

// A fade toward each end named, as a mask.
function fadeMask(leading, trailing, bottom) {
  const across = `linear-gradient(to right, ${leading ? "transparent" : "#000"}, #000 ${FADE}%, #000 ${100 - FADE}%, ${trailing ? "transparent" : "#000"})`;
  if (!bottom) return { maskImage: across };
  return {
    maskImage: `${across}, linear-gradient(to bottom, #000 ${100 - BOTTOM_FADE}%, transparent)`,
    maskComposite: "intersect", WebkitMaskComposite: "source-in",
  };
}

// The colour `fraction` of the way along `colors`.
const shade = (colors, fraction) => colors[Math.round(Math.min(Math.max(fraction, 0), 1) * (colors.length - 1))];

// Where the sound of `levels` sits between its lowest band, 0, and its
// highest, 1: their middle by how loud each is, the loudest counting most.
function tone(levels) {
  const weights = levels.map(level => level ** 3);
  const weight = weights.reduce((sum, each) => sum + each, 0);
  if (!weight || levels.length < 2) return 0.5;
  return weights.reduce((sum, each, index) => sum + each * index, 0) / weight / (levels.length - 1);
}

const mean = levels => (levels.length ? levels.reduce((sum, level) => sum + level, 0) / levels.length : 0);

// A path through `points`: straight from each to the next, or a curve that
// bends at each on its way between the middles of its neighbours.
function linePath(points, curved) {
  const at = ([x, y]) => `${x.toFixed(2)},${y.toFixed(2)}`;
  if (!curved || points.length < 3) return `M${points.map(at).join("L")}`;
  const bends = points.slice(1, -1).map((point, index) => {
    const next = points[index + 2];
    return `Q${at(point)} ${at([(point[0] + next[0]) / 2, (point[1] + next[1]) / 2])}`;
  });
  return `M${at(points[0])}${bends.join("")}L${at(points[points.length - 1])}`;
}

// The wave of a sound with `levels`: a tone for each level, as points
// across `width`, `spacing` apart. The tones rise from the slowest, which
// swings once or twice across the module, to the quickest the points can
// show, each setting off from its own place so that they never all meet,
// and the whole swells and sinks along its length. It is drawn as tall as
// the module, as kantan draws a wave, its few highest peaks cut short.
// `shift` moves it along, as the sound a moment earlier or its other side
// would be.
function wavePoints(levels, width, height, spacing, shift = 0) {
  const count = Math.max(Math.round(width / spacing), 2);
  const quickest = Math.max(count / 4, 3);
  const swings = Array.from({ length: count }, (_, index) => {
    const along = index / (count - 1);
    const swell = 0.75 + 0.25 * Math.sin(2 * Math.PI * 2.3 * along + 0.9 + shift);
    return swell * levels.reduce((sum, level, each) => {
      const cycles = 1.4 * (quickest / 1.4) ** (levels.length > 1 ? each / (levels.length - 1) : 0);
      return sum + level * Math.sin(2 * Math.PI * (cycles * along + each * each * 0.37 + each * 0.21) + shift * (each + 1));
    }, 0);
  });
  const usual = Math.sqrt(swings.reduce((sum, swing) => sum + swing * swing, 0) / count) || 1;
  return swings.map((swing, index) => [
    width * index / (count - 1),
    height / 2 * (1 - Math.min(Math.max(swing / (usual * 2.4), -1), 1)),
  ]);
}

// The colours of the bars from left to right, as a gradient to stroke or
// fill with.
function Shades({ id, colors, dark }) {
  return (
    <defs>
      <linearGradient id={id} gradientUnits="userSpaceOnUse" x1="0" x2="100%" y1="0" y2="0">
        {colors.map((stop, index) => (
          <stop key={index} offset={colors.length > 1 ? index / (colors.length - 1) : 0} stopColor={cssColor(stop, dark)} />
        ))}
      </linearGradient>
    </defs>
  );
}

function Wave({ waveform, color, dark, gradient }) {
  const { levels, width, height, colors, options = {} } = waveform;
  const spacing = options.curve ? 3 : 1.5;
  const strokeWidth = options.loudness ? 0.7 + 1.5 * mean(levels) : 1.2;
  const across = colors ? `url(#${gradient})` : color;
  // Each line's colour and how far along it is moved: the left and right
  // sides, or the one line of the two together.
  const lines = options.stereo
    ? [{ stroke: colors ? cssColor(colors[0], dark) : color, shift: 0 }, { stroke: colors ? cssColor(colors[colors.length - 1], dark) : color, shift: 0.5, opacity: colors ? 1 : 0.55 }]
    : [{ stroke: options.tone && colors ? cssColor(shade(colors, tone(levels)), dark) : across, shift: 0 }];
  // The waves drawn before this one, the oldest first and the faintest.
  const ages = options.glow ? [3, 2, 1, 0] : [0];
  return (
    <>
      {colors && <Shades id={gradient} colors={colors} dark={dark} />}
      {ages.flatMap(age => lines.map((line, index) => {
        const path = linePath(wavePoints(levels, width, height, spacing, line.shift + age * 0.35), options.curve);
        return (
          <g key={`${age}-${index}`} opacity={(line.opacity ?? 1) * 0.5 ** age}>
            {options.fill && age === 0 && <path d={`${path}L${width},${height / 2}L0,${height / 2}Z`} fill={line.stroke} opacity={0.22} />}
            <path d={path} fill="none" stroke={line.stroke} strokeWidth={strokeWidth} strokeLinejoin="round" strokeLinecap="round" />
          </g>
        );
      }))}
    </>
  );
}

// A ribbon each for the low, middle and high bands: how many times it
// swings across the module, and how bright it is.
const RIBBONS = [{ cycles: 1, opacity: 0.95 }, { cycles: 1.7, opacity: 0.65 }, { cycles: 2.6, opacity: 0.45 }];

function Flow({ waveform, color, dark }) {
  const { levels, width, height, colors } = waveform;
  const third = Math.max(Math.floor(levels.length / RIBBONS.length), 1);
  const count = Math.max(Math.round(width / 1.5), 2);
  return RIBBONS.map((ribbon, index) => {
    const reach = Math.min(mean(levels.slice(index * third, (index + 1) * third)) * 1.3, 1) * height / 2;
    const swings = Array.from({ length: count }, (_, point) => {
      const along = point / (count - 1);
      return [width * along, reach * Math.sin(Math.PI * along) ** 2 * Math.sin(2 * Math.PI * ribbon.cycles * along + index * 1.9)];
    });
    const upper = linePath(swings.map(([x, y]) => [x, height / 2 - y]));
    const lower = swings.map(([x, y]) => `L${x.toFixed(2)},${(height / 2 + y).toFixed(2)}`).reverse().join("");
    const own = colors ? cssColor(shade(colors, index / (RIBBONS.length - 1)), dark) : color;
    return (
      <g key={index} opacity={ribbon.opacity}>
        <path d={`${upper}${lower}Z`} fill={own} opacity={0.3} />
        <path d={upper} fill="none" stroke={own} strokeWidth={1} strokeLinejoin="round" />
      </g>
    );
  }).reverse();
}

// How loud the sound has been, as bars about the middle 3 points apart:
// the levels stand for the moments passed.
function Scroll({ waveform, color, dark, gradient }) {
  const { levels, width, height, colors } = waveform;
  const heights = barLevels(levels, Math.max(Math.floor(width / 3), 1));
  return (
    <>
      {colors && <Shades id={gradient} colors={colors} dark={dark} />}
      {heights.map((level, index) => {
        const tall = Math.max(level * height, 1);
        return <rect key={index} x={width - (heights.length - index) * 3} y={(height - tall) / 2} width={2} height={tall} rx={0.5} fill={colors ? `url(#${gradient})` : color} />;
      })}
    </>
  );
}

// The bands over time, a column every 2 points: each band as loud as its
// level, rising and falling from one moment to the next.
function Spectrogram({ waveform, color, dark }) {
  const { levels, width, height, colors } = waveform;
  const rows = Math.min(Math.max(Math.floor(height), 1), 32);
  const bands = barLevels(levels, rows), cell = height / rows;
  return Array.from({ length: Math.ceil(width / 2) }, (_, column) => bands.map((level, row) => {
    const loud = level * (0.6 + 0.4 * Math.sin(column * 0.45 + row * 1.3));
    if (loud <= 0.04) return null;
    return <rect key={`${column}-${row}`} x={column * 2} y={height - (row + 1) * cell} width={2} height={cell} fill={colors ? cssColor(shade(colors, loud), dark) : color} opacity={loud ** 1.5} />;
  }));
}

// The bands as one curve standing on the bottom edge, filled faintly
// beneath.
function Line({ waveform, color, dark, gradient }) {
  const { levels, width, height, colors } = waveform;
  const points = barLevels(levels, Math.max(Math.floor(width / 3), 2));
  const path = linePath(points.map((level, index) => [width * index / (points.length - 1), height - Math.max(level * (height - 1), 0.6)]), true);
  const across = colors ? `url(#${gradient})` : color;
  return (
    <>
      {colors && <Shades id={gradient} colors={colors} dark={dark} />}
      <path d={`${path}L${width},${height}L0,${height}Z`} fill={across} opacity={0.25} />
      <path d={path} fill="none" stroke={across} strokeWidth={1.2} strokeLinejoin="round" strokeLinecap="round" />
    </>
  );
}

// Each band as a column of dots 3 points apart, as many lit from the
// bottom as the band is loud and the rest dim.
function Dots({ waveform, color, dark }) {
  const { levels, height, colors } = waveform;
  const rows = Math.max(Math.floor((height + 1) / 3), 1);
  const top = (height - (rows * 3 - 1)) / 2;
  return levels.map((level, column) => {
    const lit = Math.max(Math.round(level * rows), 1);
    const own = colors ? cssColor(colors[column % colors.length], dark) : color;
    return Array.from({ length: rows }, (_, row) => (
      <circle key={`${column}-${row}`} cx={column * 3 + 1} cy={top + (rows - 1 - row) * 3 + 1} r={1} fill={own} opacity={row < lit ? 1 : 0.18} />
    ));
  });
}

const DRAWN = { wave: Wave, flow: Flow, scroll: Scroll, spectrogram: Spectrogram, line: Line, dots: Dots };

// Where each style fades out: toward both ends, toward the end what
// scrolls past leaves by, or toward the edge the `line` stands on.
const FADES = {
  wave: [true, true], flow: [true, true], line: [true, true, true],
  scroll: [true, false], spectrogram: [true, false], dots: [false, false],
};

export function Waveform({ waveform, dark, element }) {
  const { style, levels, height } = waveform;
  const color = cssColor(waveform.color, dark);
  const gradient = useId();
  const Drawn = DRAWN[style];
  if (Drawn) {
    const width = style === "dots" ? Math.max(levels.length * 3 - 1, 1) : waveform.width;
    return (
      <svg ref={element} width={width} height={height} style={{ flexShrink: 0, ...fadeMask(...FADES[style]) }}>
        <Drawn waveform={{ ...waveform, width }} color={color} dark={dark} gradient={gradient} />
      </svg>
    );
  }
  return (
    <div ref={element} style={{ display: "flex", alignItems: "center", gap: 2, height }}>
      {levels.map((level, index) => (
        <span key={index} style={{
          width: 2, height: Math.max(2, level * height), borderRadius: 1,
          background: waveform.colors ? cssColor(waveform.colors[index % waveform.colors.length], dark) : color,
        }} />
      ))}
    </div>
  );
}

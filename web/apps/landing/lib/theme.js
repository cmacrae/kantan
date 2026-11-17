export const latte = {
  fg:"#4c4f69",bg:"#eff1f5",shape:"#ccd0da",
  rosewater:"#dc8a78",flamingo:"#dd7878",pink:"#ea76cb",mauve:"#8839ef",
  red:"#d20f39",maroon:"#e64553",peach:"#fe640b",yellow:"#df8e1d",
  green:"#40a02b",teal:"#179299",sky:"#04a5e5",sapphire:"#209fb5",
  blue:"#1e66f5",lavender:"#7287fd",subtext1:"#5c5f77",overlay0:"#9ca0b0",
};

export const mocha = {
  fg:"#cdd6f4",bg:"#1e1e2e",shape:"#313244",
  rosewater:"#f5e0dc",flamingo:"#f2cdcd",pink:"#f5c2e7",mauve:"#cba6f7",
  red:"#f38ba8",maroon:"#eba0ac",peach:"#fab387",yellow:"#f9e2af",
  green:"#a6e3a1",teal:"#94e2d5",sky:"#89dceb",sapphire:"#74c7ec",
  blue:"#89b4fa",lavender:"#b4befe",subtext1:"#bac2de",overlay0:"#6c7086",
};

// The workspace module's rainbow colours, as config-example.yaml lists them.
export const RAINBOW = ["red", "peach", "green", "sky", "mauve", "pink"];

export const SPACES = 6;

const U64 = (1n << 64n) - 1n;

// kantan's `WorkspaceConfig.shuffledRainbow`: a Fisher-Yates shuffle seeded
// by the workspace count, cycled to one colour per workspace with no two
// neighbours alike.
export function shuffledRainbow(colors, spaceCount) {
  if (colors.length <= 1) return colors.slice();
  const shuffled = colors.slice();
  let rng = BigInt(spaceCount);
  for (let i = shuffled.length - 1; i >= 1; i--) {
    rng = (rng * 6364136223846793005n + 1442695040888963407n) & U64;
    const j = Number((rng >> 33n) % BigInt(i + 1));
    [shuffled[i], shuffled[j]] = [shuffled[j], shuffled[i]];
  }
  if (spaceCount <= shuffled.length) return shuffled;
  const result = shuffled.slice();
  while (result.length < spaceCount) {
    const last = result[result.length - 1];
    const start = result.length % shuffled.length;
    let next = shuffled[start];
    for (let offset = 1; next === last && offset < shuffled.length; offset++) {
      next = shuffled[(start + offset) % shuffled.length];
    }
    result.push(next);
  }
  return result;
}

// Each workspace's colour, indexed as kantan indexes them.
export const WORKSPACE_COLORS = shuffledRainbow(RAINBOW, SPACES);

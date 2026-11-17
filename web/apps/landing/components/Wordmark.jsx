// The "kantan" heading with its かんたん subheading, drawn `scale` times the
// landing page's size.
export default function Wordmark({ color, subColor, scale = 1 }) {
  return (
    <>
      <h1 style={{
        fontSize: 56 * scale, fontFamily: "'Single Day', cursive", fontWeight: 400, letterSpacing: "-0.03em",
        margin: 0, lineHeight: 1.1, color,
      }}>
        kantan
      </h1>
      <p style={{
        fontSize: 18 * scale, color: subColor, margin: `${6 * scale}px 0 0`,
        fontFamily: "'Darumadrop One', cursive",
        fontWeight: 400, letterSpacing: "0.08em",
      }}>
        &#12363;&#12435;&#12383;&#12435;
      </p>
    </>
  );
}

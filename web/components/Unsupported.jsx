// Marks something kantan draws that the preview can't yet, in its place.
export function Unsupported({ what }) {
  return (
    <span
      title={`kantan draws this ${what}, but the preview can't yet`}
      style={{
        display: "inline-flex", alignItems: "center", gap: 4, flexShrink: 0,
        padding: "1px 6px", borderRadius: 4, whiteSpace: "nowrap",
        border: "1px dashed currentColor", opacity: 0.75,
        font: "500 10px/14px -apple-system, BlinkMacSystemFont, 'Helvetica Neue', sans-serif",
      }}
    >
      {what}: not supported in preview
    </span>
  );
}

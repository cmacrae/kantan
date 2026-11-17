import { useLayoutEffect, useRef, useState } from "react";

// Shrinks `ref`'s element to fit its parent when its content is wider, as
// the bar is on a phone, but no smaller than `min` of its size.
export function useFitZoom(ref, min = 0) {
  const [zoom, setZoom] = useState(1);
  const current = useRef(1);
  useLayoutEffect(() => {
    const frame = ref.current;
    const parent = frame.parentElement;
    function fit() {
      // Both widths as drawn, so a zoom further out cancels out.
      const style = getComputedStyle(parent);
      const drawn = parent.getBoundingClientRect().width / parent.clientWidth;
      const room = (parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight)) * drawn;
      const natural = frame.getBoundingClientRect().width / current.current;
      const next = Math.max(min, Math.min(1, room / natural));
      if (Math.abs(next - current.current) > 0.001) {
        current.current = next;
        setZoom(next);
      }
    }
    const observer = new ResizeObserver(fit);
    observer.observe(parent);
    observer.observe(frame);
    return () => observer.disconnect();
  }, [ref, min]);
  return zoom;
}

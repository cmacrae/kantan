import { useLayoutEffect, useState } from "react";

// Scales `ref`'s element down to fit the room its box's parent has when
// its content is wider, as the bar is on a phone, but no smaller than
// `min` of its size. The element sits in a box of its own, which takes the
// room the element takes up once scaled: the element's layout width is
// what is compared, which no scale changes, and the box clips what is left
// of its unscaled layout, which browsers otherwise let the page scroll to.
// Gives the scale, the element's style and its box's style.
export function useFitScale(ref, min = 0) {
  const [fit, setFit] = useState({ scale: 1, width: 0, height: 0 });
  useLayoutEffect(() => {
    const frame = ref.current;
    const parent = frame.parentElement.parentElement;
    function measure() {
      const style = getComputedStyle(parent);
      const room = parent.clientWidth - parseFloat(style.paddingLeft) - parseFloat(style.paddingRight);
      const { offsetWidth: width, offsetHeight: height } = frame;
      const scale = Math.max(min, Math.min(1, room / width));
      setFit(current => (Math.abs(current.scale - scale) < 0.001 && current.width === width && current.height === height
        ? current : { scale, width, height }));
    }
    const observer = new ResizeObserver(measure);
    observer.observe(parent);
    observer.observe(frame);
    return () => observer.disconnect();
  }, [ref, min]);
  const { scale, width, height } = fit;
  if (scale === 1) return { scale, style: {}, box: { width: "100%" } };
  return {
    scale,
    style: { transform: `scale(${scale})`, transformOrigin: "top left", marginBottom: -height * (1 - scale) },
    // As wide as the room, or the scaled element where that's wider.
    box: { width: "100%", minWidth: width * scale, overflowX: "clip" },
  };
}

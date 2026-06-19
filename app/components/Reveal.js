"use client";

import { useEffect, useRef, useState } from "react";

// Scroll-reveal wrapper. Children start hidden (via the `.reveal` class in
// globals.css) and fade/slide up the first time they enter the viewport.
// `delay` (ms) staggers siblings; `className` passes through for layout
// (e.g. "h-full" so a wrapped card still stretches in a grid).
export default function Reveal({
  children,
  delay = 0,
  className = "",
  as: Tag = "div",
}) {
  const ref = useRef(null);
  const [visible, setVisible] = useState(false);

  useEffect(() => {
    const el = ref.current;
    if (!el) return;
    // Fallback: if IntersectionObserver is unavailable, just show the content
    // so it can never be left permanently hidden behind the reveal styles.
    if (typeof IntersectionObserver === "undefined") {
      setVisible(true);
      return;
    }
    const io = new IntersectionObserver(
      ([entry]) => {
        if (entry.isIntersecting) {
          setVisible(true);
          io.unobserve(el);
        }
      },
      { threshold: 0.15, rootMargin: "0px 0px -8% 0px" }
    );
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return (
    <Tag
      ref={ref}
      className={`reveal ${visible ? "is-visible" : ""} ${className}`.trim()}
      style={delay ? { transitionDelay: `${delay}ms` } : undefined}
    >
      {children}
    </Tag>
  );
}

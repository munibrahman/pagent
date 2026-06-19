"use client";

import { useEffect, useState } from "react";

// Frosted sticky header. Adds `.is-scrolled` (a hairline bottom border) once
// the page has scrolled a little, so the bar reads as floating over content.
export default function ScrollHeader({ children, className = "" }) {
  const [scrolled, setScrolled] = useState(false);

  useEffect(() => {
    const onScroll = () => setScrolled(window.scrollY > 8);
    onScroll();
    window.addEventListener("scroll", onScroll, { passive: true });
    return () => window.removeEventListener("scroll", onScroll);
  }, []);

  return (
    <header className={`nav-sticky ${scrolled ? "is-scrolled" : ""}`}>
      <nav className={className}>{children}</nav>
    </header>
  );
}

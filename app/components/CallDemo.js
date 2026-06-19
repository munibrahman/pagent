"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";

// Scripted call shown in the hero — iMessage-style voice notes that rise up.
// Each bubble has its own voice wave + live caption. Agent left, customer right.
// A line may set its own `typingMs` to override the default pace (e.g. the VIN
// is read out slowly, digit by digit).
export const NEW_CALL = [
  { role: "agent", text: "Hey, thanks for calling PartsPlace — how can I help you today?" },
  { role: "customer", text: "Hi, I'm looking for a filter for a 2009 Camry." },
  { role: "agent", text: "Sure — what kind of filter? Oil, air, cabin, or something else?" },
  { role: "customer", text: "Oh — an oil filter." },
  { role: "agent", text: "Got it. Do you know what engine size it has?" },
  { role: "customer", text: "Uhh… I don't know, honestly." },
  { role: "agent", text: "No problem — can you read me the VIN?" },
  { role: "customer", text: "Yeah, one sec… 4T1 BE46K 89U 123456.", typingMs: 135 },
  {
    role: "agent",
    text: "Perfect — that's a 2.4L. I've got a Fram oil filter, $8.99, six on the shelf. Want me to set one aside?",
  },
];

// Returning caller — PartsPanda recalls the customer's name + last vehicle.
export const RETURNING_CALL = [
  { role: "agent", text: "Thanks for calling PartsPlace — is this Mike?" },
  { role: "customer", text: "Yeah, it's me." },
  { role: "agent", text: "Welcome back! Calling about the 2009 Camry again?" },
  { role: "customer", text: "Actually, yeah — I need wiper blades this time." },
  {
    role: "agent",
    text: "Easy. Bosch Icon blades fit your Camry — $24.99 a pair, in stock. Want them set aside?",
  },
];

const TYPING_MS = 55; // per character (default pace)
const HOLD_MS = 1100; // pause after a line finishes
const LOOP_MS = 3200; // pause before the call replays

// Static base heights for the voice wave (px). Deterministic → no SSR mismatch.
const WAVE = Array.from({ length: 36 }, (_, i) => 5 + Math.round(15 * Math.abs(Math.sin(i * 0.8))));

// Drives the call: types out the current line, then advances; restarts at the end.
function useScriptedCall(script) {
  const [turn, setTurn] = useState(0);
  const [chars, setChars] = useState(0);

  useEffect(() => {
    const current = script[turn];

    if (!current) {
      const t = setTimeout(() => {
        setTurn(0);
        setChars(0);
      }, LOOP_MS);
      return () => clearTimeout(t);
    }

    if (chars < current.text.length) {
      const speed = current.typingMs ?? TYPING_MS;
      const t = setTimeout(() => setChars((c) => c + 1), speed);
      return () => clearTimeout(t);
    }

    const t = setTimeout(() => {
      setTurn((i) => i + 1);
      setChars(0);
    }, HOLD_MS);
    return () => clearTimeout(t);
  }, [turn, chars, script]);

  return { turn, chars };
}

// Voice wave inside a bubble — bounces while speaking, static once played.
function MiniWave({ active }) {
  return (
    <span className="flex h-6 w-full items-center justify-between" aria-hidden>
      {WAVE.map((h, i) => (
        <span
          key={i}
          className={`w-[2px] rounded-full bg-current ${active ? "animate-eq" : "opacity-40"}`}
          style={{
            height: `${h}px`,
            animationDelay: `${i * 80}ms`,
            animationDuration: `${700 + (i % 3) * 100}ms`,
          }}
        />
      ))}
    </span>
  );
}

export default function CallDemo({ script = NEW_CALL, fadeClass = "from-background" }) {
  const { turn, chars } = useScriptedCall(script);
  const visible = script.slice(0, turn + 1);

  return (
    <div>
      {/* call header */}

      {/* voice notes rising from the bottom; older ones clip behind the top fade */}
      <div className="relative mt-4 h-80 overflow-hidden">
        <div className={`pointer-events-none absolute inset-x-0 top-0 z-10 h-10 bg-linear-to-b to-transparent ${fadeClass}`} />
        <div className="flex h-full flex-col justify-end gap-2.5">
          <AnimatePresence initial={false}>
            {visible.map((t, i) => {
              const isAgent = t.role === "agent";
              const isTyping = i === turn && chars < t.text.length;
              const text = i === turn ? t.text.slice(0, chars) : t.text;
              return (
                // outer: layout-animates position so older bubbles glide up smoothly
                <motion.div
                  key={i}
                  layout="position"
                  exit={{ opacity: 0, transition: { duration: 0.15 } }}
                  transition={{ type: "spring", stiffness: 420, damping: 34 }}
                >
                  {/* inner: crisp spring-eased entrance (no layout conflict) */}
                  <motion.div
                    initial={{ opacity: 0, y: 14, scale: 0.97 }}
                    animate={{ opacity: 1, y: 0, scale: 1 }}
                    transition={{ duration: 0.42, ease: [0.16, 1, 0.3, 1] }}
                    className={`flex w-full flex-col ${isAgent ? "items-start" : "items-end"}`}
                  >
                    <span className="mb-1 px-1 text-[11px] font-semibold text-foreground/55">
                      {isAgent ? "PartsPanda" : "Customer"}
                    </span>
                    <div
                      className={`w-[90%] rounded-2xl px-4 py-3 ${isAgent ? "bg-foreground text-background" : "bg-[#1D3A40] text-background"
                        }`}
                    >
                      <MiniWave active={isTyping} />
                      <p className="mt-2.5 text-[13px] leading-snug opacity-80">{text}</p>
                    </div>
                  </motion.div>
                </motion.div>
              );
            })}
          </AnimatePresence>
        </div>
      </div>
    </div>
  );
}

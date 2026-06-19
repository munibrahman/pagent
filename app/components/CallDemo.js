"use client";

import { useEffect, useState } from "react";
import { AnimatePresence, motion } from "motion/react";

// Hero demo — two calls on a loop that show off MEMORY:
//   Phase 1 (New caller):  Chris calls for the first time; the agent captures
//                          his name + vehicle.
//   Phase 2 (Returning):   Chris calls back and is recognised instantly —
//                          greeted by name, vehicle recalled.
// iMessage-style voice notes rise from the bottom; each has its own voice wave.

const NEW_CALLER = [
  { role: "agent", text: "Thanks for calling PartsPlace! Who do I have the pleasure of speaking with?" },
  { role: "customer", text: "Hey, this is Chris." },
  { role: "agent", text: "Hey Chris. How can I help you today?" },
  { role: "customer", text: "I'm looking for front brake pads for my 2009 Camry." },
  {
    role: "agent",
    text: "Lemme look that up. I have some Wagner ThermoQuiet fit your Camry, $42.99 a set, four in stock.",
  },
  { role: "customer", text: "Yes, they will work, when can I come by?" },
  { role: "agent", text: "We are open till 5 pm today." },
  { role: "customer", text: "Sounds good, ill be on my way." },


];

const RETURNING_CALLER = [
  { role: "agent", text: "Hey Chris! Good to hear from you — calling about the 2009 Camry?" },
  { role: "customer", text: "Yeah — I need an oil filter this time." },
  {
    role: "agent",
    text: "Easy. Fram fits your Camry — $8.99, six on the shelf. Want it set aside?",
  },
  { role: "customer", text: "Perfect. Thanks!" },
];

const PHASES = [
  { caller: { kind: "new" }, script: NEW_CALLER },
  { caller: { kind: "returning", name: "Chris", id: "103", vehicle: "2009 Camry" }, script: RETURNING_CALLER },
];

const TYPING_MS = 55; // per character (default pace)
const HOLD_MS = 1100; // pause after a line finishes
const LOOP_MS = 2600; // pause after a call ends, before the next one

// Static base heights for the voice wave (px). Deterministic → no SSR mismatch.
const WAVE = Array.from({ length: 36 }, (_, i) => 5 + Math.round(15 * Math.abs(Math.sin(i * 0.8))));

// Drives the loop: types each line, advances turns, then advances phase (call).
function useScriptedCall(phases) {
  const [phase, setPhase] = useState(0);
  const [turn, setTurn] = useState(0);
  const [chars, setChars] = useState(0);

  useEffect(() => {
    const script = phases[phase].script;
    const current = script[turn];

    // call finished → pause, then move to the next call (looping)
    if (!current) {
      const t = setTimeout(() => {
        setPhase((p) => (p + 1) % phases.length);
        setTurn(0);
        setChars(0);
      }, LOOP_MS);
      return () => clearTimeout(t);
    }

    // still typing the current line
    if (chars < current.text.length) {
      const speed = current.typingMs ?? TYPING_MS;
      const t = setTimeout(() => setChars((c) => c + 1), speed);
      return () => clearTimeout(t);
    }

    // line done → next line
    const t = setTimeout(() => {
      setTurn((i) => i + 1);
      setChars(0);
    }, HOLD_MS);
    return () => clearTimeout(t);
  }, [phase, turn, chars, phases]);

  return { phase, turn, chars };
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

// The caller record above the call — "New caller" vs the recognised customer.
function CallerCard({ caller }) {
  if (caller.kind === "returning") {
    return (
      <div className="inline-flex flex-col rounded-lg border border-[#212427]/12 bg-white px-3.5 py-2 shadow-sm">
        <span className="text-[10px] font-bold uppercase tracking-[0.18em] text-foreground/45">
          Returning caller
        </span>
        <span className="mt-0.5 text-sm font-bold">
          {caller.name} · #{caller.id}
        </span>
        <span className="text-xs text-foreground/55">{caller.vehicle}</span>
      </div>
    );
  }
  return (
    <div className="inline-flex items-center gap-2 rounded-lg border border-[#212427]/12 bg-white px-3.5 py-2 shadow-sm">
      <span className="relative flex h-2 w-2">
        <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-foreground/40" />
        <span className="relative inline-flex h-2 w-2 rounded-full bg-foreground" />
      </span>
      <span className="text-[11px] font-bold uppercase tracking-[0.18em] text-foreground/55">
        New caller
      </span>
    </div>
  );
}

export default function CallDemo({ phases = PHASES, fadeClass = "from-background" }) {
  const { phase, turn, chars } = useScriptedCall(phases);
  const { caller, script } = phases[phase];
  const visible = script.slice(0, turn + 1);

  return (
    <div>
      {/* caller record — swaps between New and Returning each loop */}
      <div className="mb-3 min-h-[58px]">
        <AnimatePresence mode="wait">
          <motion.div
            key={phase}
            initial={{ opacity: 0, y: -6 }}
            animate={{ opacity: 1, y: 0 }}
            exit={{ opacity: 0, y: -6 }}
            transition={{ duration: 0.3 }}
          >
            <CallerCard caller={caller} />
          </motion.div>
        </AnimatePresence>
      </div>

      {/* voice notes rising from the bottom; older ones clip behind the top fade */}
      <div className="relative h-72 overflow-hidden">
        <div className={`pointer-events-none absolute inset-x-0 top-0 z-10 h-10 bg-linear-to-b to-transparent ${fadeClass}`} />
        <div className="flex h-full flex-col justify-end gap-2.5">
          <AnimatePresence initial={false}>
            {visible.map((t, i) => {
              const isAgent = t.role === "agent";
              const isTyping = i === turn && chars < t.text.length;
              const text = i === turn ? t.text.slice(0, chars) : t.text;
              return (
                // key includes phase so each new call's bubbles mount fresh and rise
                <motion.div
                  key={`${phase}-${i}`}
                  layout="position"
                  exit={{ opacity: 0, transition: { duration: 0.15 } }}
                  transition={{ type: "spring", stiffness: 420, damping: 34 }}
                >
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

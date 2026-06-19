"use client";

import { useEffect, useRef, useState } from "react";
import { AnimatePresence, motion } from "motion/react";

// ── Live projector dashboard ────────────────────────────────────────────────
// Right now this runs off a scripted mock feed so it's alive on stage today.
// To go real: replace useLiveFeed() with a poll of GET /api/calls + /api/leads
// (or an Insforge realtime subscription). The panels render whatever it returns.

const CALLS = [
  {
    caller: { kind: "returning", name: "Chris", id: "103", phone: "(403) 555-0103", vehicle: "2009 Camry" },
    lines: [
      { who: "agent", text: "Hey Chris! Calling about the 2009 Camry?" },
      { who: "customer", text: "Yeah — need front brake pads." },
      { who: "agent", text: "Wagner ThermoQuiet fit your Camry — $42.99, four in stock." },
    ],
    result: { type: "hit", part: { name: "Brake Pads — Front", brand: "Wagner ThermoQuiet", sku: "ZD1210", price: 42.99, qty: 4, shelf: "B12" } },
  },
  {
    caller: { kind: "new", name: "Dana", phone: "(403) 555-0192", vehicle: "2015 F-150" },
    lines: [
      { who: "agent", text: "Thanks for calling PartsPlace — what can I get you?" },
      { who: "customer", text: "Cabin air filter for a 2015 F-150." },
      { who: "agent", text: "Not on the shelf today — I'll take your number and have it ordered." },
    ],
    result: { type: "miss", part: "Cabin air filter" },
  },
  {
    caller: { kind: "returning", name: "Maria", id: "088", phone: "(403) 555-0088", vehicle: "2012 Civic" },
    lines: [
      { who: "agent", text: "Welcome back, Maria! The 2012 Civic again?" },
      { who: "customer", text: "Yep — just an oil filter." },
      { who: "agent", text: "Mobil 1 M1-110A — $11.49, nine on the shelf." },
    ],
    result: { type: "hit", part: { name: "Oil Filter", brand: "Mobil 1", sku: "M1-110A", price: 11.49, qty: 9, shelf: "A4" } },
  },
  {
    caller: { kind: "new", name: "Tom", phone: "(403) 555-0211", vehicle: "2018 Silverado" },
    lines: [
      { who: "agent", text: "PartsPlace, how can I help?" },
      { who: "customer", text: "Need an alternator for an '18 Silverado." },
      { who: "agent", text: "Not in stock right now — taking your number for a callback." },
    ],
    result: { type: "miss", part: "Alternator" },
  },
  {
    caller: { kind: "returning", name: "Sam", id: "054", phone: "(403) 555-0054", vehicle: "2007 Tacoma" },
    lines: [
      { who: "agent", text: "Hey Sam — the 2007 Tacoma?" },
      { who: "customer", text: "Yeah, a set of spark plugs." },
      { who: "agent", text: "NGK Laser Iridium, set of four — $56, eight in stock." },
    ],
    result: { type: "hit", part: { name: "Spark Plugs (set of 4)", brand: "NGK Laser Iridium", sku: "SILZKR7B11", price: 56.0, qty: 8, shelf: "C2" } },
  },
];

const INITIAL_HITS = [
  { id: 1, name: "Oil Filter", brand: "Fram", sku: "PH7317", price: 8.99, qty: 6, shelf: "A4", time: "9:42" },
  { id: 2, name: "Spark Plugs (4)", brand: "NGK Iridium", sku: "BKR6EIX", price: 38.5, qty: 12, shelf: "C2", time: "9:39" },
  { id: 3, name: "Air Filter", brand: "Wix", sku: "49065", price: 21.99, qty: 5, shelf: "A7", time: "9:31" },
];

const INITIAL_LEADS = [
  { id: 11, name: "Jordan", phone: "(403) 555-0148", part: "Timing belt kit", vehicle: "2013 Sonata", time: "9:40" },
  { id: 12, name: "Riley", phone: "(403) 555-0177", part: "Headlight assembly (L)", vehicle: "2016 RAV4", time: "9:28" },
];

const LINE_MS = 1500; // gap between transcript lines
const RESULT_MS = 1500; // pause after the last line before the call resolves

function useLiveFeed() {
  const [callIdx, setCallIdx] = useState(0);
  const [lineCount, setLineCount] = useState(0);
  const [hits, setHits] = useState(INITIAL_HITS);
  const [leads, setLeads] = useState(INITIAL_LEADS);
  const [hitsCount, setHitsCount] = useState(71);
  const [leadsCount, setLeadsCount] = useState(22);
  const [now, setNow] = useState(null);
  const idRef = useRef(1000);

  // live clock
  useEffect(() => {
    setNow(new Date());
    const t = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(t);
  }, []);

  // call driver: reveal lines → resolve (hit/lead) → next call, looping
  useEffect(() => {
    const call = CALLS[callIdx];
    if (lineCount < call.lines.length) {
      const t = setTimeout(() => setLineCount((c) => c + 1), LINE_MS);
      return () => clearTimeout(t);
    }
    const t = setTimeout(() => {
      const time = new Date().toLocaleTimeString([], { hour: "numeric", minute: "2-digit" });
      const id = ++idRef.current;
      if (call.result.type === "hit") {
        setHits((h) => [{ id, ...call.result.part, time }, ...h].slice(0, 7));
        setHitsCount((n) => n + 1);
      } else {
        setLeads((l) => [
          { id, name: call.caller.name, phone: call.caller.phone, part: call.result.part, vehicle: call.caller.vehicle, time },
          ...l,
        ].slice(0, 7));
        setLeadsCount((n) => n + 1);
      }
      setCallIdx((i) => (i + 1) % CALLS.length);
      setLineCount(0);
    }, RESULT_MS);
    return () => clearTimeout(t);
  }, [callIdx, lineCount]);

  const call = CALLS[callIdx];
  const resolving = lineCount >= call.lines.length;
  const callsToday = hitsCount + leadsCount;
  const inStock = Math.round((hitsCount / callsToday) * 100);

  return { call, lineCount, resolving, hits, leads, seq: callsToday, stats: { callsToday, inStock, leadsCount }, now };
}

function LiveDot({ className = "" }) {
  return (
    <span className={`relative flex h-2.5 w-2.5 ${className}`}>
      <span className="absolute inline-flex h-full w-full animate-ping rounded-full bg-[#1F9D55]/50" />
      <span className="relative inline-flex h-2.5 w-2.5 rounded-full bg-[#1F9D55]" />
    </span>
  );
}

function StatCard({ label, value, accent }) {
  const accentClass =
    accent === "green" ? "text-[#1F9D55]" : accent === "teal" ? "text-[#1D3A40]" : "text-foreground";
  return (
    <div className="rounded-2xl border border-[#212427]/10 bg-white p-5 shadow-sm">
      <div className="text-xs font-bold uppercase tracking-[0.18em] text-foreground/45">{label}</div>
      <div className={`mt-2 font-serif text-4xl tabular-nums ${accentClass}`}>{value}</div>
    </div>
  );
}

function Panel({ title, badge, className = "", children }) {
  return (
    <section className={`flex min-h-[28rem] flex-col rounded-2xl border border-[#212427]/10 bg-white p-5 shadow-sm ${className}`}>
      <div className="mb-4 flex items-center justify-between">
        <h2 className="text-xs font-bold uppercase tracking-[0.18em] text-foreground/45">{title}</h2>
        {badge}
      </div>
      {children}
    </section>
  );
}

function CallerCard({ caller }) {
  const returning = caller.kind === "returning";
  return (
    <div
      className={`flex items-center justify-between rounded-xl border p-3 ${returning ? "border-[#1D3A40]/25 bg-[#1D3A40]/5" : "border-[#212427]/10 bg-background"
        }`}
    >
      <div className="min-w-0">
        <div className="flex items-center gap-2">
          <span className="truncate text-sm font-bold">
            {caller.name}
            {returning && ` · #${caller.id}`}
          </span>
          <span
            className={`rounded-full px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-background ${returning ? "bg-[#1D3A40]" : "bg-foreground"
              }`}
          >
            {returning ? "Returning" : "New"}
          </span>
        </div>
        <div className="mt-0.5 truncate text-xs text-foreground/55">
          {caller.vehicle} · {caller.phone}
        </div>
      </div>
      <LiveDot />
    </div>
  );
}

function CallPanel({ call, lineCount, resolving, seq }) {
  const visible = call.lines.slice(0, lineCount);
  return (
    <div className="flex flex-1 flex-col">
      <CallerCard caller={call.caller} />

      <div className="mt-4 flex flex-1 flex-col justify-end gap-2 overflow-hidden">
        <AnimatePresence initial={false}>
          {visible.map((l, i) => {
            const isAgent = l.who === "agent";
            return (
              <motion.div
                key={`${seq}-${i}`}
                layout="position"
                initial={{ opacity: 0, y: 12, scale: 0.98 }}
                animate={{ opacity: 1, y: 0, scale: 1 }}
                exit={{ opacity: 0, transition: { duration: 0.15 } }}
                transition={{ type: "spring", stiffness: 420, damping: 34 }}
                className={`flex ${isAgent ? "justify-start" : "justify-end"}`}
              >
                <div
                  className={`max-w-[85%] rounded-2xl px-3.5 py-2 text-sm leading-snug ${isAgent ? "bg-foreground text-background" : "bg-[#1D3A40] text-background"
                    }`}
                >
                  {l.text}
                </div>
              </motion.div>
            );
          })}
        </AnimatePresence>
      </div>

      <div className="mt-4 flex items-center gap-2 border-t border-[#212427]/10 pt-3 text-xs font-semibold text-foreground/55">
        {resolving ? (
          <>
            <span className="h-2.5 w-2.5 animate-spin rounded-full border-2 border-foreground/30 border-t-foreground" />
            Checking inventory…
          </>
        ) : (
          <>
            <LiveDot />
            Listening…
          </>
        )}
      </div>
    </div>
  );
}

function rowAnim(extra = "") {
  return {
    layout: true,
    initial: { opacity: 0, y: -10, scale: 0.98 },
    animate: { opacity: 1, y: 0, scale: 1 },
    transition: { type: "spring", stiffness: 380, damping: 30 },
    className: extra,
  };
}

export default function Dashboard() {
  const { call, lineCount, resolving, hits, leads, seq, stats, now } = useLiveFeed();
  const clock = now
    ? now.toLocaleTimeString([], { hour: "2-digit", minute: "2-digit", second: "2-digit" })
    : "";

  return (
    <main className="min-h-screen bg-background text-foreground">
      {/* header */}
      <header className="flex items-center justify-between border-b border-[#212427]/10 px-8 py-5">
        <div className="flex items-baseline gap-3">
          <span className="font-brand text-xl font-extrabold tracking-tight">PartsPanda</span>
          <span className="text-sm text-foreground/45">Live Dashboard</span>
        </div>
        <div className="flex items-center gap-6">
          <span className="text-sm text-foreground/55">PartsPlace · Calgary</span>
          <span className="flex items-center gap-2">
            <LiveDot />
            <span className="text-xs font-bold uppercase tracking-widest text-foreground/70">Live</span>
          </span>
          <span className="w-[5.5rem] text-right text-sm font-semibold tabular-nums text-foreground/70">
            {clock}
          </span>
        </div>
      </header>

      {/* stat strip */}
      <div className="grid grid-cols-2 gap-4 px-8 pt-6 sm:grid-cols-4">
        <StatCard label="Calls today" value={stats.callsToday} />
        <StatCard label="Answered" value="100%" accent="green" />
        <StatCard label="In-stock rate" value={`${stats.inStock}%`} />
        <StatCard label="Leads captured" value={stats.leadsCount} accent="teal" />
      </div>

      {/* panels */}
      <div className="grid grid-cols-1 gap-4 px-8 py-6 lg:grid-cols-12">
        <Panel
          title="Live call"
          className="lg:col-span-5"
          badge={
            <span className="flex items-center gap-1.5 text-[11px] font-bold uppercase tracking-widest text-[#1F9D55]">
              <LiveDot /> On air
            </span>
          }
        >
          <CallPanel call={call} lineCount={lineCount} resolving={resolving} seq={seq} />
        </Panel>

        <Panel
          title="Inventory hits"
          className="lg:col-span-3"
          badge={<span className="text-xs font-semibold text-foreground/45">{stats.inStock}% in stock</span>}
        >
          <div className="flex flex-col gap-2.5">
            <AnimatePresence initial={false}>
              {hits.map((h) => (
                <motion.div key={h.id} {...rowAnim("flex items-center gap-3 rounded-xl border border-[#212427]/10 bg-white p-3")}>
                  <div className="flex h-9 w-9 shrink-0 items-center justify-center rounded-lg bg-[#1F9D55]/12 text-[#1F9D55]">
                    <svg viewBox="0 0 20 20" className="h-4 w-4" fill="none" stroke="currentColor" strokeWidth="2.5" strokeLinecap="round" strokeLinejoin="round">
                      <path d="M4 10 L8 14 L16 5" />
                    </svg>
                  </div>
                  <div className="min-w-0 flex-1">
                    <div className="truncate text-sm font-bold">{h.name}</div>
                    <div className="truncate text-xs text-foreground/55">{h.brand} · {h.sku}</div>
                  </div>
                  <div className="text-right">
                    <div className="font-serif text-base tabular-nums">${h.price.toFixed(2)}</div>
                    <div className="text-[11px] text-foreground/55">{h.qty} · {h.shelf}</div>
                  </div>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </Panel>

        <Panel
          title="Leads captured"
          className="lg:col-span-4"
          badge={<span className="text-xs font-semibold text-[#1D3A40]">{stats.leadsCount} today</span>}
        >
          <div className="flex flex-col gap-2.5">
            <AnimatePresence initial={false}>
              {leads.map((l) => (
                <motion.div key={l.id} {...rowAnim("rounded-xl border border-[#1D3A40]/20 bg-white p-3")}>
                  <div className="flex items-center justify-between">
                    <span className="text-sm font-bold">{l.name}</span>
                    <span className="text-[11px] text-foreground/45">{l.time}</span>
                  </div>
                  <div className="mt-0.5 text-xs text-foreground/70">
                    Wants: <span className="font-semibold text-foreground">{l.part}</span>
                  </div>
                  <div className="text-xs text-foreground/55">{l.vehicle} · {l.phone}</div>
                  <span className="mt-2 inline-flex rounded-full bg-[#1D3A40] px-2 py-0.5 text-[10px] font-bold uppercase tracking-wide text-background">
                    Callback queued
                  </span>
                </motion.div>
              ))}
            </AnimatePresence>
          </div>
        </Panel>
      </div>
    </main>
  );
}

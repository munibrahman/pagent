// pagent — landing page
// Palette: bg #F3F2E6 · alt panel #ECEADA · text #212427
// Type: Hedvig Letters Serif (headers) · Lato (everything else)
// Sections alternate: transparent (bleeds to bg) → alt panel → transparent ...

function Section({ id, alt = false, children }) {
  return (
    <section id={id} className={alt ? "bg-surface-alt" : ""}>
      <div className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-24">
        {children}
      </div>
    </section>
  );
}

function CallAgentButton({ children = "Call the agent →" }) {
  // Primary CTA — wired to the live Vapi demo number (placeholder for now).
  return (
    <a
      href="tel:+14030000000"
      className="inline-flex items-center justify-center rounded-md bg-foreground px-5 py-3 text-sm font-bold text-background transition-opacity hover:opacity-90"
    >
      {children}
    </a>
  );
}

const cardClass =
  "rounded-xl border border-[#212427]/12 p-5";

// Everything an independent auto parts store actually runs. Placeholder text
// chips now → real logos in polish. Two rows, scrolling opposite directions.
// Row A — POS / inventory / dealer-management systems.
const POS_SYSTEMS = [
  "Epicor Eagle",
  "Epicor Vision",
  "Epicor Vista",
  "MAM Autopart",
  "NAPA TAMS",
  "Triad",
  "Activant",
  "NCR Counterpoint",
  "RockSolid MAX",
  "Autologue",
  "Karmak Fusion",
  "Freedom Data Systems",
  "Internet Autoparts",
  "WHI Nexpart",
];

// Row B — store banners / networks + catalog & fitment data standards.
const NETWORKS = [
  "NAPA",
  "Auto Value",
  "Carquest",
  "Bumper to Bumper",
  "Pronto",
  "Federated Auto Parts",
  "Parts Plus",
  "O'Reilly Auto Parts",
  "Advance Auto Parts",
  "AutoZone",
  "Worldpac",
  "Parts Alliance",
  "ACES / PIES",
  "MOTOR",
];

function MarqueeRow({ items, reverse = false }) {
  // List rendered twice; track slides -50% for a seamless infinite loop.
  // Spacing lives on each chip (mr) so the loop point aligns exactly.
  // Hovering pauses the row so a logo can actually be read.
  return (
    <div className="overflow-hidden">
      <div
        className={`flex w-max hover:[animation-play-state:paused] ${
          reverse ? "animate-marquee-reverse" : "animate-marquee"
        }`}
      >
        {[...items, ...items].map((name, i) => (
          <span
            key={i}
            className="mr-3 whitespace-nowrap rounded-md border border-[#212427]/10 bg-surface-alt px-4 py-2 text-sm text-foreground/70"
          >
            {name}
          </span>
        ))}
      </div>
    </div>
  );
}

function Eyebrow({ children }) {
  return (
    <div className="text-xs font-bold uppercase tracking-[0.18em] text-foreground/45">
      {children}
    </div>
  );
}

function SystemsMarquee() {
  return (
    <div className="mt-12">
      <Eyebrow>Built to integrate with the systems you already run</Eyebrow>
      <div className="mt-4 flex flex-col gap-3 border-y border-[#212427]/10 py-4">
        <MarqueeRow items={POS_SYSTEMS} />
        <MarqueeRow items={NETWORKS} reverse />
      </div>
    </div>
  );
}

export default function Home() {
  return (
    <main className="flex flex-col">
      {/* ── NAV ───────────────────────────────────────────── */}
      <nav className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-5">
        <span className="font-serif text-xl">pagent</span>
        <div className="flex items-center gap-6 text-sm">
          <a href="#how" className="hover:opacity-70">
            How it works
          </a>
          <a href="#pricing" className="hover:opacity-70">
            Pricing
          </a>
          <CallAgentButton>Call the agent</CallAgentButton>
        </div>
      </nav>

      {/* ── HOOK ──────────────────────────────────────────── */}
      <Section>
        <h1 className="max-w-3xl font-serif text-4xl leading-[1.05] sm:text-6xl">
          Stop losing sales to a ringing phone.
        </h1>
        <p className="mt-5 max-w-xl text-lg text-foreground/70">
          pagent answers every call to your parts counter, checks your real
          inventory, and quotes price and availability — 24/7. No hold music.
          No missed orders.
        </p>
        <div className="mt-8 flex flex-wrap items-center gap-5">
          <CallAgentButton />
          <a href="#pricing" className="text-sm underline underline-offset-4">
            See pricing
          </a>
        </div>

        {/* Integrations carousel — the "we connect to what you run" signal */}
        <SystemsMarquee />
      </Section>

      {/* ── THE STAKES ────────────────────────────────────── */}
      <Section alt>
        <h2 className="max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Every call you miss is a sale at the next store.
        </h2>
        <p className="mt-5 max-w-xl text-foreground/70">
          Your counter is slammed. The phone rings twice and stops — that
          mechanic already dialed the competitor down the road. After close,
          nobody&apos;s there at all. Those are orders you&apos;ll never even
          know you lost.
        </p>
        <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {[
            ["500+", "calls a day at a busy counter"],
            ["1 in 4", "go unanswered at peak hours"],
            ["0", "answered after you close"],
          ].map(([big, small]) => (
            <div key={small} className={cardClass}>
              <div className="font-serif text-3xl">{big}</div>
              <div className="mt-1 text-sm text-foreground/60">{small}</div>
            </div>
          ))}
        </div>
      </Section>

      {/* ── THE FIX ───────────────────────────────────────── */}
      <Section>
        <h2 className="max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Meet pagent — the counter person who never clocks out.
        </h2>
        <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {[
            ["Answers instantly", "Every call, every time. No hold, no voicemail."],
            ["Knows your stock", "Real inventory, real prices, real shelf location."],
            ["Never drops a lead", "Takes the order — or the callback — even at 2am."],
          ].map(([title, body]) => (
            <div key={title} className={cardClass}>
              <div className="font-bold">{title}</div>
              <div className="mt-1 text-sm text-foreground/60">{body}</div>
            </div>
          ))}
        </div>
      </Section>

      {/* ── PROOF / LIVE CALL (primary conversion) ────────── */}
      <Section alt>
        <h2 className="max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Don&apos;t take our word for it. Call it.
        </h2>
        <p className="mt-5 max-w-xl text-foreground/70">
          Pick up your phone and talk to the agent right now. Ask it for a part.
        </p>
        <div className="mt-10 rounded-2xl border border-[#212427]/15 bg-background p-8 text-center">
          <Eyebrow>Live agent</Eyebrow>
          <div className="mt-3 font-serif text-4xl">(403) 000-0000</div>
          <div className="mt-7">
            <CallAgentButton>Call now</CallAgentButton>
          </div>
        </div>
      </Section>

      {/* ── HOW IT WORKS ──────────────────────────────────── */}
      <Section id="how">
        <h2 className="font-serif text-3xl leading-tight sm:text-4xl">
          How it works
        </h2>
        <ol className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {[
            ["1", "Caller asks for a part", "“You got front brake pads for a 2015 Camry?”"],
            ["2", "pagent checks your inventory", "Understands the request, looks up live stock."],
            ["3", "It closes the loop", "Quotes price + availability, or takes the order."],
          ].map(([n, title, body]) => (
            <li key={n} className={cardClass}>
              <div className="font-serif text-2xl text-foreground/40">{n}</div>
              <div className="mt-3 font-bold">{title}</div>
              <div className="mt-1 text-sm text-foreground/60">{body}</div>
            </li>
          ))}
        </ol>
      </Section>

      {/* ── PRICING (Stripe TODO) ─────────────────────────── */}
      <Section id="pricing" alt>
        <h2 className="font-serif text-3xl leading-tight sm:text-4xl">
          Pricing
        </h2>
        <p className="mt-3 text-sm text-foreground/50">
          Plans + features TBD — placeholder cards. Stripe checkout links go on
          the buttons.
        </p>
        <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {[
            ["Starter", "$X/mo", ["1 store", "Up to N calls/mo", "Inventory lookup"]],
            ["Pro", "$X/mo", ["1 store", "More calls", "Lead capture + dashboard"]],
            ["Multi-store", "Contact", ["2–5 stores", "Unlimited calls", "Priority support"]],
          ].map(([name, price, feats]) => (
            <div
              key={name}
              className="flex flex-col rounded-xl border border-[#212427]/12 bg-background p-6"
            >
              <div className="font-bold">{name}</div>
              <div className="mt-1 font-serif text-3xl">{price}</div>
              <ul className="mt-4 flex-1 space-y-1.5 text-sm text-foreground/60">
                {feats.map((f) => (
                  <li key={f}>— {f}</li>
                ))}
              </ul>
              <button
                type="button"
                className="mt-6 rounded-md border border-foreground px-4 py-2 text-sm font-bold transition-colors hover:bg-foreground hover:text-background"
              >
                Choose {name}
              </button>
            </div>
          ))}
        </div>
      </Section>

      {/* ── FINAL CTA ─────────────────────────────────────── */}
      <Section>
        <h2 className="font-serif text-3xl leading-tight sm:text-5xl">
          Never miss another order.
        </h2>
        <div className="mt-8">
          <CallAgentButton />
        </div>
      </Section>

      {/* ── FOOTER ────────────────────────────────────────── */}
      <footer className="bg-surface-alt">
        <div className="mx-auto w-full max-w-5xl px-6 py-8 text-sm text-foreground/50">
          pagent — built for independent auto parts stores.
        </div>
      </footer>
    </main>
  );
}

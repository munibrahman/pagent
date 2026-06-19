// PartsPanda — landing page
// Palette: bg #F3F2E6 · alt panel #ECEADA · text #212427
// Type: Hedvig Letters Serif (headers) · Lato (everything else)
// Sections alternate: transparent (bleeds to bg) → alt panel → transparent ...

import { Fragment } from "react";
import CallDemo from "./components/CallDemo";

function Section({ id, alt = false, children }) {
  return (
    <section id={id} className={alt ? "bg-surface-alt" : ""}>
      <div className="mx-auto w-full max-w-5xl px-6 py-20 sm:py-24">
        {children}
      </div>
    </section>
  );
}

function CallAgentButton({ children = "Try it yourself" }) {
  // Primary CTA — wired to the live Vapi demo number (placeholder for now).
  return (
    <a
      href="tel:+19289889317"
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
        className={`flex w-max hover:[animation-play-state:paused] ${reverse ? "animate-marquee-reverse" : "animate-marquee"
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

// Cartoon panda peeking over the wordmark — looking right at you.
function PandaPeek({ className = "" }) {
  return (
    <svg viewBox="0 0 100 82" className={className} aria-hidden>
      {/* ears */}
      <circle cx="27" cy="24" r="14" fill="#212427" />
      <circle cx="73" cy="24" r="14" fill="#212427" />
      {/* face */}
      <ellipse cx="50" cy="42" rx="33" ry="29" fill="#fff" stroke="#212427" strokeWidth="3" />
      {/* eye patches */}
      <ellipse cx="37" cy="42" rx="9" ry="12" fill="#212427" transform="rotate(-20 37 42)" />
      <ellipse cx="63" cy="42" rx="9" ry="12" fill="#212427" transform="rotate(20 63 42)" />
      {/* eyes (looking at you) */}
      <circle cx="38" cy="43" r="4.5" fill="#fff" />
      <circle cx="62" cy="43" r="4.5" fill="#fff" />
      <circle cx="39" cy="44" r="2.3" fill="#212427" />
      <circle cx="61" cy="44" r="2.3" fill="#212427" />
      {/* nose + mouth */}
      <ellipse cx="50" cy="56" rx="5" ry="3.5" fill="#212427" />
      <path
        d="M50 59 Q45 64 41 61 M50 59 Q55 64 59 61"
        fill="none"
        stroke="#212427"
        strokeWidth="2"
        strokeLinecap="round"
      />
      {/* little paws gripping the edge */}
      <circle cx="19" cy="75" r="7" fill="#212427" />
      <circle cx="81" cy="75" r="7" fill="#212427" />
    </svg>
  );
}

// Memory section — the three steps that weave into retention growth.
const MEMORY_STEPS = [
  ["Knows who's calling", "Greet returning callers by name"],
  ["Recall their vehicle", "Speed up lookup times"],
  ["Turns calls into regulars", "Familiarity is retention and retention is recurring revenue."],
];

// Animated weaving dashed line that connects the memory steps.
function WeaveConnector() {
  return (
    <div className="hidden h-6 w-16 shrink-0 lg:block">
      <svg viewBox="0 0 64 24" preserveAspectRatio="none" className="h-full w-full" aria-hidden>
        <path
          d="M0,12 Q16,2 32,12 T64,12"
          fill="none"
          stroke="#212427"
          strokeOpacity="0.4"
          strokeWidth="2"
          strokeLinecap="round"
          strokeDasharray="5 6"
          className="animate-dash"
        />
      </svg>
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

// Pricing tiers. Checkout hrefs come from env (Stripe Payment Links).
const PLANS = [
  {
    name: "Starter",
    price: "$129",
    period: "/mo",
    tagline: "Everything you need to stop missing calls.",
    features: [
      "1 location",
      "100 calls / mo included",
      "Then $1.25 / call",
      "Answers every call, 24/7",
      "Live inventory lookup",
      "Lead capture",
    ],
    cta: "Start free trial",
    href: process.env.NEXT_PUBLIC_STRIPE_STARTER_URL || "#",
    featured: false,
  },
  {
    name: "Pro",
    price: "$299",
    period: "/mo",
    tagline: "Retention and insight that pay for themselves.",
    features: [
      "Up to 3 locations",
      "240 calls / mo included",
      "Then $1.25 / call",
      "Everything in Starter",
      "Customer memory",
      "VIN decode",
      "Live dashboard",
    ],
    cta: "Start free trial",
    href: process.env.NEXT_PUBLIC_STRIPE_PRO_URL || "#",
    featured: true,
  },
  {
    name: "Multi-store",
    price: "Custom",
    period: "",
    tagline: "For groups and growing chains.",
    features: [
      "4+ locations",
      "Everything in Pro",
      "POS integrations",
      "Priority support",
      "Dedicated number per store",
    ],
    cta: "Talk to us",
    href: "mailto:hello@partspanda.com",
    featured: false,
  },
];

function Check() {
  return (
    <svg
      viewBox="0 0 20 20"
      className="mt-0.5 h-4 w-4 shrink-0 text-[#1F9D55]"
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      <path d="M4 10 L8 14 L16 5" />
    </svg>
  );
}

// Directional trend arrow (up = rising, down = falling). Colour via text class.
function Trend({ up, colorClass }) {
  return (
    <svg
      viewBox="0 0 24 24"
      className={`h-5 w-5 ${colorClass}`}
      fill="none"
      stroke="currentColor"
      strokeWidth="2.5"
      strokeLinecap="round"
      strokeLinejoin="round"
      aria-hidden
    >
      {up ? (
        <>
          <path d="M4 16 L10 10 L14 14 L20 6" />
          <path d="M14 6 L20 6 L20 12" />
        </>
      ) : (
        <>
          <path d="M4 8 L10 14 L14 10 L20 18" />
          <path d="M14 18 L20 18 L20 12" />
        </>
      )}
    </svg>
  );
}

// Stakes stats — arrows: call volume up (green), misses up (amber), zero answered down (red).
const STAKES = [
  { big: "500+", small: "calls a day at a busy counter", up: true, colorClass: "text-[#1F9D55]" },
  { big: "1 in 4", small: "go unanswered at peak hours", up: true, colorClass: "text-[#D97706]" },
  { big: "0", small: "answered after you close", up: false, colorClass: "text-[#DC2626]" },
];

function PlanCard({ plan }) {
  const { name, price, period, tagline, features, cta, href, featured } = plan;
  return (
    <div
      className={`relative flex flex-col rounded-2xl bg-white p-7 ${featured
        ? "border-2 border-[#1D3A40] shadow-md"
        : "border border-[#212427]/10 shadow-sm"
        }`}
    >
      {featured && (
        <span className="absolute -top-3 left-7 rounded-full bg-[#1D3A40] px-3 py-1 text-[11px] font-bold uppercase tracking-wide text-background">
          Most popular
        </span>
      )}
      <div className="font-bold">{name}</div>
      <div className="mt-2 flex items-baseline gap-1">
        <span className="font-serif text-4xl">{price}</span>
        {period && <span className="text-sm text-foreground/50">{period}</span>}
      </div>
      <p className="mt-2 text-sm text-foreground/60">{tagline}</p>
      <ul className="mt-6 flex-1 space-y-2.5 text-sm">
        {features.map((f) => (
          <li key={f} className="flex gap-2">
            <Check />
            <span>{f}</span>
          </li>
        ))}
      </ul>
      <a
        href={href}
        className={`mt-7 inline-flex items-center justify-center rounded-md px-4 py-2.5 text-sm font-bold transition-colors ${featured
          ? "bg-foreground text-background hover:opacity-90"
          : "border border-foreground hover:bg-foreground hover:text-background"
          }`}
      >
        {cta}
      </a>
    </div>
  );
}

export default function Home() {
  return (
    <main className="flex flex-col">
      {/* ── NAV ───────────────────────────────────────────── */}
      <nav className="mx-auto flex w-full max-w-5xl items-center justify-between px-6 py-5">
        <span className="relative inline-block">
          <PandaPeek className="pointer-events-none absolute -top-4 left-1/2 h-7 w-auto -translate-x-1/2" />
          <span className="font-brand text-xl font-extrabold tracking-tight">
            PartsPanda
          </span>
        </span>
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
        <div className="grid items-center gap-10 lg:grid-cols-5">
          {/* left — the pitch */}
          <div className="lg:col-span-3">
            <h1 className="font-serif text-4xl leading-[1.05] sm:text-6xl">
              Every missed call goes to your competition
            </h1>
            <p className="mt-5 max-w-xl text-lg text-foreground/70">
              Your parts store needs someone that always picks calls, knows your customer, and quotes parts straight from your shelf — day or
              night.
            </p>
            <div className="mt-8 flex flex-wrap items-center gap-5">
              <CallAgentButton />
            </div>
          </div>

          {/* right — the live call demo (floats, no card) */}
          <div className="lg:col-span-2">
            <CallDemo />
          </div>
        </div>

        {/* Integrations carousel — the "we connect to what you run" signal */}
        {/* <SystemsMarquee /> */}
      </Section>

      {/* ── THE STAKES ────────────────────────────────────── */}
      <Section alt>
        <h2 className="max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Automate your inbound
        </h2>
        <p className="mt-5 max-w-xl text-foreground/70">
          This is usually your biggest funnel. If the phone rings and drops or goes on hold — that
          customer will call the competition down the road.
        </p>
        <div className="mt-10 grid grid-cols-1 gap-4 sm:grid-cols-3">
          {STAKES.map(({ big, small, up, colorClass }) => (
            <div
              key={small}
              className="flex flex-col rounded-xl border border-[#212427]/10 bg-white p-6 shadow-sm"
            >
              <div className="flex items-start justify-between">
                <span className="font-serif text-4xl">{big}</span>
                <Trend up={up} colorClass={colorClass} />
              </div>
              <span className="mt-2 text-sm text-foreground/60">{small}</span>
            </div>
          ))}
        </div>
        <p className="mt-5 max-w-xl text-foreground/70">Partspanda makes sure you never miss another call. Even after your store is closed.</p>
      </Section>

      {/* ── MEMORY / RETENTION ────────────────────────────── */}
      <Section>
        <Eyebrow>Customer memory</Eyebrow>
        <h2 className="mt-3 max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Remember your customers
        </h2>
        <p className="mt-5 max-w-xl text-foreground/70">
          Nothing beats a personal touch. Recall their name and purchase history to close sales faster.
        </p>

        {/* three steps weaving toward retention */}
        <div className="mt-14 flex flex-col gap-6 lg:flex-row lg:items-center">
          {MEMORY_STEPS.map(([title, body], i) => {
            const isLast = i === MEMORY_STEPS.length - 1;
            return (
              <Fragment key={title}>
                <div className="flex flex-1 flex-col rounded-xl border border-[#212427]/10 bg-white p-5 shadow-sm lg:aspect-video">
                  <div className="flex items-start justify-between">
                    <span className="font-serif text-2xl text-foreground/30">{i + 1}</span>
                    {isLast && (
                      <span className="flex items-center gap-1 font-serif text-lg font-bold text-[#1F9D55]">
                        <svg
                          viewBox="0 0 24 24"
                          className="h-4 w-4"
                          fill="none"
                          stroke="currentColor"
                          strokeWidth="2.5"
                          strokeLinecap="round"
                          strokeLinejoin="round"
                          aria-hidden
                        >
                          <path d="M4 16 L10 10 L14 14 L20 6" />
                          <path d="M14 6 L20 6 L20 12" />
                        </svg>
                        +23%
                      </span>
                    )}
                  </div>
                  <div className="mt-auto pt-4">
                    <div className="font-bold">{title}</div>
                    <div className="mt-1 text-sm text-foreground/60">{body}</div>
                  </div>
                </div>
                {!isLast && <WeaveConnector />}
              </Fragment>
            );
          })}
        </div>
      </Section>

      {/* ── PROOF / LIVE CALL (primary conversion) ────────── */}
      <Section alt>
        <h2 className="max-w-2xl font-serif text-3xl leading-tight sm:text-4xl">
          Try it for yourself
        </h2>
        <p className="mt-5 max-w-xl text-foreground/70">
          Say hello to your newest employee - that never sleeps.
        </p>
        <div className="mt-10 rounded-2xl border border-[#212427]/10 bg-white p-8 text-center shadow-sm">
          <Eyebrow>Live agent</Eyebrow>
          <div className="mt-3 font-serif text-4xl">(928) 988-9317</div>
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
            ["2", "PartsPanda checks your inventory", "Understands the request, looks up live stock."],
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

      {/* ── PRICING ───────────────────────────────────────── */}
      <Section id="pricing" alt>
        <h2 className="font-serif text-2xl leading-tight sm:text-4xl">
          A single missed call could cost you more than a months subscription.
        </h2>
        <p className="mt-3 max-w-xl text-foreground/70">
          Try free for 7 days, cancel anytime.
        </p>
        <div className="mt-12 grid grid-cols-1 items-stretch gap-6 lg:grid-cols-3">
          {PLANS.map((plan) => (
            <PlanCard key={plan.name} plan={plan} />
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
          PartsPanda — built for independent auto parts stores.
        </div>
      </footer>
    </main>
  );
}

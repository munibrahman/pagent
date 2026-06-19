<!-- BEGIN:nextjs-agent-rules -->
# This is NOT the Next.js you know

This version has breaking changes — APIs, conventions, and file structure may all differ from your training data. Read the relevant guide in `node_modules/next/dist/docs/` before writing any code. Heed deprecation notices.
<!-- END:nextjs-agent-rules -->

# PartsPanda (repo dir: `pagent`)

A voice agent that replaces the front-counter person at independent auto parts
stores (NAPA / Auto Value / Carquest, etc.). A caller asks for a part → the agent
interprets it → checks the store's real inventory → quotes price & availability →
captures a lead if it's a miss. **This repo is the marketing site + live dashboard
(frontend).** The voice/backend pipeline lives separately (see "The system" below).

## Context: this is a hackathon build

- **Event:** Gravitational Ventures hackathon. Sponsors with prize tracks:
  **Nebius** (LLM inference), **Vapi** (voice), **Insforge** (backend).
  Anthropic is NOT a prize sponsor.
- **Strategic point:** the closest competitor (AutoPartsAgent.ai, ~50¢/call, already
  shipping) runs on Claude — but at this event prize money flows to Nebius/Vapi/Insforge,
  so the brain runs on a **Nebius open model**, not Claude. One pipeline = eligible for
  every track.
- **Primary prize target:** Vapi's **$1,000 "Most Commercially Viable"** — won on the
  market story (thousands of independent owner-operators; missed call = lost order).
- **Deadline:** 3:00 PM. Team of 2: **Munib** = marketing / frontend / UI (this repo);
  **Mayer** = backend / voice (separate, see `BACKEND_SPEC.md`).

## The system (full pipeline — for context)

```
Vapi (answers call, speech↔text)
  → Nebius open model (interprets "front brake pads, 2015 Camry")
  → model calls a TOOL → Insforge edge fn queries seeded inventory
  → structured answer returned → Vapi speaks it
  → every call + every miss logged to Insforge (this dashboard reads those)
```

Key principle: the LLM never stores/guesses inventory — it only translates speech into a
tool call. Truth lives in the database. Side-quest: VIN decode via the free NHTSA vPIC API.

The backend contract (4 endpoints, table schemas, Vapi tool shapes, Nebius config) is
fully specified in **`BACKEND_SPEC.md`** — that's Mayer's spec and the integration contract.
Endpoints the frontend dashboard will eventually consume:
`GET /api/inventory`, `POST /api/check_inventory`, `GET /api/calls`, `GET /api/leads`.

## This repo (frontend)

- **Framework:** Next.js 16 (App Router), React 19, **JavaScript** (not TS).
- **Styling:** Tailwind CSS v4 (`@import "tailwindcss"` in `app/globals.css`; theme tokens
  declared via `@theme inline`). No Tailwind config file.
- **Run:** `npm run dev` → **http://localhost:3003** (port pinned to 3003 in `package.json`).
- **Structure:** `app/layout.js` (fonts + metadata), `app/page.js` (the whole landing page),
  `app/globals.css` (tokens + marquee keyframes).

### Design system (locked)

| Token | Value | Usage |
|-------|-------|-------|
| `--background` / `bg-background` | `#F3F2E6` | page background (warm cream) |
| `--surface-alt` / `bg-surface-alt` | `#ECEADA` | alternating section panel (oatmeal) |
| `--foreground` / `text-foreground` | `#212427` | all text ("black") |
| `--font-serif` / `font-serif` | **Hedvig Letters Serif** | ALL headers + big numbers |
| `--font-sans` / default body | **Lato** | everything else |

- **Section rhythm:** sections alternate background — one bleeds through to `#F3F2E6`,
  the next is `#ECEADA`, repeat. Implemented via the `<Section alt>` helper in `page.js`.
- **Text hierarchy:** done with opacity on `text-foreground` (`/70`, `/60`, `/45`) — do
  NOT introduce new grey hues.
- **Primary CTA:** solid `bg-foreground` button, cream text. The single action the whole
  page funnels to is **"Call the agent"** (a `tel:` link).
- Fonts loaded in `app/layout.js` via `next/font/google` (Hedvig weight 400; Lato 300/400/700/900).

### Page structure (`app/page.js`, top → bottom)

Nav · Hook (headline + CTA + **integrations carousel**) · The Stakes (pain + 3 stat cards) ·
The Fix (3 capability cards) · Proof/Live-call (the big phone number — primary conversion) ·
How it works (3 steps) · Pricing (3 placeholder plan cards, Stripe TODO) · Final CTA · Footer.

The **integrations carousel** is a two-row marquee (`SystemsMarquee`) of POS/inventory
systems + store banners + catalog-data standards, scrolling opposite directions, paused on
hover. Label is deliberately honest: *"Built to integrate with the systems you already run"*
— we don't integrate yet; it's the post-hackathon moat. Chips are placeholder text → real
logos in the polish pass. Animation keyframes (`marquee` / `.animate-marquee[-reverse]`) are
in `globals.css`.

### Placeholders / TODO

- **Phone number** `(403) 000-0000` + `tel:+14030000000` → swap in Mayer's real Vapi number.
- **Pricing** — all `$X` / `N calls` until plans are finalized; Stripe checkout links to be
  wired onto the "Choose {plan}" buttons.
- **Carousel chips** — text now, real logos later.
- **Dashboard** — `/dashboard` (live projector view: call transcript + inventory hits +
  leads streaming in) is NOT built yet; planned as the highest-risk demo piece.

## Working conventions

- **Iterate, don't one-shot.** Build bare structure first, then style deliberately. Avoid
  "AI slop" — restrained, minimal, no random colors or decorative gradients.
- **Stay on-palette.** Only the 3 colors above + opacity steps. Headers serif, body Lato.
- Keep `app/page.js` readable: small local components (`Section`, `CallAgentButton`,
  `MarqueeRow`, `Eyebrow`) + data arrays mapped to markup.
- Frontend builds against the `BACKEND_SPEC.md` endpoint shapes; those shapes are the
  contract and must not drift.

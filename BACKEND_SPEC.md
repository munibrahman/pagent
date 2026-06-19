# Backend Spec — Auto Parts Voice Agent (Mayer)

**Deadline: 3:00 PM.** This is the contract. Build to these shapes exactly so the
frontend snaps together at integration (2:15).

---

## 0. The loop you're building

```
Vapi (answers call, speech↔text)
  → Nebius open model (interprets "front brake pads, 2015 Camry")
  → model calls a TOOL → your endpoint queries Insforge
  → structured answer returned → Vapi speaks it
  → every call + every miss is logged to Insforge (dashboard reads these)
```

Your three jobs, in priority order:
1. **Insforge: tables + seed data + the lookup** (frontend is blocked on this — do first)
2. **Vapi assistant wired to Nebius + the tool**
3. **VIN decode** (side-quest, do last)

---

## 1. FIRST THING (12:15) — unblock the frontend

Before anything works, commit **stub endpoints that return hardcoded JSON** in the
exact shapes below. The frontend builds against these immediately. Replace internals
with real Insforge queries after — the shapes never change.

---

## 2. Insforge tables

### `inventory`
| column        | type      | notes                                  |
|---------------|-----------|----------------------------------------|
| id            | uuid/serial pk |                                   |
| category      | text      | `brakes`, `filters`, `ignition`, `battery`, `suspension` |
| part_name     | text      | `Brake Pads`, `Oil Filter`             |
| position      | text null | `front` / `rear` / null                |
| brand         | text      | `Wagner`, `Bosch`, `ACDelco`           |
| part_number   | text      | the SKU, e.g. `ZD1210`                 |
| year_start    | int       | fitment range start, e.g. 2012         |
| year_end      | int       | fitment range end, e.g. 2017           |
| make          | text      | lowercase: `toyota`                    |
| model         | text      | lowercase: `camry`                     |
| fitment_text  | text      | human label: `2012–2017 Toyota Camry`  |
| qty           | int       | stock on hand                          |
| price         | numeric   | 42.99                                  |
| shelf         | text      | `B12`                                  |

### `calls` (dashboard reads this)
| column         | type | notes |
|----------------|------|-------|
| id             | uuid/serial pk | |
| caller_number  | text | |
| requested_part | text | `front brake pads` |
| vehicle        | text | `2015 Toyota Camry` |
| outcome        | text | `in_stock` / `miss` / `transferred` |
| transcript     | text | optional, full or summary |
| created_at     | timestamp default now() |

### `leads` (dashboard reads this — the money shot)
| column         | type | notes |
|----------------|------|-------|
| id             | uuid/serial pk | |
| caller_number  | text | |
| part_requested | text | |
| vehicle        | text | |
| note           | text | optional |
| created_at     | timestamp default now() |

---

## 3. The four endpoints (THE CONTRACT — do not change shapes)

### `GET /api/inventory`
Returns all SKUs. Used for a browse view + sanity checks.
```json
[
  { "id": 1, "category": "brakes", "part_name": "Brake Pads", "position": "front",
    "brand": "Wagner", "part_number": "ZD1210", "fitment_text": "2012–2017 Toyota Camry",
    "qty": 3, "price": 42.99, "shelf": "B12" }
]
```

### `POST /api/check_inventory`  ← the core tool
Request:
```json
{ "part": "brake pads", "position": "front",
  "year": 2015, "make": "toyota", "model": "camry", "vin": null }
```
Response:
```json
{
  "found": true,
  "matches": [
    { "brand": "Wagner", "part_number": "ZD1210", "part_name": "Brake Pads",
      "price": 42.99, "qty": 3, "shelf": "B12", "fitment_text": "2012–2017 Toyota Camry" }
  ],
  "message": "Yes — Wagner front brake pads, 3 in stock at $42.99, shelf B12."
}
```
On a miss:
```json
{ "found": false, "matches": [],
  "message": "No front brake pads in stock for a 2015 Camry. Want me to take your number and have them ordered?" }
```

**Matching logic (keep simple):**
- Normalize `part` → category (e.g. "brake pads"/"pads"/"brakes" → `brakes`).
- Filter inventory where `category` matches AND (`position` is null OR equals request position)
  AND `year` BETWEEN `year_start` and `year_end` AND `make` = request make AND `model` = request model.
- `found` = matches.length > 0. Always return a natural-language `message` — the LLM speaks it.
- If `vin` is provided, decode it first (section 6) to fill year/make/model, then match.

### `GET /api/calls`
Recent calls, newest first, limit ~20. Returns array of `calls` rows. Dashboard polls/subscribes.

### `GET /api/leads`
All leads, newest first. Returns array of `leads` rows. Dashboard polls/subscribes.

---

## 4. Vapi tool contract

Create **two** tools (functions) on the Vapi assistant. Vapi POSTs to your server URL
when the model calls them; you reply in Vapi's results format.

**Tool A — `check_inventory`** parameters:
```json
{ "part": "string", "position": "string|null",
  "year": "number|null", "make": "string|null",
  "model": "string|null", "vin": "string|null" }
```

**Tool B — `capture_lead`** parameters (called on a miss):
```json
{ "caller_number": "string", "part_requested": "string", "vehicle": "string" }
```
→ inserts a row into `leads`, returns `{ "ok": true }`.

**Vapi webhook shape** (verify against current Vapi docs — this format drifts):
Vapi sends:
```json
{ "message": { "toolCalls": [
  { "id": "call_abc", "function": { "name": "check_inventory",
    "arguments": { "part": "brake pads", "year": 2015, "make": "toyota", "model": "camry" } } }
] } }
```
You respond:
```json
{ "results": [ { "toolCallId": "call_abc", "result": "<the message string or JSON>" } ] }
```

Also: on **every** completed call, write a row to `calls` (use Vapi's end-of-call
report webhook, or write it from the tool handler). This is what makes the dashboard live.

---

## 5. Nebius brain (Vapi custom-LLM config)

In the Vapi assistant's model config, set an **OpenAI-compatible custom LLM**:
- **Base URL:** `https://api.tokenfactory.nebius.com/v1`
- **Model:** pick a fast, tool-calling-capable open model (e.g. a Llama-3.3-70B-Instruct
  or Qwen instruct on the **Fast** tier — must support function calling).
- **API key:** your Nebius Token Factory key.
- Keep the **system prompt tight**: "You are the parts counter at an auto parts store.
  When a caller asks for a part, ALWAYS call check_inventory before answering — never
  guess stock or price. If it's a miss, offer to capture their number via capture_lead.
  Be brief, friendly, like a busy counter person."

**Critical:** the model must NEVER invent stock/price. Truth lives in the DB; the model
only translates speech → tool call → speech.

---

## 6. VIN decode (side-quest, free, no key)

NHTSA vPIC API:
```
GET https://vpic.nhtsa.dot.gov/api/vehicles/DecodeVinValues/{VIN}?format=json
```
Pull `ModelYear`, `Make`, `Model` from `Results[0]`. Lowercase make/model, feed into
`check_inventory`. If a caller reads a VIN on stage and it resolves to a real part →
that's the wow moment.

---

## 7. Env / handoff
Backend needs: Insforge URL + key, Nebius key, Vapi key + phone number.
When live, give the frontend the **base URL** of your four endpoints — that's the only
thing it needs from you.

---

## TL;DR for Mayer
1. 12:15 — stub the 4 endpoints with fake JSON, push. **Frontend unblocked.**
2. Insforge tables + seed 40 SKUs + real `check_inventory`.
3. Vapi assistant → Nebius custom-LLM → `check_inventory` + `capture_lead` tools.
4. Log every call to `calls`, every miss to `leads`.
5. VIN decode if time. Give frontend your base URL at integration.

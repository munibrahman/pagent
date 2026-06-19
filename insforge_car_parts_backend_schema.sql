-- InsForge/Postgres schema for AI car-parts caller hackathon
-- Goal: Vapi voice agent -> InsForge Edge Functions -> Postgres inventory/quotes/holds -> Twilio SMS

CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- -----------------------------
-- Enums
-- -----------------------------
DO $$ BEGIN
  CREATE TYPE part_quality AS ENUM ('used', 'aftermarket', 'oem', 'remanufactured', 'performance', 'unknown');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE inventory_status AS ENUM ('available', 'reserved', 'sold', 'backordered', 'unavailable');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE hold_status AS ENUM ('active', 'expired', 'released', 'converted_to_sale');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE quote_status AS ENUM ('draft', 'sent', 'accepted', 'expired', 'cancelled', 'paid');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE call_status AS ENUM ('ringing', 'in_progress', 'completed', 'transferred', 'failed', 'abandoned');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE lead_status AS ENUM ('new', 'quoted', 'hold_created', 'transferred', 'won', 'lost', 'spam');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

DO $$ BEGIN
  CREATE TYPE integration_status AS ENUM ('fake', 'connected', 'syncing', 'error', 'disabled');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

-- -----------------------------
-- Utility trigger
-- -----------------------------
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------
-- Shop / tenant setup
-- -----------------------------
CREATE TABLE IF NOT EXISTS shops (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL,
  slug TEXT UNIQUE NOT NULL,
  business_phone TEXT,
  website_url TEXT,
  timezone TEXT NOT NULL DEFAULT 'America/Los_Angeles',
  currency TEXT NOT NULL DEFAULT 'USD',
  avg_order_value NUMERIC(10,2) NOT NULL DEFAULT 180.00,
  close_rate_percent NUMERIC(5,2) NOT NULL DEFAULT 35.00,
  gross_margin_percent NUMERIC(5,2) NOT NULL DEFAULT 40.00,
  loaded_hourly_wage NUMERIC(10,2) NOT NULL DEFAULT 28.00,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_shops_updated_at ON shops;
CREATE TRIGGER trg_shops_updated_at BEFORE UPDATE ON shops FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS shop_locations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  phone TEXT,
  city TEXT NOT NULL,
  state_region TEXT,
  country TEXT NOT NULL DEFAULT 'US',
  address_line1 TEXT,
  address_line2 TEXT,
  postal_code TEXT,
  latitude NUMERIC(9,6),
  longitude NUMERIC(9,6),
  is_primary BOOLEAN NOT NULL DEFAULT false,
  opening_hours JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_shop_locations_updated_at ON shop_locations;
CREATE TRIGGER trg_shop_locations_updated_at BEFORE UPDATE ON shop_locations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------
-- Integrations: POS, inventory, telephony, SMS, payment
-- -----------------------------
CREATE TABLE IF NOT EXISTS integrations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  provider TEXT NOT NULL, -- fake_pos, shopmonkey, lightspeed, twilio, stripe, vapi, etc.
  integration_type TEXT NOT NULL, -- pos, inventory, sms, payment, voice
  status integration_status NOT NULL DEFAULT 'fake',
  config JSONB NOT NULL DEFAULT '{}'::jsonb,
  last_sync_at TIMESTAMPTZ,
  last_error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, provider, integration_type)
);

DROP TRIGGER IF EXISTS trg_integrations_updated_at ON integrations;
CREATE TRIGGER trg_integrations_updated_at BEFORE UPDATE ON integrations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------
-- Suppliers
-- -----------------------------
CREATE TABLE IF NOT EXISTS suppliers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID REFERENCES shops(id) ON DELETE CASCADE, -- null means global demo supplier
  name TEXT NOT NULL,
  supplier_type TEXT NOT NULL DEFAULT 'warehouse', -- warehouse, salvage_yard, dealer, aftermarket, internal
  phone TEXT,
  email TEXT,
  city TEXT,
  state_region TEXT,
  country TEXT NOT NULL DEFAULT 'US',
  default_lead_time_hours INT NOT NULL DEFAULT 24,
  rating NUMERIC(3,2) DEFAULT 4.50,
  integration_id UUID REFERENCES integrations(id),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON suppliers;
CREATE TRIGGER trg_suppliers_updated_at BEFORE UPDATE ON suppliers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------
-- Vehicle reference data
-- Keep this lightweight for hackathon. Populate via NHTSA vPIC or CarAPI.
-- -----------------------------
CREATE TABLE IF NOT EXISTS vehicle_makes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  nhtsa_make_id INT,
  name TEXT NOT NULL UNIQUE,
  country TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS vehicle_models (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  make_id UUID NOT NULL REFERENCES vehicle_makes(id) ON DELETE CASCADE,
  nhtsa_model_id INT,
  name TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(make_id, name)
);

CREATE TABLE IF NOT EXISTS vehicle_configurations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  year INT NOT NULL CHECK (year BETWEEN 1981 AND 2100),
  make_id UUID NOT NULL REFERENCES vehicle_makes(id),
  model_id UUID NOT NULL REFERENCES vehicle_models(id),
  trim TEXT,
  body_class TEXT,
  doors INT,
  drive_type TEXT,
  engine_cylinders INT,
  engine_displacement_l NUMERIC(4,2),
  fuel_type TEXT,
  transmission TEXT,
  source TEXT NOT NULL DEFAULT 'manual_seed',
  raw_source JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_vehicle_configs_unique
ON vehicle_configurations (
  year,
  make_id,
  model_id,
  COALESCE(trim, ''),
  COALESCE(engine_displacement_l, 0),
  COALESCE(transmission, '')
);

CREATE TABLE IF NOT EXISTS vin_decode_cache (
  vin TEXT PRIMARY KEY CHECK (length(vin) = 17),
  year INT,
  make TEXT,
  model TEXT,
  trim TEXT,
  body_class TEXT,
  engine TEXT,
  plant_country TEXT,
  decoded_valid BOOLEAN NOT NULL DEFAULT true,
  source TEXT NOT NULL DEFAULT 'nhtsa_vpic',
  raw_response JSONB NOT NULL DEFAULT '{}'::jsonb,
  decoded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------
-- Customers / vehicles
-- -----------------------------
CREATE TABLE IF NOT EXISTS customers (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  name TEXT,
  phone TEXT NOT NULL,
  email TEXT,
  city TEXT,
  state_region TEXT,
  preferred_contact_method TEXT NOT NULL DEFAULT 'sms',
  marketing_opt_in BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, phone)
);

DROP TRIGGER IF EXISTS trg_customers_updated_at ON customers;
CREATE TRIGGER trg_customers_updated_at BEFORE UPDATE ON customers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS customer_vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  customer_id UUID NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  vin TEXT CHECK (vin IS NULL OR length(vin) = 17),
  year INT CHECK (year IS NULL OR year BETWEEN 1981 AND 2100),
  make TEXT,
  model TEXT,
  trim TEXT,
  engine TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_customer_vehicles_updated_at ON customer_vehicles;
CREATE TRIGGER trg_customer_vehicles_updated_at BEFORE UPDATE ON customer_vehicles FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- -----------------------------
-- Parts catalog: ACES-ish fitment + PIES-ish product info
-- -----------------------------
CREATE TABLE IF NOT EXISTS part_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_id UUID REFERENCES part_categories(id),
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL UNIQUE,
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS part_types (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  category_id UUID REFERENCES part_categories(id),
  name TEXT NOT NULL,
  normalized_name TEXT NOT NULL UNIQUE,
  pcdb_code TEXT, -- optional future mapping to Auto Care PCdb
  description TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS part_aliases (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_type_id UUID NOT NULL REFERENCES part_types(id) ON DELETE CASCADE,
  alias TEXT NOT NULL,
  normalized_alias TEXT NOT NULL,
  source TEXT NOT NULL DEFAULT 'manual_seed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(part_type_id, normalized_alias)
);

CREATE TABLE IF NOT EXISTS brands (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  name TEXT NOT NULL UNIQUE,
  brand_type TEXT NOT NULL DEFAULT 'aftermarket', -- oem, aftermarket, house, salvage
  website_url TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS part_products (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_type_id UUID NOT NULL REFERENCES part_types(id),
  brand_id UUID REFERENCES brands(id),
  manufacturer_part_number TEXT NOT NULL,
  sku TEXT UNIQUE,
  title TEXT NOT NULL,
  description TEXT,
  quality part_quality NOT NULL DEFAULT 'aftermarket',
  condition_grade TEXT, -- A/B/C for used parts, New for new parts
  warranty_days INT NOT NULL DEFAULT 30,
  core_charge NUMERIC(10,2) NOT NULL DEFAULT 0,
  msrp NUMERIC(10,2),
  interchange_part_numbers TEXT[] NOT NULL DEFAULT '{}',
  image_url TEXT,
  source TEXT NOT NULL DEFAULT 'manual_seed',
  raw_source JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_part_products_mpn_brand_unique
ON part_products (
  manufacturer_part_number,
  COALESCE(brand_id, '00000000-0000-0000-0000-000000000000'::uuid)
);

DROP TRIGGER IF EXISTS trg_part_products_updated_at ON part_products;
CREATE TRIGGER trg_part_products_updated_at BEFORE UPDATE ON part_products FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS part_fitments (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  part_product_id UUID NOT NULL REFERENCES part_products(id) ON DELETE CASCADE,
  year_start INT NOT NULL,
  year_end INT NOT NULL,
  make TEXT NOT NULL,
  model TEXT NOT NULL,
  trim TEXT,
  engine TEXT,
  qualifiers TEXT, -- e.g. '2.0L only', 'without sport package'
  confidence NUMERIC(4,3) NOT NULL DEFAULT 1.000,
  source TEXT NOT NULL DEFAULT 'manual_seed',
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (year_start <= year_end)
);

-- -----------------------------
-- Inventory / pricing / holds
-- -----------------------------
CREATE TABLE IF NOT EXISTS inventory_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  location_id UUID REFERENCES shop_locations(id),
  supplier_id UUID REFERENCES suppliers(id),
  part_product_id UUID NOT NULL REFERENCES part_products(id),
  external_inventory_id TEXT,
  quantity_available INT NOT NULL DEFAULT 1 CHECK (quantity_available >= 0),
  quantity_reserved INT NOT NULL DEFAULT 0 CHECK (quantity_reserved >= 0),
  cost NUMERIC(10,2),
  price NUMERIC(10,2) NOT NULL,
  currency TEXT NOT NULL DEFAULT 'USD',
  status inventory_status NOT NULL DEFAULT 'available',
  lead_time_hours INT NOT NULL DEFAULT 0,
  shelf_location TEXT,
  notes TEXT,
  last_synced_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  CHECK (quantity_reserved <= quantity_available)
);

DROP TRIGGER IF EXISTS trg_inventory_items_updated_at ON inventory_items;
CREATE TRIGGER trg_inventory_items_updated_at BEFORE UPDATE ON inventory_items FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS calls (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  vapi_call_id TEXT UNIQUE,
  from_phone TEXT,
  to_phone TEXT,
  customer_id UUID REFERENCES customers(id),
  status call_status NOT NULL DEFAULT 'ringing',
  lead_status lead_status NOT NULL DEFAULT 'new',
  started_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  ended_at TIMESTAMPTZ,
  duration_seconds INT,
  language TEXT DEFAULT 'en',
  intent TEXT, -- quote_part, check_status, hours, transfer, spam
  requested_part_text TEXT,
  vehicle_text TEXT,
  transcript TEXT,
  summary TEXT,
  outcome TEXT,
  estimated_revenue NUMERIC(10,2) NOT NULL DEFAULT 0,
  recording_url TEXT,
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_calls_updated_at ON calls;
CREATE TRIGGER trg_calls_updated_at BEFORE UPDATE ON calls FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS call_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id UUID NOT NULL REFERENCES calls(id) ON DELETE CASCADE,
  role TEXT NOT NULL CHECK (role IN ('system','assistant','user','tool')),
  content TEXT NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS call_tool_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  call_id UUID REFERENCES calls(id) ON DELETE CASCADE,
  tool_name TEXT NOT NULL,
  request_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  response_json JSONB NOT NULL DEFAULT '{}'::jsonb,
  success BOOLEAN NOT NULL DEFAULT true,
  latency_ms INT,
  error_message TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS quote_requests (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  call_id UUID REFERENCES calls(id),
  customer_id UUID REFERENCES customers(id),
  customer_vehicle_id UUID REFERENCES customer_vehicles(id),
  part_type_id UUID REFERENCES part_types(id),
  requested_part_text TEXT NOT NULL,
  city TEXT,
  urgency TEXT DEFAULT 'normal',
  budget_max NUMERIC(10,2),
  preferred_quality part_quality DEFAULT 'unknown',
  status TEXT NOT NULL DEFAULT 'open',
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_quote_requests_updated_at ON quote_requests;
CREATE TRIGGER trg_quote_requests_updated_at BEFORE UPDATE ON quote_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS quotes (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  quote_request_id UUID REFERENCES quote_requests(id),
  call_id UUID REFERENCES calls(id),
  customer_id UUID REFERENCES customers(id),
  status quote_status NOT NULL DEFAULT 'draft',
  subtotal NUMERIC(10,2) NOT NULL DEFAULT 0,
  tax NUMERIC(10,2) NOT NULL DEFAULT 0,
  fees NUMERIC(10,2) NOT NULL DEFAULT 0,
  total NUMERIC(10,2) NOT NULL DEFAULT 0,
  currency TEXT NOT NULL DEFAULT 'USD',
  payment_url TEXT,
  public_quote_token TEXT UNIQUE DEFAULT encode(gen_random_bytes(16), 'hex'),
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '24 hours'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_quotes_updated_at ON quotes;
CREATE TRIGGER trg_quotes_updated_at BEFORE UPDATE ON quotes FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS quote_items (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  quote_id UUID NOT NULL REFERENCES quotes(id) ON DELETE CASCADE,
  inventory_item_id UUID REFERENCES inventory_items(id),
  part_product_id UUID NOT NULL REFERENCES part_products(id),
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
  unit_price NUMERIC(10,2) NOT NULL,
  warranty_days INT NOT NULL DEFAULT 30,
  lead_time_hours INT NOT NULL DEFAULT 0,
  line_total NUMERIC(10,2) GENERATED ALWAYS AS (quantity * unit_price) STORED,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS inventory_holds (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  inventory_item_id UUID NOT NULL REFERENCES inventory_items(id),
  customer_id UUID REFERENCES customers(id),
  call_id UUID REFERENCES calls(id),
  quote_id UUID REFERENCES quotes(id),
  quantity INT NOT NULL DEFAULT 1 CHECK (quantity > 0),
  status hold_status NOT NULL DEFAULT 'active',
  expires_at TIMESTAMPTZ NOT NULL DEFAULT (now() + interval '30 minutes'),
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  released_at TIMESTAMPTZ
);

-- -----------------------------
-- Notifications / SMS
-- -----------------------------
CREATE TABLE IF NOT EXISTS sms_messages (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES customers(id),
  call_id UUID REFERENCES calls(id),
  quote_id UUID REFERENCES quotes(id),
  provider TEXT NOT NULL DEFAULT 'twilio',
  provider_message_id TEXT,
  to_phone TEXT NOT NULL,
  from_phone TEXT,
  body TEXT NOT NULL,
  status TEXT NOT NULL DEFAULT 'queued',
  error_message TEXT,
  sent_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- -----------------------------
-- Analytics / ROI
-- -----------------------------
CREATE TABLE IF NOT EXISTS daily_metrics (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  metric_date DATE NOT NULL,
  total_calls INT NOT NULL DEFAULT 0,
  ai_answered_calls INT NOT NULL DEFAULT 0,
  missed_calls_pre_ai_estimate INT NOT NULL DEFAULT 0,
  quotes_created INT NOT NULL DEFAULT 0,
  holds_created INT NOT NULL DEFAULT 0,
  transfers_to_human INT NOT NULL DEFAULT 0,
  avg_call_duration_seconds INT NOT NULL DEFAULT 0,
  estimated_revenue_recovered NUMERIC(10,2) NOT NULL DEFAULT 0,
  labour_minutes_saved NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, metric_date)
);

-- -----------------------------
-- Search views
-- -----------------------------
CREATE OR REPLACE VIEW v_inventory_search AS
SELECT
  ii.id AS inventory_item_id,
  ii.shop_id,
  sl.city AS location_city,
  sl.state_region AS location_state,
  s.name AS supplier_name,
  s.default_lead_time_hours AS supplier_default_lead_time_hours,
  pc.name AS category_name,
  pt.name AS part_type_name,
  pt.normalized_name AS part_type_normalized,
  b.name AS brand_name,
  pp.manufacturer_part_number,
  pp.sku,
  pp.title,
  pp.quality,
  pp.condition_grade,
  pp.warranty_days,
  pp.interchange_part_numbers,
  ii.price,
  ii.currency,
  ii.quantity_available,
  ii.quantity_reserved,
  ii.status,
  ii.lead_time_hours
FROM inventory_items ii
JOIN part_products pp ON pp.id = ii.part_product_id
JOIN part_types pt ON pt.id = pp.part_type_id
LEFT JOIN part_categories pc ON pc.id = pt.category_id
LEFT JOIN brands b ON b.id = pp.brand_id
LEFT JOIN suppliers s ON s.id = ii.supplier_id
LEFT JOIN shop_locations sl ON sl.id = ii.location_id;

CREATE OR REPLACE VIEW v_quote_revenue AS
SELECT
  q.shop_id,
  q.id AS quote_id,
  q.status,
  q.total,
  c.id AS call_id,
  c.duration_seconds,
  c.estimated_revenue,
  q.created_at
FROM quotes q
LEFT JOIN calls c ON c.id = q.call_id;

-- -----------------------------
-- Indexes
-- -----------------------------
CREATE INDEX IF NOT EXISTS idx_shop_locations_shop_city ON shop_locations(shop_id, city);
CREATE INDEX IF NOT EXISTS idx_suppliers_shop_city ON suppliers(shop_id, city);
CREATE INDEX IF NOT EXISTS idx_vehicle_models_make_name ON vehicle_models(make_id, lower(name));
CREATE INDEX IF NOT EXISTS idx_vehicle_configs_year_make_model ON vehicle_configurations(year, make_id, model_id);
CREATE INDEX IF NOT EXISTS idx_customers_shop_phone ON customers(shop_id, phone);
CREATE INDEX IF NOT EXISTS idx_customer_vehicles_vin ON customer_vehicles(vin);
CREATE INDEX IF NOT EXISTS idx_part_aliases_normalized ON part_aliases(normalized_alias);
CREATE INDEX IF NOT EXISTS idx_part_types_normalized ON part_types(normalized_name);
CREATE INDEX IF NOT EXISTS idx_part_products_mpn ON part_products(manufacturer_part_number);
CREATE INDEX IF NOT EXISTS idx_part_fitments_vehicle ON part_fitments(lower(make), lower(model), year_start, year_end);
CREATE INDEX IF NOT EXISTS idx_inventory_shop_status ON inventory_items(shop_id, status);
CREATE INDEX IF NOT EXISTS idx_inventory_part ON inventory_items(part_product_id);
CREATE INDEX IF NOT EXISTS idx_calls_shop_started ON calls(shop_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_quotes_shop_status ON quotes(shop_id, status);
CREATE INDEX IF NOT EXISTS idx_holds_active_expiry ON inventory_holds(status, expires_at);
CREATE INDEX IF NOT EXISTS idx_sms_shop_created ON sms_messages(shop_id, created_at DESC);

-- -----------------------------
-- Function: simple inventory search for Vapi tool
-- -----------------------------
CREATE OR REPLACE FUNCTION search_inventory_for_call(
  p_shop_id UUID,
  p_part_text TEXT,
  p_year INT DEFAULT NULL,
  p_make TEXT DEFAULT NULL,
  p_model TEXT DEFAULT NULL,
  p_city TEXT DEFAULT NULL
)
RETURNS TABLE (
  inventory_item_id UUID,
  title TEXT,
  part_type_name TEXT,
  brand_name TEXT,
  manufacturer_part_number TEXT,
  quality part_quality,
  price NUMERIC,
  warranty_days INT,
  lead_time_hours INT,
  quantity_available INT,
  supplier_name TEXT,
  location_city TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    vis.inventory_item_id,
    vis.title,
    vis.part_type_name,
    vis.brand_name,
    vis.manufacturer_part_number,
    vis.quality,
    vis.price,
    vis.warranty_days,
    vis.lead_time_hours,
    (vis.quantity_available - vis.quantity_reserved) AS quantity_available,
    vis.supplier_name,
    vis.location_city
  FROM v_inventory_search vis
  LEFT JOIN part_fitments pf ON pf.part_product_id = (
    SELECT ii.part_product_id FROM inventory_items ii WHERE ii.id = vis.inventory_item_id
  )
  WHERE vis.shop_id = p_shop_id
    AND vis.status = 'available'
    AND (vis.quantity_available - vis.quantity_reserved) > 0
    AND (
      vis.part_type_normalized ILIKE '%' || lower(p_part_text) || '%'
      OR vis.part_type_name ILIKE '%' || p_part_text || '%'
      OR vis.title ILIKE '%' || p_part_text || '%'
      OR EXISTS (
        SELECT 1 FROM part_aliases pa
        JOIN part_types pt ON pt.id = pa.part_type_id
        JOIN part_products pp ON pp.part_type_id = pt.id
        JOIN inventory_items ii ON ii.part_product_id = pp.id
        WHERE ii.id = vis.inventory_item_id
          AND pa.normalized_alias ILIKE '%' || lower(p_part_text) || '%'
      )
    )
    AND (p_city IS NULL OR lower(vis.location_city) = lower(p_city) OR vis.lead_time_hours <= 48)
    AND (p_year IS NULL OR pf.id IS NULL OR p_year BETWEEN pf.year_start AND pf.year_end)
    AND (p_make IS NULL OR pf.id IS NULL OR lower(pf.make) = lower(p_make))
    AND (p_model IS NULL OR pf.id IS NULL OR lower(pf.model) = lower(p_model))
  ORDER BY vis.lead_time_hours ASC, vis.price ASC
  LIMIT 5;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------
-- Function: hold part atomically for Vapi tool
-- -----------------------------
CREATE OR REPLACE FUNCTION create_inventory_hold(
  p_shop_id UUID,
  p_inventory_item_id UUID,
  p_customer_id UUID DEFAULT NULL,
  p_call_id UUID DEFAULT NULL,
  p_quote_id UUID DEFAULT NULL,
  p_quantity INT DEFAULT 1,
  p_hold_minutes INT DEFAULT 30
)
RETURNS UUID AS $$
DECLARE
  v_hold_id UUID;
  v_available INT;
BEGIN
  SELECT quantity_available - quantity_reserved
  INTO v_available
  FROM inventory_items
  WHERE id = p_inventory_item_id
    AND shop_id = p_shop_id
    AND status = 'available'
  FOR UPDATE;

  IF v_available IS NULL OR v_available < p_quantity THEN
    RAISE EXCEPTION 'Inventory item not available or insufficient quantity';
  END IF;

  UPDATE inventory_items
  SET quantity_reserved = quantity_reserved + p_quantity,
      updated_at = now()
  WHERE id = p_inventory_item_id;

  INSERT INTO inventory_holds (
    shop_id, inventory_item_id, customer_id, call_id, quote_id, quantity, expires_at
  ) VALUES (
    p_shop_id, p_inventory_item_id, p_customer_id, p_call_id, p_quote_id, p_quantity, now() + make_interval(mins => p_hold_minutes)
  ) RETURNING id INTO v_hold_id;

  RETURN v_hold_id;
END;
$$ LANGUAGE plpgsql;

-- -----------------------------
-- Seed data for hackathon demo
-- -----------------------------
INSERT INTO shops (name, slug, business_phone, website_url, timezone, currency)
VALUES ('PartPilot Demo Auto Parts', 'partpilot-demo', '+14155550123', 'https://example.com', 'America/Los_Angeles', 'USD')
ON CONFLICT (slug) DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug = 'partpilot-demo')
INSERT INTO shop_locations (shop_id, name, phone, city, state_region, country, address_line1, is_primary, opening_hours)
SELECT shop.id, x.name, x.phone, x.city, x.state_region, x.country, x.address_line1, x.is_primary, x.opening_hours::jsonb
FROM shop, (VALUES
  ('San Francisco Counter', '+14155550123', 'San Francisco', 'CA', 'US', '100 Market St', true,  '{"mon-fri":"08:00-18:00","sat":"09:00-15:00"}'),
  ('Calgary Counter',       '+14035550123', 'Calgary',       'AB', 'CA', '200 8 Ave SW', false, '{"mon-fri":"08:00-18:00","sat":"09:00-15:00"}'),
  ('Toronto Counter',       '+14165550123', 'Toronto',       'ON', 'CA', '300 King St W', false, '{"mon-fri":"08:00-18:00","sat":"09:00-15:00"}')
) AS x(name, phone, city, state_region, country, address_line1, is_primary, opening_hours)
ON CONFLICT DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug = 'partpilot-demo')
INSERT INTO suppliers (shop_id, name, supplier_type, phone, city, state_region, country, default_lead_time_hours, rating)
SELECT shop.id, x.name, x.supplier_type, x.phone, x.city, x.state_region, x.country, x.default_lead_time_hours, x.rating
FROM shop, (VALUES
  ('Rapid Wreckers',        'salvage_yard', '+14155551001', 'San Francisco', 'CA', 'US', 4,  4.40),
  ('OEM Direct Dealer',     'dealer',       '+14155551002', 'San Jose',      'CA', 'US', 24, 4.70),
  ('Budget Auto Parts',     'aftermarket',  '+14035551001', 'Calgary',       'AB', 'CA', 12, 4.20),
  ('Premium Reman Supply',  'warehouse',    '+14165551001', 'Toronto',       'ON', 'CA', 36, 4.80)
) AS x(name, supplier_type, phone, city, state_region, country, default_lead_time_hours, rating)
ON CONFLICT DO NOTHING;

INSERT INTO vehicle_makes (name, country) VALUES
  ('Honda', 'Japan'), ('Toyota', 'Japan'), ('Ford', 'United States'), ('BMW', 'Germany'), ('Hyundai', 'South Korea')
ON CONFLICT (name) DO NOTHING;

WITH honda AS (SELECT id FROM vehicle_makes WHERE name='Honda'),
     toyota AS (SELECT id FROM vehicle_makes WHERE name='Toyota'),
     ford AS (SELECT id FROM vehicle_makes WHERE name='Ford'),
     bmw AS (SELECT id FROM vehicle_makes WHERE name='BMW'),
     hyundai AS (SELECT id FROM vehicle_makes WHERE name='Hyundai')
INSERT INTO vehicle_models (make_id, name)
SELECT honda.id, 'Civic' FROM honda UNION ALL
SELECT honda.id, 'Accord' FROM honda UNION ALL
SELECT toyota.id, 'Camry' FROM toyota UNION ALL
SELECT toyota.id, 'Corolla' FROM toyota UNION ALL
SELECT ford.id, 'F-150' FROM ford UNION ALL
SELECT bmw.id, 'X5' FROM bmw UNION ALL
SELECT hyundai.id, 'Elantra' FROM hyundai
ON CONFLICT (make_id, name) DO NOTHING;

WITH m AS (SELECT vmk.name AS make, vmo.name AS model, vmk.id AS make_id, vmo.id AS model_id FROM vehicle_makes vmk JOIN vehicle_models vmo ON vmo.make_id = vmk.id)
INSERT INTO vehicle_configurations (year, make_id, model_id, trim, body_class, doors, drive_type, engine_cylinders, engine_displacement_l, fuel_type, transmission)
SELECT x.year, m.make_id, m.model_id, x.trim, x.body_class, x.doors, x.drive_type, x.engine_cylinders, x.engine_displacement_l, x.fuel_type, x.transmission
FROM m JOIN (VALUES
  (2016, 'Honda',  'Civic',   'LX',   'Sedan', 4, 'FWD', 4, 2.00, 'Gasoline', 'CVT'),
  (2017, 'Toyota', 'Camry',   'LE',   'Sedan', 4, 'FWD', 4, 2.50, 'Gasoline', 'Automatic'),
  (2018, 'Ford',   'F-150',   'XLT',  'Pickup',4, '4WD', 6, 3.50, 'Gasoline', 'Automatic'),
  (2014, 'BMW',    'X5',      '35i',  'SUV',   4, 'AWD', 6, 3.00, 'Gasoline', 'Automatic'),
  (2020, 'Hyundai','Elantra', 'SE',   'Sedan', 4, 'FWD', 4, 2.00, 'Gasoline', 'Automatic')
) AS x(year, make, model, trim, body_class, doors, drive_type, engine_cylinders, engine_displacement_l, fuel_type, transmission)
ON m.make = x.make AND m.model = x.model
ON CONFLICT DO NOTHING;

INSERT INTO part_categories (name, normalized_name, description) VALUES
  ('Starting & Charging', 'starting_charging', 'Starters, alternators, batteries'),
  ('Cooling', 'cooling', 'Radiators, fans, water pumps'),
  ('Brakes', 'brakes', 'Pads, rotors, calipers'),
  ('Lighting', 'lighting', 'Headlights, tail lights, bulbs'),
  ('Body', 'body', 'Bumpers, mirrors, exterior parts')
ON CONFLICT (normalized_name) DO NOTHING;

WITH cat AS (SELECT id, normalized_name FROM part_categories)
INSERT INTO part_types (category_id, name, normalized_name, description)
SELECT cat.id, x.name, x.normalized_name, x.description
FROM cat JOIN (VALUES
  ('starting_charging', 'Starter Motor', 'starter', 'Electric starter motor'),
  ('starting_charging', 'Alternator', 'alternator', 'Charging alternator'),
  ('cooling', 'Radiator', 'radiator', 'Engine cooling radiator'),
  ('brakes', 'Front Brake Pads', 'front_brake_pads', 'Front brake pad set'),
  ('lighting', 'Headlight Assembly', 'headlight_assembly', 'Complete headlight assembly'),
  ('body', 'Side Mirror', 'side_mirror', 'Exterior side mirror')
) AS x(category_norm, name, normalized_name, description)
ON cat.normalized_name = x.category_norm
ON CONFLICT (normalized_name) DO NOTHING;

WITH pt AS (SELECT id, normalized_name FROM part_types)
INSERT INTO part_aliases (part_type_id, alias, normalized_alias)
SELECT pt.id, x.alias, lower(x.alias)
FROM pt JOIN (VALUES
  ('starter', 'starter'), ('starter', 'starter motor'), ('starter', 'start motor'),
  ('alternator', 'alternator'), ('alternator', 'generator'),
  ('radiator', 'radiator'), ('front_brake_pads', 'brake pads'), ('front_brake_pads', 'front pads'),
  ('headlight_assembly', 'headlight'), ('headlight_assembly', 'head lamp'),
  ('side_mirror', 'side mirror'), ('side_mirror', 'mirror')
) AS x(part_norm, alias)
ON pt.normalized_name = x.part_norm
ON CONFLICT (part_type_id, normalized_alias) DO NOTHING;

INSERT INTO brands (name, brand_type) VALUES
  ('DemoOEM', 'oem'), ('BudgetLine', 'aftermarket'), ('RemanPro', 'remanufactured'), ('SalvageGrade', 'salvage')
ON CONFLICT (name) DO NOTHING;

WITH pt AS (SELECT id, normalized_name FROM part_types), b AS (SELECT id, name FROM brands)
INSERT INTO part_products (part_type_id, brand_id, manufacturer_part_number, sku, title, quality, condition_grade, warranty_days, core_charge, msrp, interchange_part_numbers)
SELECT pt.id, b.id, x.mpn, x.sku, x.title, x.quality::part_quality, x.condition_grade, x.warranty_days, x.core_charge, x.msrp, x.interchange_part_numbers::text[]
FROM pt
JOIN (VALUES
  ('starter', 'DemoOEM',      'DEMO-HON-CIV-16-STR-OE',   'SKU-STR-HON-CIV-16-OE',   'OEM Starter - 2016 Honda Civic 2.0L',       'oem',            'New', 365, 0, 220, ARRAY['HON-STR-16CIV-DEMO']),
  ('starter', 'SalvageGrade', 'USED-HON-CIV-16-STR-A',    'SKU-STR-HON-CIV-16-USED', 'Used OEM Starter - 2016 Honda Civic',       'used',           'A',   30, 0, 95,  ARRAY['DEMO-HON-CIV-16-STR-OE']),
  ('starter', 'RemanPro',     'RMP-HON-CIV-16-STR',       'SKU-STR-HON-CIV-16-RMP',  'Reman Starter - 2016 Honda Civic',          'remanufactured', 'New', 730, 25, 210, ARRAY['DEMO-HON-CIV-16-STR-OE']),
  ('alternator','BudgetLine', 'BL-TYT-CAM-17-ALT',        'SKU-ALT-TYT-CAM-17-BL',   'Aftermarket Alternator - 2017 Toyota Camry','aftermarket',    'New', 365, 0, 165, ARRAY['TYT-ALT-CAM17-DEMO']),
  ('front_brake_pads','BudgetLine','BL-FRD-F150-18-FPAD', 'SKU-BRK-FRD-F150-18-BL',  'Front Brake Pads - 2018 Ford F-150',        'aftermarket',    'New', 365, 0, 75,  ARRAY['FRD-FPAD-F15018-DEMO']),
  ('radiator','SalvageGrade', 'USED-BMW-X5-14-RAD-B',     'SKU-RAD-BMW-X5-14-USED',  'Used Radiator - 2014 BMW X5 35i',           'used',           'B',   30, 0, 140, ARRAY['BMW-RAD-X514-DEMO']),
  ('headlight_assembly','BudgetLine','BL-HYU-ELA-20-HL-L','SKU-HDL-HYU-ELA-20-L',    'Left Headlight - 2020 Hyundai Elantra',     'aftermarket',    'New', 180, 0, 190, ARRAY['HYU-HL-ELA20-L-DEMO'])
) AS x(part_norm, brand_name, mpn, sku, title, quality, condition_grade, warranty_days, core_charge, msrp, interchange_part_numbers)
ON pt.normalized_name = x.part_norm
JOIN b ON b.name = x.brand_name
ON CONFLICT DO NOTHING;

INSERT INTO part_fitments (part_product_id, year_start, year_end, make, model, trim, engine, qualifiers)
SELECT pp.id, x.year_start, x.year_end, x.make, x.model, x.trim, x.engine, x.qualifiers
FROM part_products pp JOIN (VALUES
  ('DEMO-HON-CIV-16-STR-OE', 2016, 2018, 'Honda',  'Civic',   NULL, '2.0L', 'Sedan 2.0L only'),
  ('USED-HON-CIV-16-STR-A',  2016, 2018, 'Honda',  'Civic',   NULL, '2.0L', 'Sedan 2.0L only'),
  ('RMP-HON-CIV-16-STR',     2016, 2018, 'Honda',  'Civic',   NULL, '2.0L', 'Sedan 2.0L only'),
  ('BL-TYT-CAM-17-ALT',      2015, 2017, 'Toyota', 'Camry',   NULL, '2.5L', '2.5L engine'),
  ('BL-FRD-F150-18-FPAD',    2015, 2020, 'Ford',   'F-150',   NULL, NULL,   'Front axle'),
  ('USED-BMW-X5-14-RAD-B',   2014, 2018, 'BMW',    'X5',      '35i','3.0L', '35i only'),
  ('BL-HYU-ELA-20-HL-L',     2019, 2020, 'Hyundai','Elantra', NULL, NULL,   'Left side')
) AS x(mpn, year_start, year_end, make, model, trim, engine, qualifiers)
ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     loc AS (SELECT id, city FROM shop_locations WHERE shop_id = (SELECT id FROM shop)),
     sup AS (SELECT id, name FROM suppliers WHERE shop_id = (SELECT id FROM shop)),
     pp AS (SELECT id, manufacturer_part_number FROM part_products)
INSERT INTO inventory_items (shop_id, location_id, supplier_id, part_product_id, quantity_available, price, cost, status, lead_time_hours, shelf_location)
SELECT shop.id, loc.id, sup.id, pp.id, x.qty, x.price, x.cost, 'available', x.lead, x.shelf
FROM shop
CROSS JOIN (VALUES
  ('San Francisco', 'Rapid Wreckers',       'USED-HON-CIV-16-STR-A',    2,  95,  45,  2, 'A1-03'),
  ('San Francisco', 'OEM Direct Dealer',    'DEMO-HON-CIV-16-STR-OE',   1, 220, 160, 24, 'DROP-SHIP'),
  ('Toronto',       'Premium Reman Supply', 'RMP-HON-CIV-16-STR',       4, 210, 130, 36, 'R2-11'),
  ('Calgary',       'Budget Auto Parts',    'BL-TYT-CAM-17-ALT',        3, 165,  90, 12, 'C4-02'),
  ('San Francisco', 'Budget Auto Parts',    'BL-FRD-F150-18-FPAD',      6,  75,  35, 24, 'B2-08'),
  ('Calgary',       'Rapid Wreckers',       'USED-BMW-X5-14-RAD-B',     1, 140,  65, 24, 'YARD-7'),
  ('Toronto',       'Budget Auto Parts',    'BL-HYU-ELA-20-HL-L',       2, 190, 100, 12, 'L1-19')
) AS x(city, supplier, mpn, qty, price, cost, lead, shelf)
JOIN loc ON loc.city = x.city
JOIN sup ON sup.name = x.supplier
JOIN pp ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

-- Optional sample customer/call
WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo')
INSERT INTO customers (shop_id, name, phone, city)
SELECT shop.id, 'Alex Demo', '+14155559999', 'San Francisco'
FROM shop
ON CONFLICT (shop_id, phone) DO NOTHING;

-- -----------------------------
-- Expanded client-demo seed data
-- -----------------------------
WITH shop AS (SELECT id FROM shops WHERE slug = 'partpilot-demo')
INSERT INTO integrations (shop_id, provider, integration_type, status, config, last_sync_at)
SELECT shop.id, x.provider, x.integration_type, x.status::integration_status, x.config::jsonb, now() - x.age::interval
FROM shop, (VALUES
  ('vapi', 'voice', 'connected', '{"assistant":"PartsPanda Demo Voice Agent","phone":"+14155550123"}', '4 minutes'),
  ('twilio', 'sms', 'connected', '{"messaging_service":"demo-service"}', '8 minutes'),
  ('stripe', 'payment', 'fake', '{"mode":"test","checkout_enabled":true}', '1 hour'),
  ('fake_pos', 'inventory', 'syncing', '{"sync_interval_minutes":15,"source":"demo_catalog"}', '15 minutes')
) AS x(provider, integration_type, status, config, age)
ON CONFLICT (shop_id, provider, integration_type) DO UPDATE
SET status = EXCLUDED.status,
    config = EXCLUDED.config,
    last_sync_at = EXCLUDED.last_sync_at,
    updated_at = now();

INSERT INTO vehicle_makes (name, country) VALUES
  ('Chevrolet', 'United States'),
  ('Nissan', 'Japan'),
  ('Jeep', 'United States'),
  ('Subaru', 'Japan'),
  ('Mazda', 'Japan'),
  ('Mercedes-Benz', 'Germany'),
  ('Audi', 'Germany'),
  ('Volkswagen', 'Germany'),
  ('Kia', 'South Korea'),
  ('Lexus', 'Japan'),
  ('Ram', 'United States')
ON CONFLICT (name) DO NOTHING;

WITH makes AS (SELECT id, name FROM vehicle_makes)
INSERT INTO vehicle_models (make_id, name)
SELECT makes.id, x.model
FROM makes JOIN (VALUES
  ('Chevrolet', 'Silverado 1500'),
  ('Chevrolet', 'Malibu'),
  ('Nissan', 'Altima'),
  ('Nissan', 'Rogue'),
  ('Jeep', 'Wrangler'),
  ('Subaru', 'Outback'),
  ('Mazda', 'CX-5'),
  ('Mercedes-Benz', 'C300'),
  ('Audi', 'A4'),
  ('Volkswagen', 'Jetta'),
  ('Kia', 'Forte'),
  ('Lexus', 'RX350'),
  ('Ram', '1500')
) AS x(make, model)
ON makes.name = x.make
ON CONFLICT (make_id, name) DO NOTHING;

WITH m AS (
  SELECT vmk.name AS make, vmo.name AS model, vmk.id AS make_id, vmo.id AS model_id
  FROM vehicle_makes vmk
  JOIN vehicle_models vmo ON vmo.make_id = vmk.id
)
INSERT INTO vehicle_configurations (year, make_id, model_id, trim, body_class, doors, drive_type, engine_cylinders, engine_displacement_l, fuel_type, transmission)
SELECT x.year, m.make_id, m.model_id, x.trim, x.body_class, x.doors, x.drive_type, x.engine_cylinders, x.engine_displacement_l, x.fuel_type, x.transmission
FROM m JOIN (VALUES
  (2015, 'Toyota', 'Camry', 'SE', 'Sedan', 4, 'FWD', 4, 2.50, 'Gasoline', 'Automatic'),
  (2012, 'Toyota', 'Corolla', 'LE', 'Sedan', 4, 'FWD', 4, 1.80, 'Gasoline', 'Automatic'),
  (2019, 'Honda', 'Accord', 'Sport', 'Sedan', 4, 'FWD', 4, 1.50, 'Gasoline', 'CVT'),
  (2021, 'Ford', 'F-150', 'XL', 'Pickup', 4, 'RWD', 6, 2.70, 'Gasoline', 'Automatic'),
  (2019, 'Chevrolet', 'Silverado 1500', 'LT', 'Pickup', 4, '4WD', 8, 5.30, 'Gasoline', 'Automatic'),
  (2018, 'Nissan', 'Altima', 'SV', 'Sedan', 4, 'FWD', 4, 2.50, 'Gasoline', 'CVT'),
  (2020, 'Nissan', 'Rogue', 'SL', 'SUV', 4, 'AWD', 4, 2.50, 'Gasoline', 'CVT'),
  (2017, 'Jeep', 'Wrangler', 'Sport', 'SUV', 2, '4WD', 6, 3.60, 'Gasoline', 'Manual'),
  (2016, 'Subaru', 'Outback', 'Premium', 'Wagon', 4, 'AWD', 4, 2.50, 'Gasoline', 'CVT'),
  (2021, 'Mazda', 'CX-5', 'Touring', 'SUV', 4, 'AWD', 4, 2.50, 'Gasoline', 'Automatic'),
  (2018, 'Mercedes-Benz', 'C300', '4MATIC', 'Sedan', 4, 'AWD', 4, 2.00, 'Gasoline', 'Automatic'),
  (2017, 'Audi', 'A4', 'Premium', 'Sedan', 4, 'AWD', 4, 2.00, 'Gasoline', 'Automatic'),
  (2014, 'Volkswagen', 'Jetta', 'SE', 'Sedan', 4, 'FWD', 4, 1.80, 'Gasoline', 'Automatic'),
  (2020, 'Kia', 'Forte', 'LXS', 'Sedan', 4, 'FWD', 4, 2.00, 'Gasoline', 'CVT'),
  (2016, 'Lexus', 'RX350', 'Base', 'SUV', 4, 'AWD', 6, 3.50, 'Gasoline', 'Automatic'),
  (2020, 'Ram', '1500', 'Big Horn', 'Pickup', 4, '4WD', 8, 5.70, 'Gasoline', 'Automatic')
) AS x(year, make, model, trim, body_class, doors, drive_type, engine_cylinders, engine_displacement_l, fuel_type, transmission)
ON m.make = x.make AND m.model = x.model
ON CONFLICT DO NOTHING;

INSERT INTO part_categories (name, normalized_name, description) VALUES
  ('Filters', 'filters', 'Oil, air, cabin, and fuel filters'),
  ('Ignition', 'ignition', 'Spark plugs, coils, wires, ignition modules'),
  ('Battery', 'battery', 'Batteries and battery service parts'),
  ('Suspension', 'suspension', 'Struts, shocks, arms, hubs, steering parts'),
  ('Drivetrain', 'drivetrain', 'Axles, hubs, bearings, and related parts'),
  ('Engine', 'engine', 'Sensors, pumps, belts, and engine accessories'),
  ('HVAC', 'hvac', 'A/C compressors, condensers, and blower parts'),
  ('Exhaust', 'exhaust', 'Oxygen sensors, catalytic and exhaust components')
ON CONFLICT (normalized_name) DO NOTHING;

WITH cat AS (SELECT id, normalized_name FROM part_categories)
INSERT INTO part_types (category_id, name, normalized_name, description)
SELECT cat.id, x.name, x.normalized_name, x.description
FROM cat JOIN (VALUES
  ('brakes', 'Rear Brake Pads', 'rear_brake_pads', 'Rear brake pad set'),
  ('brakes', 'Brake Rotor', 'brake_rotor', 'Disc brake rotor'),
  ('brakes', 'Brake Caliper', 'brake_caliper', 'Loaded brake caliper'),
  ('filters', 'Oil Filter', 'oil_filter', 'Spin-on or cartridge oil filter'),
  ('filters', 'Engine Air Filter', 'air_filter', 'Engine intake air filter'),
  ('filters', 'Cabin Air Filter', 'cabin_air_filter', 'Cabin HVAC pollen filter'),
  ('ignition', 'Spark Plug Set', 'spark_plug_set', 'Set of spark plugs'),
  ('ignition', 'Ignition Coil', 'ignition_coil', 'Single ignition coil'),
  ('battery', 'Battery', 'battery', 'Automotive battery'),
  ('suspension', 'Strut Assembly', 'strut_assembly', 'Complete loaded strut assembly'),
  ('suspension', 'Shock Absorber', 'shock_absorber', 'Suspension shock absorber'),
  ('suspension', 'Control Arm', 'control_arm', 'Control arm with bushing'),
  ('drivetrain', 'Wheel Hub Assembly', 'wheel_hub', 'Wheel bearing and hub assembly'),
  ('exhaust', 'Oxygen Sensor', 'oxygen_sensor', 'O2 sensor'),
  ('engine', 'Fuel Pump', 'fuel_pump', 'Electric fuel pump assembly'),
  ('cooling', 'Water Pump', 'water_pump', 'Engine water pump'),
  ('hvac', 'A/C Compressor', 'ac_compressor', 'Air conditioning compressor'),
  ('engine', 'Serpentine Belt', 'serpentine_belt', 'Accessory drive belt'),
  ('lighting', 'Tail Light Assembly', 'tail_light_assembly', 'Complete tail light assembly'),
  ('lighting', 'Wiper Blade Set', 'wiper_blade_set', 'Front wiper blade pair'),
  ('body', 'Bumper Cover', 'bumper_cover', 'Paintable bumper cover')
) AS x(category_norm, name, normalized_name, description)
ON cat.normalized_name = x.category_norm
ON CONFLICT (normalized_name) DO NOTHING;

WITH pt AS (SELECT id, normalized_name FROM part_types)
INSERT INTO part_aliases (part_type_id, alias, normalized_alias)
SELECT pt.id, x.alias, lower(x.alias)
FROM pt JOIN (VALUES
  ('rear_brake_pads', 'rear brake pads'), ('rear_brake_pads', 'rear pads'), ('rear_brake_pads', 'back brake pads'),
  ('brake_rotor', 'rotor'), ('brake_rotor', 'rotors'), ('brake_rotor', 'disc'),
  ('brake_caliper', 'caliper'), ('brake_caliper', 'loaded caliper'),
  ('oil_filter', 'oil filter'), ('oil_filter', 'filter for oil'),
  ('air_filter', 'air filter'), ('air_filter', 'engine air filter'),
  ('cabin_air_filter', 'cabin filter'), ('cabin_air_filter', 'pollen filter'),
  ('spark_plug_set', 'spark plugs'), ('spark_plug_set', 'plugs'),
  ('ignition_coil', 'coil'), ('ignition_coil', 'ignition coil'),
  ('battery', 'battery'), ('battery', 'car battery'),
  ('strut_assembly', 'strut'), ('strut_assembly', 'loaded strut'),
  ('shock_absorber', 'shock'), ('shock_absorber', 'shocks'),
  ('control_arm', 'control arm'), ('control_arm', 'lower control arm'),
  ('wheel_hub', 'wheel hub'), ('wheel_hub', 'hub assembly'),
  ('oxygen_sensor', 'oxygen sensor'), ('oxygen_sensor', 'o2 sensor'),
  ('fuel_pump', 'fuel pump'), ('water_pump', 'water pump'),
  ('ac_compressor', 'a/c compressor'), ('ac_compressor', 'ac compressor'),
  ('serpentine_belt', 'belt'), ('serpentine_belt', 'serpentine belt'),
  ('tail_light_assembly', 'tail light'), ('tail_light_assembly', 'taillight'),
  ('wiper_blade_set', 'wipers'), ('wiper_blade_set', 'wiper blades'),
  ('bumper_cover', 'bumper'), ('bumper_cover', 'bumper cover')
) AS x(part_norm, alias)
ON pt.normalized_name = x.part_norm
ON CONFLICT (part_type_id, normalized_alias) DO NOTHING;

INSERT INTO brands (name, brand_type, website_url) VALUES
  ('Wagner', 'aftermarket', 'https://www.wagnerbrake.com'),
  ('Bosch', 'aftermarket', 'https://www.boschautoparts.com'),
  ('Denso', 'oem', 'https://www.densoautoparts.com'),
  ('ACDelco', 'oem', 'https://www.acdelco.com'),
  ('Motorcraft', 'oem', 'https://www.motorcraft.com'),
  ('Monroe', 'aftermarket', 'https://www.monroe.com'),
  ('MOOG', 'aftermarket', 'https://www.moogparts.com'),
  ('Gates', 'aftermarket', 'https://www.gates.com'),
  ('NGK', 'aftermarket', 'https://www.ngkntk.com'),
  ('FRAM', 'aftermarket', 'https://www.fram.com'),
  ('Raybestos', 'aftermarket', 'https://www.raybestos.com'),
  ('PowerStop', 'performance', 'https://www.powerstop.com'),
  ('TYC', 'aftermarket', 'https://www.tycusa.com'),
  ('Dorman', 'aftermarket', 'https://www.dormanproducts.com'),
  ('Delphi', 'aftermarket', 'https://www.delphiautoparts.com'),
  ('Timken', 'aftermarket', 'https://www.timken.com'),
  ('KYB', 'aftermarket', 'https://www.kyb.com'),
  ('Valeo', 'aftermarket', 'https://www.valeo.com')
ON CONFLICT (name) DO NOTHING;

WITH pt AS (SELECT id, normalized_name FROM part_types), b AS (SELECT id, name FROM brands)
INSERT INTO part_products (part_type_id, brand_id, manufacturer_part_number, sku, title, quality, condition_grade, warranty_days, core_charge, msrp, interchange_part_numbers)
SELECT pt.id, b.id, x.mpn, x.sku, x.title, x.quality::part_quality, 'New', x.warranty_days, x.core_charge, x.msrp, ARRAY[x.mpn || '-ALT', x.sku]::text[]
FROM pt
JOIN (VALUES
  ('front_brake_pads', 'Wagner', 'ZD1210', 'SKU-BRK-TYT-CAM-12-17-WAG-F', 'Wagner Front Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 365, 0, 64.99),
  ('rear_brake_pads', 'Wagner', 'ZD1212', 'SKU-BRK-TYT-CAM-12-17-WAG-R', 'Wagner Rear Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 365, 0, 59.99),
  ('brake_rotor', 'Raybestos', '980418R', 'SKU-ROT-TYT-CAM-12-17-RAY', 'Raybestos Front Brake Rotor - Toyota Camry', 'aftermarket', 365, 0, 82.99),
  ('oil_filter', 'FRAM', 'PH4386', 'SKU-FLT-TYT-CAM-FRAM-OIL', 'FRAM Oil Filter - Toyota 2.5L', 'aftermarket', 180, 0, 11.99),
  ('air_filter', 'Bosch', 'AF5632', 'SKU-FLT-TYT-CAM-BOS-AIR', 'Bosch Engine Air Filter - Toyota Camry', 'aftermarket', 180, 0, 19.99),
  ('spark_plug_set', 'NGK', 'LFR5AIX11-4', 'SKU-IGN-TYT-CAM-NGK-PLUG', 'NGK Iridium Spark Plug Set - Toyota 2.5L', 'aftermarket', 365, 0, 49.99),
  ('ignition_coil', 'Denso', '6731309', 'SKU-IGN-TYT-CAM-DEN-COIL', 'Denso Ignition Coil - Toyota Camry', 'oem', 365, 0, 84.99),
  ('water_pump', 'Gates', '43526', 'SKU-CLG-TYT-CAM-GAT-WP', 'Gates Water Pump - Toyota Camry 2.5L', 'aftermarket', 365, 0, 72.99),
  ('battery', 'ACDelco', '48AGM', 'SKU-BAT-UNV-ACD-48AGM', 'ACDelco Gold AGM Battery Group 48', 'oem', 365, 18, 209.99),
  ('front_brake_pads', 'Bosch', 'BC914', 'SKU-BRK-HON-CIV-16-21-BOS-F', 'Bosch Front Brake Pads - Honda Civic', 'aftermarket', 365, 0, 54.99),
  ('oil_filter', 'FRAM', 'PH7317', 'SKU-FLT-HON-CIV-FRAM-OIL', 'FRAM Oil Filter - Honda 1.5L/2.0L', 'aftermarket', 180, 0, 10.99),
  ('ac_compressor', 'Valeo', '815672', 'SKU-HVAC-HON-CIV-VALEO-AC', 'Valeo A/C Compressor - Honda Civic', 'aftermarket', 365, 35, 319.99),
  ('alternator', 'Denso', '2100647', 'SKU-ALT-HON-ACC-DEN', 'Denso Alternator - Honda Accord', 'oem', 365, 20, 229.99),
  ('radiator', 'Denso', '2213225', 'SKU-RAD-HON-ACC-DEN', 'Denso Radiator - Honda Accord', 'aftermarket', 365, 0, 169.99),
  ('brake_rotor', 'PowerStop', 'JBR1414EVC', 'SKU-ROT-FRD-F150-PWR', 'PowerStop Front Brake Rotor - Ford F-150', 'performance', 365, 0, 119.99),
  ('oxygen_sensor', 'Bosch', '15717', 'SKU-EXH-FRD-F150-BOS-O2', 'Bosch Upstream Oxygen Sensor - Ford F-150', 'aftermarket', 365, 0, 74.99),
  ('fuel_pump', 'Delphi', 'FG1353', 'SKU-FUEL-FRD-F150-DEL', 'Delphi Fuel Pump Module - Ford F-150', 'aftermarket', 365, 0, 284.99),
  ('shock_absorber', 'Monroe', '58640', 'SKU-SUS-FRD-F150-MON-SHOCK', 'Monroe Load Adjusting Shock - Ford F-150', 'aftermarket', 365, 0, 96.99),
  ('front_brake_pads', 'ACDelco', '17D1367CH', 'SKU-BRK-CHE-SIL-ACD-F', 'ACDelco Front Brake Pads - Silverado 1500', 'oem', 365, 0, 69.99),
  ('alternator', 'ACDelco', '3351096', 'SKU-ALT-CHE-SIL-ACD', 'ACDelco Alternator - Silverado 1500', 'oem', 365, 30, 249.99),
  ('control_arm', 'MOOG', 'RK621387', 'SKU-SUS-CHE-SIL-MOOG-ARM', 'MOOG Lower Control Arm - Silverado 1500', 'aftermarket', 365, 0, 139.99),
  ('tail_light_assembly', 'TYC', '11-6610-00', 'SKU-LGT-CHE-SIL-TYC-RR', 'TYC Right Tail Light - Silverado 1500', 'aftermarket', 180, 0, 109.99),
  ('front_brake_pads', 'Wagner', 'ZD905', 'SKU-BRK-NIS-ALT-WAG-F', 'Wagner Front Brake Pads - Nissan Altima', 'aftermarket', 365, 0, 48.99),
  ('oil_filter', 'FRAM', 'PH6607', 'SKU-FLT-NIS-ALT-FRAM-OIL', 'FRAM Oil Filter - Nissan 2.5L', 'aftermarket', 180, 0, 9.99),
  ('strut_assembly', 'KYB', 'SR4225', 'SKU-SUS-NIS-ALT-KYB-STRUT', 'KYB Loaded Strut - Nissan Altima', 'aftermarket', 365, 0, 174.99),
  ('wiper_blade_set', 'Bosch', 'ICON26A17A', 'SKU-WIP-NIS-ROG-BOS', 'Bosch ICON Wiper Blade Set - Nissan Rogue', 'aftermarket', 180, 0, 42.99),
  ('front_brake_pads', 'PowerStop', 'Z36-1273', 'SKU-BRK-JEP-WRA-PWR-F', 'PowerStop Z36 Front Pads - Jeep Wrangler', 'performance', 365, 0, 76.99),
  ('radiator', 'Denso', '2219405', 'SKU-RAD-JEP-WRA-DEN', 'Denso Radiator - Jeep Wrangler', 'aftermarket', 365, 0, 189.99),
  ('bumper_cover', 'Dorman', '242-5505', 'SKU-BDY-JEP-WRA-DOR-BUMP', 'Dorman Front Bumper Cover - Jeep Wrangler', 'aftermarket', 180, 0, 219.99),
  ('front_brake_pads', 'Wagner', 'ZD929', 'SKU-BRK-SUB-OUT-WAG-F', 'Wagner Front Brake Pads - Subaru Outback', 'aftermarket', 365, 0, 52.99),
  ('wheel_hub', 'Timken', 'HA590315', 'SKU-HUB-SUB-OUT-TIM', 'Timken Front Wheel Hub - Subaru Outback', 'aftermarket', 365, 0, 149.99),
  ('cabin_air_filter', 'Bosch', '6055C', 'SKU-FLT-SUB-OUT-BOS-CABIN', 'Bosch Cabin Air Filter - Subaru Outback', 'aftermarket', 180, 0, 22.99),
  ('front_brake_pads', 'Akebono', 'ACT1473', 'SKU-BRK-BMW-X5-AKE-F', 'Akebono Front Brake Pads - BMW X5', 'aftermarket', 365, 0, 94.99),
  ('control_arm', 'MOOG', 'RK620897', 'SKU-SUS-BMW-X5-MOOG-ARM', 'MOOG Control Arm - BMW X5', 'aftermarket', 365, 0, 184.99),
  ('front_brake_pads', 'Wagner', 'ZD1594', 'SKU-BRK-HYU-ELA-WAG-F', 'Wagner Front Brake Pads - Hyundai Elantra', 'aftermarket', 365, 0, 47.99),
  ('ignition_coil', 'Denso', '6738321', 'SKU-IGN-KIA-FOR-DEN-COIL', 'Denso Ignition Coil - Kia Forte', 'oem', 365, 0, 77.99),
  ('front_brake_pads', 'Raybestos', 'EHT1391H', 'SKU-BRK-LEX-RX-RAY-F', 'Raybestos Front Brake Pads - Lexus RX350', 'aftermarket', 365, 0, 68.99),
  ('oxygen_sensor', 'Denso', '2349041', 'SKU-EXH-LEX-RX-DEN-O2', 'Denso Oxygen Sensor - Lexus RX350', 'oem', 365, 0, 89.99),
  ('brake_rotor', 'PowerStop', 'JBR1797EVC', 'SKU-ROT-RAM-1500-PWR', 'PowerStop Brake Rotor - Ram 1500', 'performance', 365, 0, 124.99),
  ('fuel_pump', 'Delphi', 'FG1647', 'SKU-FUEL-RAM-1500-DEL', 'Delphi Fuel Pump Module - Ram 1500', 'aftermarket', 365, 0, 299.99),
  ('alternator', 'Bosch', 'AL0899X', 'SKU-ALT-MBZ-C300-BOS', 'Bosch Reman Alternator - Mercedes C300', 'remanufactured', 365, 45, 279.99),
  ('oil_filter', 'Mann-Filter', 'HU7197X', 'SKU-FLT-VW-JET-MANN-OIL', 'Mann Oil Filter - Volkswagen/Audi 2.0L', 'aftermarket', 180, 0, 14.99)
) AS x(part_norm, brand_name, mpn, sku, title, quality, warranty_days, core_charge, msrp)
ON pt.normalized_name = x.part_norm
JOIN b ON b.name = x.brand_name
ON CONFLICT DO NOTHING;

INSERT INTO brands (name, brand_type) VALUES
  ('Akebono', 'aftermarket'),
  ('Mann-Filter', 'aftermarket')
ON CONFLICT (name) DO NOTHING;

-- Retry the two premium-brand rows after their brands exist.
WITH pt AS (SELECT id, normalized_name FROM part_types), b AS (SELECT id, name FROM brands)
INSERT INTO part_products (part_type_id, brand_id, manufacturer_part_number, sku, title, quality, condition_grade, warranty_days, core_charge, msrp, interchange_part_numbers)
SELECT pt.id, b.id, x.mpn, x.sku, x.title, x.quality::part_quality, 'New', x.warranty_days, x.core_charge, x.msrp, ARRAY[x.mpn || '-ALT', x.sku]::text[]
FROM pt
JOIN (VALUES
  ('front_brake_pads', 'Akebono', 'ACT1473', 'SKU-BRK-BMW-X5-AKE-F', 'Akebono Front Brake Pads - BMW X5', 'aftermarket', 365, 0, 94.99),
  ('oil_filter', 'Mann-Filter', 'HU7197X', 'SKU-FLT-VW-JET-MANN-OIL', 'Mann Oil Filter - Volkswagen/Audi 2.0L', 'aftermarket', 180, 0, 14.99)
) AS x(part_norm, brand_name, mpn, sku, title, quality, warranty_days, core_charge, msrp)
ON pt.normalized_name = x.part_norm
JOIN b ON b.name = x.brand_name
ON CONFLICT DO NOTHING;

INSERT INTO part_fitments (part_product_id, year_start, year_end, make, model, trim, engine, qualifiers)
SELECT pp.id, x.year_start, x.year_end, x.make, x.model, x.trim, x.engine, x.qualifiers
FROM part_products pp JOIN (VALUES
  ('ZD1210', 2012, 2017, 'Toyota', 'Camry', NULL, NULL, 'front axle'),
  ('ZD1212', 2012, 2017, 'Toyota', 'Camry', NULL, NULL, 'rear axle'),
  ('980418R', 2012, 2017, 'Toyota', 'Camry', NULL, NULL, 'front rotor'),
  ('PH4386', 2010, 2017, 'Toyota', 'Camry', NULL, '2.5L', '2.5L engine'),
  ('AF5632', 2012, 2017, 'Toyota', 'Camry', NULL, NULL, NULL),
  ('LFR5AIX11-4', 2012, 2017, 'Toyota', 'Camry', NULL, '2.5L', 'set of four'),
  ('6731309', 2012, 2017, 'Toyota', 'Camry', NULL, '2.5L', NULL),
  ('43526', 2012, 2017, 'Toyota', 'Camry', NULL, '2.5L', NULL),
  ('48AGM', 2010, 2024, 'Toyota', 'Camry', NULL, NULL, 'group 48 fitment'),
  ('48AGM', 2015, 2024, 'Ford', 'F-150', NULL, NULL, 'group 48 fitment'),
  ('BC914', 2016, 2021, 'Honda', 'Civic', NULL, NULL, 'front axle'),
  ('PH7317', 2012, 2021, 'Honda', 'Civic', NULL, NULL, NULL),
  ('815672', 2016, 2021, 'Honda', 'Civic', NULL, NULL, NULL),
  ('2100647', 2018, 2022, 'Honda', 'Accord', NULL, '1.5L', NULL),
  ('2213225', 2018, 2022, 'Honda', 'Accord', NULL, '1.5L', NULL),
  ('JBR1414EVC', 2015, 2021, 'Ford', 'F-150', NULL, NULL, 'front rotor'),
  ('15717', 2015, 2020, 'Ford', 'F-150', NULL, '3.5L', 'upstream'),
  ('FG1353', 2015, 2020, 'Ford', 'F-150', NULL, NULL, NULL),
  ('58640', 2015, 2020, 'Ford', 'F-150', NULL, NULL, 'rear shock'),
  ('17D1367CH', 2014, 2020, 'Chevrolet', 'Silverado 1500', NULL, NULL, 'front axle'),
  ('3351096', 2014, 2019, 'Chevrolet', 'Silverado 1500', NULL, '5.3L', NULL),
  ('RK621387', 2014, 2020, 'Chevrolet', 'Silverado 1500', NULL, NULL, 'lower control arm'),
  ('11-6610-00', 2014, 2018, 'Chevrolet', 'Silverado 1500', NULL, NULL, 'right side'),
  ('ZD905', 2013, 2018, 'Nissan', 'Altima', NULL, NULL, 'front axle'),
  ('PH6607', 2013, 2021, 'Nissan', 'Altima', NULL, '2.5L', NULL),
  ('SR4225', 2013, 2018, 'Nissan', 'Altima', NULL, NULL, 'front left/right'),
  ('ICON26A17A', 2017, 2022, 'Nissan', 'Rogue', NULL, NULL, 'front pair'),
  ('Z36-1273', 2007, 2018, 'Jeep', 'Wrangler', NULL, NULL, 'front axle'),
  ('2219405', 2012, 2018, 'Jeep', 'Wrangler', NULL, '3.6L', NULL),
  ('242-5505', 2007, 2018, 'Jeep', 'Wrangler', NULL, NULL, 'front bumper'),
  ('ZD929', 2015, 2019, 'Subaru', 'Outback', NULL, NULL, 'front axle'),
  ('HA590315', 2015, 2019, 'Subaru', 'Outback', NULL, NULL, 'front hub'),
  ('6055C', 2015, 2019, 'Subaru', 'Outback', NULL, NULL, NULL),
  ('ACT1473', 2014, 2018, 'BMW', 'X5', NULL, NULL, 'front axle'),
  ('RK620897', 2014, 2018, 'BMW', 'X5', NULL, NULL, 'front lower'),
  ('ZD1594', 2017, 2020, 'Hyundai', 'Elantra', NULL, NULL, 'front axle'),
  ('6738321', 2019, 2021, 'Kia', 'Forte', NULL, '2.0L', NULL),
  ('EHT1391H', 2016, 2019, 'Lexus', 'RX350', NULL, NULL, 'front axle'),
  ('2349041', 2016, 2019, 'Lexus', 'RX350', NULL, '3.5L', 'upstream'),
  ('JBR1797EVC', 2019, 2023, 'Ram', '1500', NULL, NULL, 'front rotor'),
  ('FG1647', 2019, 2023, 'Ram', '1500', NULL, '5.7L', NULL),
  ('AL0899X', 2015, 2018, 'Mercedes-Benz', 'C300', NULL, '2.0L', NULL),
  ('HU7197X', 2012, 2018, 'Volkswagen', 'Jetta', NULL, '1.8L', NULL),
  ('HU7197X', 2012, 2018, 'Audi', 'A4', NULL, '2.0L', NULL)
) AS x(mpn, year_start, year_end, make, model, trim, engine, qualifiers)
ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     loc AS (SELECT id, city FROM shop_locations WHERE shop_id = (SELECT id FROM shop)),
     sup AS (SELECT id, name FROM suppliers WHERE shop_id = (SELECT id FROM shop)),
     pp AS (SELECT id, manufacturer_part_number FROM part_products)
INSERT INTO inventory_items (shop_id, location_id, supplier_id, part_product_id, quantity_available, price, cost, status, lead_time_hours, shelf_location, notes, last_synced_at)
SELECT shop.id, loc.id, sup.id, pp.id, x.qty, x.price, x.cost, x.status::inventory_status, x.lead, x.shelf, x.notes, now() - x.synced_ago::interval
FROM shop
CROSS JOIN (VALUES
  ('San Francisco', 'Budget Auto Parts', 'ZD1210', 8, 42.99, 21.00, 'available', 0, 'B12', 'high-confidence demo match', '6 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ZD1212', 5, 39.99, 19.50, 'available', 0, 'B13', 'rear set', '6 minutes'),
  ('San Francisco', 'OEM Direct Dealer', '980418R', 4, 64.99, 34.00, 'available', 24, 'DROPSHIP', 'two rotors recommended', '20 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'PH4386', 18, 8.99, 3.10, 'available', 0, 'F1-01', 'counter fast mover', '6 minutes'),
  ('Calgary', 'Budget Auto Parts', 'AF5632', 10, 15.99, 7.25, 'available', 0, 'F2-04', NULL, '12 minutes'),
  ('Toronto', 'Premium Reman Supply', 'LFR5AIX11-4', 6, 41.99, 22.00, 'available', 12, 'I4-02', 'set of four', '18 minutes'),
  ('San Francisco', 'OEM Direct Dealer', '6731309', 3, 74.99, 43.00, 'available', 24, 'DROPSHIP', NULL, '20 minutes'),
  ('Calgary', 'Budget Auto Parts', '43526', 2, 58.99, 31.00, 'available', 12, 'C7-03', NULL, '12 minutes'),
  ('San Francisco', 'OEM Direct Dealer', '48AGM', 7, 189.99, 132.00, 'available', 0, 'BAT-2', 'core applies', '5 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'BC914', 9, 44.99, 22.00, 'available', 0, 'B15', NULL, '6 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'PH7317', 24, 7.99, 2.95, 'available', 0, 'F1-06', NULL, '6 minutes'),
  ('Toronto', 'Premium Reman Supply', '815672', 1, 279.99, 170.00, 'available', 36, 'HVAC-4', 'core applies', '30 minutes'),
  ('Toronto', 'Premium Reman Supply', '2100647', 2, 209.99, 135.00, 'available', 36, 'R4-08', 'core applies', '30 minutes'),
  ('Calgary', 'Budget Auto Parts', '2213225', 2, 139.99, 76.00, 'available', 12, 'C9-01', NULL, '12 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'JBR1414EVC', 6, 99.99, 54.00, 'available', 0, 'R1-02', 'front rotor each', '6 minutes'),
  ('San Francisco', 'Budget Auto Parts', '15717', 3, 64.99, 33.00, 'available', 0, 'E3-14', NULL, '6 minutes'),
  ('Toronto', 'Premium Reman Supply', 'FG1353', 1, 249.99, 151.00, 'available', 36, 'FUEL-2', NULL, '30 minutes'),
  ('Calgary', 'Budget Auto Parts', '58640', 4, 79.99, 41.00, 'available', 12, 'S5-09', 'each', '12 minutes'),
  ('San Francisco', 'OEM Direct Dealer', '17D1367CH', 5, 58.99, 31.00, 'available', 24, 'DROPSHIP', NULL, '20 minutes'),
  ('Toronto', 'Premium Reman Supply', '3351096', 2, 219.99, 140.00, 'available', 36, 'R5-03', 'core applies', '30 minutes'),
  ('Calgary', 'Budget Auto Parts', 'RK621387', 2, 119.99, 66.00, 'available', 12, 'S7-02', NULL, '12 minutes'),
  ('San Francisco', 'Budget Auto Parts', '11-6610-00', 1, 89.99, 48.00, 'available', 0, 'L3-11', 'right side', '6 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ZD905', 7, 38.99, 18.00, 'available', 0, 'B18', NULL, '6 minutes'),
  ('Calgary', 'Budget Auto Parts', 'PH6607', 20, 7.49, 2.80, 'available', 0, 'F1-09', NULL, '12 minutes'),
  ('Toronto', 'Premium Reman Supply', 'SR4225', 2, 149.99, 88.00, 'available', 36, 'S2-08', 'front loaded strut', '30 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ICON26A17A', 12, 34.99, 18.00, 'available', 0, 'W1-01', 'pair', '6 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'Z36-1273', 6, 66.99, 34.00, 'available', 0, 'B22', 'tow/off-road pad', '6 minutes'),
  ('Calgary', 'Rapid Wreckers', '2219405', 1, 159.99, 80.00, 'available', 24, 'YARD-12', 'inspected used radiator', '45 minutes'),
  ('San Francisco', 'Rapid Wreckers', '242-5505', 1, 179.99, 90.00, 'available', 4, 'YARD-3', 'black textured', '45 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ZD929', 5, 42.99, 21.00, 'available', 0, 'B24', NULL, '6 minutes'),
  ('Toronto', 'Premium Reman Supply', 'HA590315', 2, 129.99, 73.00, 'available', 36, 'H2-14', NULL, '30 minutes'),
  ('Calgary', 'Budget Auto Parts', '6055C', 9, 17.99, 8.00, 'available', 0, 'F3-04', NULL, '12 minutes'),
  ('San Francisco', 'OEM Direct Dealer', 'ACT1473', 2, 84.99, 47.00, 'available', 24, 'DROPSHIP', 'premium ceramic', '20 minutes'),
  ('Toronto', 'Premium Reman Supply', 'RK620897', 1, 159.99, 92.00, 'available', 36, 'S9-01', NULL, '30 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ZD1594', 4, 39.99, 18.50, 'available', 0, 'B27', NULL, '6 minutes'),
  ('Calgary', 'Budget Auto Parts', '6738321', 4, 64.99, 36.00, 'available', 12, 'I7-02', NULL, '12 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'EHT1391H', 3, 56.99, 30.00, 'available', 0, 'B31', NULL, '6 minutes'),
  ('Toronto', 'Premium Reman Supply', '2349041', 2, 79.99, 42.00, 'available', 36, 'E4-01', NULL, '30 minutes'),
  ('Calgary', 'Budget Auto Parts', 'JBR1797EVC', 4, 104.99, 58.00, 'available', 12, 'R7-05', 'front rotor each', '12 minutes'),
  ('Toronto', 'Premium Reman Supply', 'FG1647', 1, 269.99, 168.00, 'available', 36, 'FUEL-8', NULL, '30 minutes'),
  ('Toronto', 'Premium Reman Supply', 'AL0899X', 1, 239.99, 150.00, 'available', 36, 'R8-04', 'reman core applies', '30 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'HU7197X', 14, 10.99, 4.50, 'available', 0, 'F1-12', NULL, '6 minutes')
) AS x(city, supplier, mpn, qty, price, cost, status, lead, shelf, notes, synced_ago)
JOIN loc ON loc.city = x.city
JOIN sup ON sup.name = x.supplier
JOIN pp ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo')
INSERT INTO customers (shop_id, name, phone, email, city, state_region, preferred_contact_method, marketing_opt_in)
SELECT shop.id, x.name, x.phone, x.email, x.city, x.state_region, 'sms', x.opt_in
FROM shop, (VALUES
  ('Jamie Rivera', '+14155550101', 'jamie@example.com', 'San Francisco', 'CA', true),
  ('Morgan Lee', '+14155550102', 'morgan@example.com', 'Oakland', 'CA', false),
  ('Taylor Chen', '+14155550103', 'taylor@example.com', 'San Jose', 'CA', true),
  ('Chris Patel', '+14035550104', 'chris@example.com', 'Calgary', 'AB', true),
  ('Avery Brooks', '+14165550105', 'avery@example.com', 'Toronto', 'ON', false),
  ('Sam Johnson', '+14155550106', 'sam@example.com', 'San Francisco', 'CA', true),
  ('Jordan Kim', '+14155550107', 'jordan@example.com', 'Daly City', 'CA', false),
  ('Riley Garcia', '+14035550108', 'riley@example.com', 'Calgary', 'AB', true),
  ('Casey Nguyen', '+14165550109', 'casey@example.com', 'Toronto', 'ON', true),
  ('Drew Martin', '+14155550110', 'drew@example.com', 'Berkeley', 'CA', false)
) AS x(name, phone, email, city, state_region, opt_in)
ON CONFLICT (shop_id, phone) DO NOTHING;

WITH c AS (SELECT id, phone FROM customers)
INSERT INTO customer_vehicles (customer_id, vin, year, make, model, trim, engine, notes)
SELECT c.id, x.vin, x.year, x.make, x.model, x.trim, x.engine, x.notes
FROM c JOIN (VALUES
  ('+14155550101', '4T1BF1FK5FU000001', 2015, 'Toyota', 'Camry', 'SE', '2.5L', 'caller asks for front pads often'),
  ('+14155550102', '2HGFC2F59HH000002', 2017, 'Honda', 'Civic', 'LX', '2.0L', NULL),
  ('+14155550103', '1FTEW1EG6JFA00003', 2018, 'Ford', 'F-150', 'XLT', '3.5L', 'uses truck for work'),
  ('+14035550104', '1GCUYDED0KZ000004', 2019, 'Chevrolet', 'Silverado 1500', 'LT', '5.3L', NULL),
  ('+14165550105', '1N4AL3AP8JC000005', 2018, 'Nissan', 'Altima', 'SV', '2.5L', NULL),
  ('+14155550106', 'JF2BSABC6GG000006', 2016, 'Subaru', 'Outback', 'Premium', '2.5L', NULL),
  ('+14155550107', '5UXKR0C50F0000007', 2015, 'BMW', 'X5', '35i', '3.0L', 'prefers premium parts'),
  ('+14035550108', '1C4HJWDG5HL000008', 2017, 'Jeep', 'Wrangler', 'Sport', '3.6L', NULL),
  ('+14165550109', 'JTJBZMCA1G2000009', 2016, 'Lexus', 'RX350', 'Base', '3.5L', NULL),
  ('+14155550110', '3C6RR7LT6LG000010', 2020, 'Ram', '1500', 'Big Horn', '5.7L', NULL)
) AS x(phone, vin, year, make, model, trim, engine, notes)
ON c.phone = x.phone;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     cust AS (SELECT id, phone FROM customers WHERE shop_id = (SELECT id FROM shop))
INSERT INTO calls (shop_id, vapi_call_id, from_phone, to_phone, customer_id, status, lead_status, started_at, ended_at, duration_seconds, intent, requested_part_text, vehicle_text, transcript, summary, outcome, estimated_revenue, raw_payload)
SELECT shop.id, x.vapi_call_id, x.from_phone, '+14155550123', cust.id, x.status::call_status, x.lead_status::lead_status,
       now() - x.started_ago::interval, now() - x.ended_ago::interval, x.duration_seconds, x.intent, x.requested_part_text,
       x.vehicle_text, x.transcript, x.summary, x.outcome, x.estimated_revenue, x.raw_payload::jsonb
FROM shop
CROSS JOIN (VALUES
  ('demo-call-001', '+14155550101', 'completed', 'quoted', '2 hours', '1 hours 57 minutes', 183, 'quote_part', 'front brake pads', '2015 Toyota Camry', 'Caller needed front brake pads for a 2015 Camry. AI found Wagner pads in stock.', 'Quoted Wagner ZD1210 pads at shelf B12.', 'in_stock', 42.99, '{"demo":true,"tool":"check_inventory"}'),
  ('demo-call-002', '+14155550102', 'completed', 'hold_created', '3 hours', '2 hours 55 minutes', 294, 'quote_part', 'starter motor', '2017 Honda Civic', 'Caller asked for a starter and wanted it held.', 'Used starter offered and hold created.', 'hold_created', 95.00, '{"demo":true}'),
  ('demo-call-003', '+14155550103', 'completed', 'quoted', '5 hours', '4 hours 57 minutes', 211, 'quote_part', 'front rotors', '2018 Ford F-150', 'Caller requested front rotors for a work truck.', 'PowerStop rotors quoted.', 'in_stock', 199.98, '{"demo":true}'),
  ('demo-call-004', '+14035550104', 'completed', 'quoted', '7 hours', '6 hours 58 minutes', 146, 'quote_part', 'alternator', '2019 Chevy Silverado', 'Caller asked for an alternator.', 'ACDelco alternator available by transfer.', 'in_stock', 219.99, '{"demo":true}'),
  ('demo-call-005', '+14165550105', 'completed', 'new', '9 hours', '8 hours 59 minutes', 104, 'quote_part', 'left headlight', '2018 Nissan Altima', 'Caller needed a headlight not in stock.', 'Captured lead for follow-up.', 'miss', 0, '{"demo":true}'),
  ('demo-call-006', '+14155550106', 'completed', 'quoted', '12 hours', '11 hours 57 minutes', 190, 'quote_part', 'wheel hub', '2016 Subaru Outback', 'Caller asked for front wheel hub.', 'Timken hub quoted from Toronto.', 'in_stock', 129.99, '{"demo":true}'),
  ('demo-call-007', '+14155550107', 'transferred', 'transferred', '1 day', '23 hours 55 minutes', 331, 'quote_part', 'control arm', '2015 BMW X5', 'Caller wanted premium option and human confirmation.', 'Transferred after finding MOOG control arm.', 'transferred', 159.99, '{"demo":true}'),
  ('demo-call-008', '+14035550108', 'completed', 'quoted', '1 day 3 hours', '1 day 2 hours 56 minutes', 242, 'quote_part', 'radiator', '2017 Jeep Wrangler', 'Caller asked for radiator.', 'Used inspected radiator found.', 'in_stock', 159.99, '{"demo":true}'),
  ('demo-call-009', '+14165550109', 'completed', 'quoted', '1 day 6 hours', '1 day 5 hours 58 minutes', 128, 'quote_part', 'oxygen sensor', '2016 Lexus RX350', 'Caller needed upstream O2 sensor.', 'Denso oxygen sensor quoted.', 'in_stock', 79.99, '{"demo":true}'),
  ('demo-call-010', '+14155550110', 'completed', 'quoted', '1 day 9 hours', '1 day 8 hours 57 minutes', 201, 'quote_part', 'fuel pump', '2020 Ram 1500', 'Caller asked for fuel pump module.', 'Delphi pump quoted.', 'in_stock', 269.99, '{"demo":true}'),
  ('demo-call-011', '+14155550998', 'completed', 'new', '1 day 12 hours', '1 day 11 hours 59 minutes', 87, 'hours', 'store hours', NULL, 'Caller asked when the counter closes.', 'Answered store hours.', 'answered', 0, '{"demo":true}'),
  ('demo-call-012', '+14155550997', 'failed', 'spam', '1 day 13 hours', '1 day 12 hours 59 minutes', 33, 'spam', NULL, NULL, 'Spam robocall.', 'Marked as spam.', 'spam', 0, '{"demo":true}')
) AS x(vapi_call_id, from_phone, status, lead_status, started_ago, ended_ago, duration_seconds, intent, requested_part_text, vehicle_text, transcript, summary, outcome, estimated_revenue, raw_payload)
LEFT JOIN cust ON cust.phone = x.from_phone
ON CONFLICT (vapi_call_id) DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo')
INSERT INTO call_tool_events (call_id, tool_name, request_json, response_json, success, latency_ms)
SELECT calls.id, 'check_inventory', x.request_json::jsonb, x.response_json::jsonb, true, x.latency_ms
FROM calls
JOIN (VALUES
  ('demo-call-001', '{"part":"brake pads","position":"front","year":2015,"make":"toyota","model":"camry"}', '{"found":true,"part_number":"ZD1210","qty":8}', 184),
  ('demo-call-002', '{"part":"starter","year":2017,"make":"honda","model":"civic"}', '{"found":true,"part_number":"USED-HON-CIV-16-STR-A","qty":2}', 231),
  ('demo-call-005', '{"part":"left headlight","year":2018,"make":"nissan","model":"altima"}', '{"found":false,"matches":[]}', 156),
  ('demo-call-009', '{"part":"oxygen sensor","year":2016,"make":"lexus","model":"rx350"}', '{"found":true,"part_number":"2349041","qty":2}', 198)
) AS x(vapi_call_id, request_json, response_json, latency_ms)
ON calls.vapi_call_id = x.vapi_call_id
WHERE calls.shop_id = (SELECT id FROM shop);

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     cust AS (SELECT id, phone FROM customers WHERE shop_id = (SELECT id FROM shop)),
     calls_by_id AS (SELECT id, vapi_call_id FROM calls WHERE shop_id = (SELECT id FROM shop)),
     pt AS (SELECT id, normalized_name FROM part_types)
INSERT INTO quote_requests (shop_id, call_id, customer_id, part_type_id, requested_part_text, city, urgency, budget_max, preferred_quality, status, notes)
SELECT shop.id, calls_by_id.id, cust.id, pt.id, x.requested_part_text, x.city, x.urgency, x.budget_max, x.preferred_quality::part_quality, x.status, x.notes
FROM shop
CROSS JOIN (VALUES
  ('demo-call-001', '+14155550101', 'front_brake_pads', 'front brake pads', 'San Francisco', 'today', 80, 'aftermarket', 'quoted', 'AI demo quote'),
  ('demo-call-002', '+14155550102', 'starter', 'starter motor', 'San Francisco', 'today', 150, 'used', 'hold_created', 'caller asked to hold for pickup'),
  ('demo-call-005', '+14165550105', 'headlight_assembly', 'left headlight', 'Toronto', 'normal', 225, 'aftermarket', 'open', 'miss converted to lead')
) AS x(vapi_call_id, phone, part_norm, requested_part_text, city, urgency, budget_max, preferred_quality, status, notes)
JOIN calls_by_id ON calls_by_id.vapi_call_id = x.vapi_call_id
LEFT JOIN cust ON cust.phone = x.phone
LEFT JOIN pt ON pt.normalized_name = x.part_norm;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     calls_by_id AS (SELECT id, vapi_call_id, customer_id FROM calls WHERE shop_id = (SELECT id FROM shop))
INSERT INTO quotes (shop_id, quote_request_id, call_id, customer_id, status, subtotal, tax, fees, total, payment_url, public_quote_token, expires_at)
SELECT shop.id, qr.id, calls_by_id.id, calls_by_id.customer_id, x.status::quote_status, x.subtotal, round(x.subtotal * 0.08625, 2), 0, round(x.subtotal * 1.08625, 2), x.payment_url, x.token, now() + x.expires_in::interval
FROM shop
CROSS JOIN (VALUES
  ('demo-call-001', 'sent', 42.99, 'https://pay.example.com/q/demo-camry-pads', 'demo-camry-pads', '24 hours'),
  ('demo-call-002', 'accepted', 95.00, 'https://pay.example.com/q/demo-civic-starter', 'demo-civic-starter', '4 hours'),
  ('demo-call-003', 'sent', 199.98, 'https://pay.example.com/q/demo-f150-rotors', 'demo-f150-rotors', '24 hours')
) AS x(vapi_call_id, status, subtotal, payment_url, token, expires_in)
JOIN calls_by_id ON calls_by_id.vapi_call_id = x.vapi_call_id
LEFT JOIN quote_requests qr ON qr.call_id = calls_by_id.id
ON CONFLICT (public_quote_token) DO NOTHING;

WITH q AS (SELECT id, public_quote_token FROM quotes),
     ii AS (SELECT id, part_product_id FROM inventory_items),
     pp AS (SELECT id, manufacturer_part_number FROM part_products)
INSERT INTO quote_items (quote_id, inventory_item_id, part_product_id, quantity, unit_price, warranty_days, lead_time_hours)
SELECT q.id, ii.id, pp.id, x.qty, x.unit_price, x.warranty_days, x.lead_time_hours
FROM (VALUES
  ('demo-camry-pads', 'ZD1210', 1, 42.99, 365, 0),
  ('demo-civic-starter', 'USED-HON-CIV-16-STR-A', 1, 95.00, 30, 2),
  ('demo-f150-rotors', 'JBR1414EVC', 2, 99.99, 365, 0)
) AS x(token, mpn, qty, unit_price, warranty_days, lead_time_hours)
JOIN q ON q.public_quote_token = x.token
JOIN pp ON pp.manufacturer_part_number = x.mpn
LEFT JOIN ii ON ii.part_product_id = pp.id;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     q AS (SELECT id, public_quote_token, call_id, customer_id FROM quotes),
     ii AS (SELECT inventory_items.id, part_products.manufacturer_part_number FROM inventory_items JOIN part_products ON part_products.id = inventory_items.part_product_id)
INSERT INTO inventory_holds (shop_id, inventory_item_id, customer_id, call_id, quote_id, quantity, status, expires_at)
SELECT shop.id, ii.id, q.customer_id, q.call_id, q.id, 1, 'active', now() + interval '25 minutes'
FROM shop
JOIN q ON q.public_quote_token = 'demo-civic-starter'
JOIN ii ON ii.manufacturer_part_number = 'USED-HON-CIV-16-STR-A';

CREATE TABLE IF NOT EXISTS leads (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  call_id UUID REFERENCES calls(id) ON DELETE SET NULL,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  caller_number TEXT NOT NULL,
  part_requested TEXT NOT NULL,
  vehicle TEXT,
  note TEXT,
  status lead_status NOT NULL DEFAULT 'new',
  estimated_value NUMERIC(10,2) NOT NULL DEFAULT 0,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_leads_updated_at ON leads;
CREATE TRIGGER trg_leads_updated_at BEFORE UPDATE ON leads FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE INDEX IF NOT EXISTS idx_leads_shop_created ON leads(shop_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_leads_status ON leads(status);

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     calls_by_id AS (SELECT id, vapi_call_id, customer_id FROM calls WHERE shop_id = (SELECT id FROM shop))
INSERT INTO leads (shop_id, call_id, customer_id, caller_number, part_requested, vehicle, note, status, estimated_value, created_at)
SELECT shop.id, calls_by_id.id, calls_by_id.customer_id, x.caller_number, x.part_requested, x.vehicle, x.note, x.status::lead_status, x.estimated_value, now() - x.created_ago::interval
FROM shop
CROSS JOIN (VALUES
  ('demo-call-005', '+14165550105', 'left headlight assembly', '2018 Nissan Altima', 'Not stocked. Check supplier and text customer.', 'new', 190.00, '8 hours'),
  (NULL, '+14155550221', 'rear bumper cover', '2021 Mazda CX-5', 'Customer wants paintable cover, prefers aftermarket.', 'new', 240.00, '10 hours'),
  (NULL, '+14155550222', 'hybrid battery quote', '2014 Toyota Prius', 'Outside current inventory. Escalate to specialist.', 'new', 1200.00, '13 hours'),
  ('demo-call-007', '+14155550107', 'front lower control arm', '2015 BMW X5', 'Transferred for premium confirmation.', 'transferred', 159.99, '23 hours'),
  (NULL, '+14035550223', 'transmission assembly', '2016 Ford Escape', 'Caller needs used low-mileage unit.', 'quoted', 1850.00, '1 day 4 hours'),
  (NULL, '+14165550224', 'driver side mirror', '2020 Hyundai Elantra', 'Ask supplier for painted white option.', 'new', 145.00, '1 day 8 hours')
) AS x(vapi_call_id, caller_number, part_requested, vehicle, note, status, estimated_value, created_ago)
LEFT JOIN calls_by_id ON calls_by_id.vapi_call_id = x.vapi_call_id
;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     cust AS (SELECT id, phone FROM customers WHERE shop_id = (SELECT id FROM shop)),
     calls_by_id AS (SELECT id, vapi_call_id FROM calls WHERE shop_id = (SELECT id FROM shop)),
     q AS (SELECT id, public_quote_token FROM quotes)
INSERT INTO sms_messages (shop_id, customer_id, call_id, quote_id, provider, provider_message_id, to_phone, from_phone, body, status, sent_at)
SELECT shop.id, cust.id, calls_by_id.id, q.id, 'twilio', x.provider_message_id, x.to_phone, '+14155550123', x.body, x.status, now() - x.sent_ago::interval
FROM shop
CROSS JOIN (VALUES
  ('SMdemo001', '+14155550101', 'demo-call-001', 'demo-camry-pads', 'PartsPanda: Wagner front brake pads for your 2015 Camry are $42.99, shelf B12. Reply HOLD to reserve.', 'sent', '1 hours 55 minutes'),
  ('SMdemo002', '+14155550102', 'demo-call-002', 'demo-civic-starter', 'PartsPanda: We are holding the used Honda Civic starter for 30 minutes. Quote total is $103.19.', 'sent', '2 hours 50 minutes'),
  ('SMdemo003', '+14165550105', 'demo-call-005', NULL, 'PartsPanda: We do not have the Altima headlight in stock yet. We are checking suppliers and will text you back.', 'sent', '8 hours 56 minutes')
) AS x(provider_message_id, to_phone, vapi_call_id, quote_token, body, status, sent_ago)
LEFT JOIN cust ON cust.phone = x.to_phone
LEFT JOIN calls_by_id ON calls_by_id.vapi_call_id = x.vapi_call_id
LEFT JOIN q ON q.public_quote_token = x.quote_token;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo')
INSERT INTO daily_metrics (shop_id, metric_date, total_calls, ai_answered_calls, missed_calls_pre_ai_estimate, quotes_created, holds_created, transfers_to_human, avg_call_duration_seconds, estimated_revenue_recovered, labour_minutes_saved)
SELECT shop.id, x.metric_date, x.total_calls, x.ai_answered_calls, x.missed_calls_pre_ai_estimate, x.quotes_created, x.holds_created, x.transfers_to_human, x.avg_call_duration_seconds, x.estimated_revenue_recovered, x.labour_minutes_saved
FROM shop, (VALUES
  (current_date, 12, 11, 4, 8, 1, 1, 179, 1248.90, 96.5),
  (current_date - 1, 18, 16, 6, 10, 2, 2, 203, 1835.40, 142.0),
  (current_date - 2, 15, 14, 5, 9, 1, 1, 188, 1512.75, 118.5),
  (current_date - 3, 21, 19, 7, 13, 3, 2, 215, 2299.20, 166.0),
  (current_date - 4, 14, 13, 4, 7, 1, 1, 171, 1034.55, 89.0),
  (current_date - 5, 17, 15, 5, 9, 2, 1, 196, 1698.10, 127.5),
  (current_date - 6, 11, 10, 3, 6, 1, 0, 164, 905.40, 76.0)
) AS x(metric_date, total_calls, ai_answered_calls, missed_calls_pre_ai_estimate, quotes_created, holds_created, transfers_to_human, avg_call_duration_seconds, estimated_revenue_recovered, labour_minutes_saved)
ON CONFLICT (shop_id, metric_date) DO UPDATE
SET total_calls = EXCLUDED.total_calls,
    ai_answered_calls = EXCLUDED.ai_answered_calls,
    missed_calls_pre_ai_estimate = EXCLUDED.missed_calls_pre_ai_estimate,
    quotes_created = EXCLUDED.quotes_created,
    holds_created = EXCLUDED.holds_created,
    transfers_to_human = EXCLUDED.transfers_to_human,
    avg_call_duration_seconds = EXCLUDED.avg_call_duration_seconds,
    estimated_revenue_recovered = EXCLUDED.estimated_revenue_recovered,
    labour_minutes_saved = EXCLUDED.labour_minutes_saved;

CREATE OR REPLACE VIEW inventory AS
SELECT
  ii.id,
  pc.normalized_name AS category,
  pt.name AS part_name,
  CASE
    WHEN pt.normalized_name ILIKE 'front_%' OR pf.qualifiers ILIKE '%front%' THEN 'front'
    WHEN pt.normalized_name ILIKE 'rear_%' OR pf.qualifiers ILIKE '%rear%' THEN 'rear'
    WHEN pf.qualifiers ILIKE '%left%' THEN 'left'
    WHEN pf.qualifiers ILIKE '%right%' THEN 'right'
    ELSE NULL
  END AS position,
  b.name AS brand,
  pp.manufacturer_part_number AS part_number,
  pf.year_start,
  pf.year_end,
  lower(pf.make) AS make,
  lower(pf.model) AS model,
  CONCAT(pf.year_start, '-', pf.year_end, ' ', pf.make, ' ', pf.model) AS fitment_text,
  (ii.quantity_available - ii.quantity_reserved) AS qty,
  ii.price,
  ii.shelf_location AS shelf
FROM inventory_items ii
JOIN part_products pp ON pp.id = ii.part_product_id
JOIN part_types pt ON pt.id = pp.part_type_id
LEFT JOIN part_categories pc ON pc.id = pt.category_id
LEFT JOIN brands b ON b.id = pp.brand_id
LEFT JOIN part_fitments pf ON pf.part_product_id = pp.id
WHERE ii.status = 'available';

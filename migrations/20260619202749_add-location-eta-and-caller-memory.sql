-- Expose inventory city/realistic ETAs and add caller memory for voice personalization.

-- Lead times are now operationally realistic from the San Francisco home counter:
-- 0h = in-store today, 24h = next day, 48h = two-day local transfer,
-- 72h = 3-day regional transfer, 120h = 5-day special order,
-- 168h = 7-day warehouse transfer.
UPDATE inventory_items ii
SET lead_time_hours = CASE
  WHEN ii.lead_time_hours = 0 THEN 0
  WHEN ii.lead_time_hours <= 2 THEN 24
  WHEN ii.lead_time_hours <= 4 THEN 48
  WHEN ii.lead_time_hours <= 12 THEN 72
  WHEN ii.lead_time_hours <= 24 THEN 120
  WHEN ii.lead_time_hours <= 36 THEN 168
  ELSE ii.lead_time_hours
END;

UPDATE inventory_items
SET service_level = CASE
  WHEN lead_time_hours = 0 THEN 'local-same-day'
  WHEN lead_time_hours <= 24 THEN 'next-day'
  WHEN lead_time_hours <= 48 THEN 'two-day-local-transfer'
  WHEN lead_time_hours <= 72 THEN 'three-day-regional-transfer'
  WHEN lead_time_hours <= 120 THEN 'five-day-special-order'
  ELSE 'seven-day-warehouse-transfer'
END;

DROP VIEW IF EXISTS inventory;
DROP FUNCTION IF EXISTS search_inventory_for_call(UUID, TEXT, INT, TEXT, TEXT, TEXT);
DROP VIEW IF EXISTS v_inventory_search;

CREATE OR REPLACE VIEW v_inventory_search AS
SELECT
  ii.id AS inventory_item_id,
  ii.shop_id,
  sl.city AS location_city,
  sl.state_region AS location_state,
  sl.country AS location_country,
  s.name AS supplier_name,
  s.default_lead_time_hours AS supplier_default_lead_time_hours,
  pc.name AS category_name,
  pt.name AS part_type_name,
  pt.normalized_name AS part_type_normalized,
  b.name AS brand_name,
  b.tier AS brand_tier,
  pp.product_grade,
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
  ii.lead_time_hours,
  ((ii.lead_time_hours + 23) / 24) AS lead_time_days,
  CASE
    WHEN ii.lead_time_hours = 0 THEN 'same day in ' || COALESCE(sl.city, 'store')
    WHEN ii.lead_time_hours <= 24 THEN '1 day'
    ELSE ((ii.lead_time_hours + 23) / 24)::text || ' days'
  END AS fulfillment_eta,
  ii.service_level
FROM inventory_items ii
JOIN part_products pp ON pp.id = ii.part_product_id
JOIN part_types pt ON pt.id = pp.part_type_id
LEFT JOIN part_categories pc ON pc.id = pt.category_id
LEFT JOIN brands b ON b.id = pp.brand_id
LEFT JOIN suppliers s ON s.id = ii.supplier_id
LEFT JOIN shop_locations sl ON sl.id = ii.location_id;

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
  brand_tier brand_tier,
  product_grade TEXT,
  manufacturer_part_number TEXT,
  quality part_quality,
  price NUMERIC,
  warranty_days INT,
  lead_time_hours INT,
  lead_time_days INT,
  fulfillment_eta TEXT,
  service_level TEXT,
  quantity_available INT,
  supplier_name TEXT,
  location_city TEXT,
  location_state TEXT
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    vis.inventory_item_id,
    vis.title,
    vis.part_type_name,
    vis.brand_name,
    vis.brand_tier,
    vis.product_grade,
    vis.manufacturer_part_number,
    vis.quality,
    vis.price,
    vis.warranty_days,
    vis.lead_time_hours,
    vis.lead_time_days,
    vis.fulfillment_eta,
    vis.service_level,
    (vis.quantity_available - vis.quantity_reserved) AS quantity_available,
    vis.supplier_name,
    vis.location_city,
    vis.location_state
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
    AND (p_city IS NULL OR lower(vis.location_city) = lower(p_city) OR vis.lead_time_hours <= 168)
    AND (p_year IS NULL OR pf.id IS NULL OR p_year BETWEEN pf.year_start AND pf.year_end)
    AND (p_make IS NULL OR pf.id IS NULL OR lower(pf.make) = lower(p_make))
    AND (p_model IS NULL OR pf.id IS NULL OR lower(pf.model) = lower(p_model))
  ORDER BY
    CASE vis.brand_tier
      WHEN 'economy' THEN 1
      WHEN 'mid' THEN 2
      WHEN 'premium' THEN 3
      WHEN 'oem' THEN 4
      WHEN 'performance' THEN 5
      WHEN 'salvage' THEN 6
      ELSE 7
    END,
    vis.lead_time_hours ASC,
    vis.price ASC
  LIMIT 8;
END;
$$ LANGUAGE plpgsql;

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
  b.tier AS brand_tier,
  pp.product_grade,
  pp.manufacturer_part_number AS part_number,
  pf.year_start,
  pf.year_end,
  lower(pf.make) AS make,
  lower(pf.model) AS model,
  CONCAT(pf.year_start, '-', pf.year_end, ' ', pf.make, ' ', pf.model) AS fitment_text,
  (ii.quantity_available - ii.quantity_reserved) AS qty,
  ii.price,
  ii.lead_time_hours,
  ((ii.lead_time_hours + 23) / 24) AS lead_time_days,
  CASE
    WHEN ii.lead_time_hours = 0 THEN 'same day in ' || COALESCE(sl.city, 'store')
    WHEN ii.lead_time_hours <= 24 THEN '1 day'
    ELSE ((ii.lead_time_hours + 23) / 24)::text || ' days'
  END AS fulfillment_eta,
  ii.service_level,
  sl.city AS location_city,
  sl.state_region AS location_state,
  sl.country AS location_country,
  ii.shelf_location AS shelf
FROM inventory_items ii
JOIN part_products pp ON pp.id = ii.part_product_id
JOIN part_types pt ON pt.id = pp.part_type_id
LEFT JOIN part_categories pc ON pc.id = pt.category_id
LEFT JOIN brands b ON b.id = pp.brand_id
LEFT JOIN part_fitments pf ON pf.part_product_id = pp.id
LEFT JOIN shop_locations sl ON sl.id = ii.location_id
WHERE ii.status = 'available';

CREATE TABLE IF NOT EXISTS caller_memory_profiles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  shop_id UUID NOT NULL REFERENCES shops(id) ON DELETE CASCADE,
  customer_id UUID REFERENCES customers(id) ON DELETE SET NULL,
  caller_phone TEXT NOT NULL,
  display_name TEXT,
  preferred_name TEXT,
  memory_summary TEXT NOT NULL DEFAULT '',
  preferred_contact_method TEXT NOT NULL DEFAULT 'sms',
  last_seen_at TIMESTAMPTZ,
  call_count INT NOT NULL DEFAULT 0,
  total_estimated_value NUMERIC(10,2) NOT NULL DEFAULT 0,
  metadata JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE(shop_id, caller_phone)
);

DROP TRIGGER IF EXISTS trg_caller_memory_profiles_updated_at ON caller_memory_profiles;
CREATE TRIGGER trg_caller_memory_profiles_updated_at
BEFORE UPDATE ON caller_memory_profiles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TABLE IF NOT EXISTS caller_memory_vehicles (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_profile_id UUID NOT NULL REFERENCES caller_memory_profiles(id) ON DELETE CASCADE,
  customer_vehicle_id UUID REFERENCES customer_vehicles(id) ON DELETE SET NULL,
  vin TEXT,
  year INT,
  make TEXT,
  model TEXT,
  trim TEXT,
  engine TEXT,
  nickname TEXT,
  last_discussed_at TIMESTAMPTZ,
  last_ordered_part TEXT,
  notes TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

DROP TRIGGER IF EXISTS trg_caller_memory_vehicles_updated_at ON caller_memory_vehicles;
CREATE TRIGGER trg_caller_memory_vehicles_updated_at
BEFORE UPDATE ON caller_memory_vehicles
FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE UNIQUE INDEX IF NOT EXISTS idx_caller_memory_vehicles_unique_vehicle
ON caller_memory_vehicles (
  memory_profile_id,
  COALESCE(vin, ''),
  COALESCE(year, 0),
  COALESCE(lower(make), ''),
  COALESCE(lower(model), ''),
  COALESCE(lower(trim), '')
);

CREATE TABLE IF NOT EXISTS caller_memory_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  memory_profile_id UUID NOT NULL REFERENCES caller_memory_profiles(id) ON DELETE CASCADE,
  call_id UUID REFERENCES calls(id) ON DELETE SET NULL,
  event_type TEXT NOT NULL DEFAULT 'call',
  part_requested TEXT,
  vehicle_text TEXT,
  outcome TEXT,
  quoted_amount NUMERIC(10,2) NOT NULL DEFAULT 0,
  notes TEXT,
  occurred_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  raw_payload JSONB NOT NULL DEFAULT '{}'::jsonb,
  created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_caller_memory_profiles_phone ON caller_memory_profiles(shop_id, caller_phone);
CREATE INDEX IF NOT EXISTS idx_caller_memory_events_profile_time ON caller_memory_events(memory_profile_id, occurred_at DESC);

WITH customer_source AS (
  SELECT
    c.shop_id,
    c.id AS customer_id,
    c.phone AS caller_phone,
    c.name AS display_name,
    split_part(COALESCE(c.name, ''), ' ', 1) AS preferred_name,
    c.preferred_contact_method
  FROM customers c
),
call_source AS (
  SELECT DISTINCT
    c.shop_id,
    c.customer_id,
    c.from_phone AS caller_phone,
    NULL::text AS display_name,
    NULL::text AS preferred_name,
    'sms'::text AS preferred_contact_method
  FROM calls c
  WHERE c.from_phone IS NOT NULL
),
merged AS (
  SELECT * FROM customer_source
  UNION ALL
  SELECT * FROM call_source
)
INSERT INTO caller_memory_profiles (
  shop_id, customer_id, caller_phone, display_name, preferred_name, preferred_contact_method
)
SELECT
  m.shop_id,
  (array_agg(m.customer_id) FILTER (WHERE m.customer_id IS NOT NULL))[1] AS customer_id,
  m.caller_phone,
  max(m.display_name) AS display_name,
  NULLIF(max(m.preferred_name), '') AS preferred_name,
  COALESCE(max(m.preferred_contact_method), 'sms') AS preferred_contact_method
FROM merged m
WHERE m.caller_phone IS NOT NULL
GROUP BY m.shop_id, m.caller_phone
ON CONFLICT (shop_id, caller_phone) DO UPDATE
SET customer_id = COALESCE(caller_memory_profiles.customer_id, EXCLUDED.customer_id),
    display_name = COALESCE(caller_memory_profiles.display_name, EXCLUDED.display_name),
    preferred_name = COALESCE(caller_memory_profiles.preferred_name, EXCLUDED.preferred_name),
    preferred_contact_method = EXCLUDED.preferred_contact_method,
    updated_at = now();

WITH stats AS (
  SELECT
    cmp.id,
    count(c.id)::int AS call_count,
    max(c.started_at) AS last_seen_at,
    COALESCE(sum(c.estimated_revenue), 0) AS total_estimated_value,
    string_agg(DISTINCT NULLIF(c.vehicle_text, ''), ', ') FILTER (WHERE c.vehicle_text IS NOT NULL) AS vehicles,
    string_agg(DISTINCT NULLIF(c.requested_part_text, ''), ', ') FILTER (WHERE c.requested_part_text IS NOT NULL) AS parts
  FROM caller_memory_profiles cmp
  LEFT JOIN calls c ON c.shop_id = cmp.shop_id AND c.from_phone = cmp.caller_phone
  GROUP BY cmp.id
)
UPDATE caller_memory_profiles cmp
SET call_count = stats.call_count,
    last_seen_at = stats.last_seen_at,
    total_estimated_value = stats.total_estimated_value,
    memory_summary = trim(both ' ' FROM concat_ws(
      ' ',
      CASE WHEN cmp.display_name IS NOT NULL THEN 'Caller is ' || cmp.display_name || '.' ELSE 'Caller phone ' || cmp.caller_phone || '.' END,
      CASE WHEN stats.vehicles IS NOT NULL THEN 'Known vehicles: ' || stats.vehicles || '.' ELSE NULL END,
      CASE WHEN stats.parts IS NOT NULL THEN 'Asked about: ' || stats.parts || '.' ELSE NULL END
    )),
    updated_at = now()
FROM stats
WHERE stats.id = cmp.id;

INSERT INTO caller_memory_vehicles (
  memory_profile_id, customer_vehicle_id, vin, year, make, model, trim, engine,
  nickname, last_discussed_at, last_ordered_part, notes
)
SELECT
  cmp.id,
  cv.id,
  cv.vin,
  cv.year,
  cv.make,
  cv.model,
  cv.trim,
  cv.engine,
  concat_ws(' ', cv.year::text, cv.make, cv.model),
  (
    SELECT max(c.started_at)
    FROM calls c
    WHERE c.shop_id = cmp.shop_id
      AND c.from_phone = cmp.caller_phone
      AND c.vehicle_text ILIKE '%' || cv.model || '%'
  ) AS last_discussed_at,
  (
    SELECT c.requested_part_text
    FROM calls c
    WHERE c.shop_id = cmp.shop_id
      AND c.from_phone = cmp.caller_phone
      AND c.vehicle_text ILIKE '%' || cv.model || '%'
      AND c.requested_part_text IS NOT NULL
    ORDER BY c.started_at DESC
    LIMIT 1
  ) AS last_ordered_part,
  cv.notes
FROM caller_memory_profiles cmp
JOIN customer_vehicles cv ON cv.customer_id = cmp.customer_id
ON CONFLICT DO NOTHING;

INSERT INTO caller_memory_events (
  memory_profile_id, call_id, event_type, part_requested, vehicle_text, outcome,
  quoted_amount, notes, occurred_at, raw_payload
)
SELECT
  cmp.id,
  c.id,
  COALESCE(c.intent, 'call'),
  c.requested_part_text,
  c.vehicle_text,
  c.outcome,
  c.estimated_revenue,
  c.summary,
  c.started_at,
  c.raw_payload
FROM caller_memory_profiles cmp
JOIN calls c ON c.shop_id = cmp.shop_id AND c.from_phone = cmp.caller_phone
WHERE NOT EXISTS (
  SELECT 1 FROM caller_memory_events cme
  WHERE cme.memory_profile_id = cmp.id
    AND cme.call_id = c.id
);

CREATE OR REPLACE VIEW v_caller_memory_context AS
SELECT
  cmp.id AS memory_profile_id,
  cmp.shop_id,
  cmp.customer_id,
  cmp.caller_phone,
  cmp.display_name,
  cmp.preferred_name,
  cmp.memory_summary,
  cmp.preferred_contact_method,
  cmp.last_seen_at,
  cmp.call_count,
  cmp.total_estimated_value,
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'year', cmv.year,
        'make', cmv.make,
        'model', cmv.model,
        'trim', cmv.trim,
        'engine', cmv.engine,
        'nickname', cmv.nickname,
        'last_discussed_at', cmv.last_discussed_at,
        'last_ordered_part', cmv.last_ordered_part,
        'notes', cmv.notes
      )
      ORDER BY cmv.last_discussed_at DESC NULLS LAST, cmv.created_at DESC
    )
    FROM caller_memory_vehicles cmv
    WHERE cmv.memory_profile_id = cmp.id
  ), '[]'::jsonb) AS known_vehicles,
  COALESCE((
    SELECT jsonb_agg(
      jsonb_build_object(
        'event_type', cme.event_type,
        'part_requested', cme.part_requested,
        'vehicle_text', cme.vehicle_text,
        'outcome', cme.outcome,
        'quoted_amount', cme.quoted_amount,
        'notes', cme.notes,
        'occurred_at', cme.occurred_at
      )
      ORDER BY cme.occurred_at DESC
    )
    FROM (
      SELECT *
      FROM caller_memory_events
      WHERE memory_profile_id = cmp.id
      ORDER BY occurred_at DESC
      LIMIT 8
    ) cme
  ), '[]'::jsonb) AS recent_events
FROM caller_memory_profiles cmp;

CREATE OR REPLACE FUNCTION get_caller_memory_for_call(
  p_shop_id UUID,
  p_caller_phone TEXT
)
RETURNS TABLE (
  memory_profile_id UUID,
  caller_phone TEXT,
  display_name TEXT,
  preferred_name TEXT,
  memory_summary TEXT,
  known_vehicles JSONB,
  recent_events JSONB,
  call_count INT,
  last_seen_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    v.memory_profile_id,
    v.caller_phone,
    v.display_name,
    v.preferred_name,
    v.memory_summary,
    v.known_vehicles,
    v.recent_events,
    v.call_count,
    v.last_seen_at
  FROM v_caller_memory_context v
  WHERE v.shop_id = p_shop_id
    AND v.caller_phone = p_caller_phone
  LIMIT 1;
END;
$$ LANGUAGE plpgsql;

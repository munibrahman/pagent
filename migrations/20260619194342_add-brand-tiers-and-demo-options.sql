-- Add explicit brand/product tiers and seed tiered demo options for common voice-agent parts.

DO $$ BEGIN
  CREATE TYPE brand_tier AS ENUM ('economy', 'mid', 'premium', 'oem', 'performance', 'salvage');
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

ALTER TABLE brands
  ADD COLUMN IF NOT EXISTS tier brand_tier NOT NULL DEFAULT 'mid';

ALTER TABLE part_products
  ADD COLUMN IF NOT EXISTS product_grade TEXT NOT NULL DEFAULT 'standard';

ALTER TABLE inventory_items
  ADD COLUMN IF NOT EXISTS service_level TEXT NOT NULL DEFAULT 'standard';

CREATE INDEX IF NOT EXISTS idx_brands_tier ON brands(tier);
CREATE INDEX IF NOT EXISTS idx_part_products_grade ON part_products(product_grade);
CREATE INDEX IF NOT EXISTS idx_inventory_lead_time ON inventory_items(lead_time_hours);

UPDATE brands
SET tier = CASE
  WHEN name IN ('BudgetLine', 'FRAM', 'TYC', 'Dorman', 'Mann-Filter', 'EconoDrive', 'SureStop') THEN 'economy'::brand_tier
  WHEN name IN ('Wagner', 'Bosch', 'Raybestos', 'Gates', 'NGK', 'Monroe', 'Delphi', 'KYB', 'Valeo') THEN 'mid'::brand_tier
  WHEN name IN ('Akebono', 'MOOG', 'Timken', 'Denso') THEN 'premium'::brand_tier
  WHEN name IN ('ACDelco', 'Motorcraft', 'DemoOEM') THEN 'oem'::brand_tier
  WHEN name IN ('PowerStop') THEN 'performance'::brand_tier
  WHEN name IN ('SalvageGrade') THEN 'salvage'::brand_tier
  ELSE tier
END;

UPDATE part_products pp
SET product_grade = CASE
  WHEN b.tier = 'economy' THEN 'economy'
  WHEN b.tier = 'mid' THEN 'mid-grade'
  WHEN b.tier = 'premium' THEN 'premium'
  WHEN b.tier = 'oem' THEN 'oem'
  WHEN b.tier = 'performance' THEN 'performance'
  WHEN b.tier = 'salvage' THEN 'used'
  ELSE product_grade
END
FROM brands b
WHERE b.id = pp.brand_id;

UPDATE inventory_items ii
SET service_level = CASE
  WHEN ii.lead_time_hours = 0 THEN 'local-same-day'
  WHEN ii.lead_time_hours <= 12 THEN 'regional-same-day'
  WHEN ii.lead_time_hours <= 24 THEN 'next-day'
  ELSE 'warehouse-transfer'
END;

INSERT INTO brands (name, brand_type, tier, website_url) VALUES
  ('EconoDrive', 'aftermarket', 'economy', 'https://example.com/econodrive'),
  ('SureStop', 'aftermarket', 'economy', 'https://example.com/surestop'),
  ('Centric', 'aftermarket', 'mid', 'https://www.centricparts.com'),
  ('Brembo', 'performance', 'premium', 'https://www.brembo.com')
ON CONFLICT (name) DO UPDATE
SET tier = EXCLUDED.tier,
    brand_type = EXCLUDED.brand_type,
    website_url = COALESCE(brands.website_url, EXCLUDED.website_url);

-- Tiered part options: same fitments, different brand tier, price, quantity, and lead time.
WITH pt AS (SELECT id, normalized_name FROM part_types),
     b AS (SELECT id, name FROM brands)
INSERT INTO part_products (
  part_type_id, brand_id, manufacturer_part_number, sku, title, quality, condition_grade,
  product_grade, warranty_days, core_charge, msrp, interchange_part_numbers
)
SELECT pt.id, b.id, x.mpn, x.sku, x.title, x.quality::part_quality, 'New',
       x.product_grade, x.warranty_days, x.core_charge, x.msrp, x.interchange_part_numbers::text[]
FROM pt
JOIN (VALUES
  ('front_brake_pads', 'EconoDrive', 'ED1210', 'SKU-BRK-TYT-CAM-12-17-ECO-F', 'EconoDrive Economy Front Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 'economy', 90, 0, 34.99, ARRAY['ZD1210', 'ACT1210']),
  ('front_brake_pads', 'Akebono', 'ACT1210', 'SKU-BRK-TYT-CAM-12-17-AKE-F', 'Akebono Premium Ceramic Front Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 'premium', 365, 0, 84.99, ARRAY['ZD1210', 'ED1210']),
  ('front_brake_pads', 'DemoOEM', 'OE-TYT-CAM-1210', 'SKU-BRK-TYT-CAM-12-17-OEM-F', 'OEM Front Brake Pads - 2012-2017 Toyota Camry', 'oem', 'oem', 365, 0, 109.99, ARRAY['ZD1210', 'ACT1210']),
  ('rear_brake_pads', 'EconoDrive', 'ED1212', 'SKU-BRK-TYT-CAM-12-17-ECO-R', 'EconoDrive Economy Rear Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 'economy', 90, 0, 31.99, ARRAY['ZD1212']),
  ('rear_brake_pads', 'Akebono', 'ACT1212', 'SKU-BRK-TYT-CAM-12-17-AKE-R', 'Akebono Premium Ceramic Rear Brake Pads - 2012-2017 Toyota Camry', 'aftermarket', 'premium', 365, 0, 79.99, ARRAY['ZD1212']),
  ('brake_rotor', 'SureStop', 'SSR980418', 'SKU-ROT-TYT-CAM-12-17-ECO', 'SureStop Economy Front Brake Rotor - Toyota Camry', 'aftermarket', 'economy', 90, 0, 54.99, ARRAY['980418R']),
  ('brake_rotor', 'Brembo', 'BREM-980418', 'SKU-ROT-TYT-CAM-12-17-BREM', 'Brembo Premium Front Brake Rotor - Toyota Camry', 'performance', 'premium', 365, 0, 129.99, ARRAY['980418R']),
  ('oil_filter', 'EconoDrive', 'ED4386', 'SKU-FLT-TYT-CAM-ECO-OIL', 'EconoDrive Economy Oil Filter - Toyota 2.5L', 'aftermarket', 'economy', 90, 0, 7.99, ARRAY['PH4386']),
  ('oil_filter', 'Bosch', 'D3330', 'SKU-FLT-TYT-CAM-BOS-PREM-OIL', 'Bosch Premium Oil Filter - Toyota 2.5L', 'aftermarket', 'premium', 180, 0, 16.99, ARRAY['PH4386']),
  ('air_filter', 'EconoDrive', 'EDA5632', 'SKU-FLT-TYT-CAM-ECO-AIR', 'EconoDrive Economy Engine Air Filter - Toyota Camry', 'aftermarket', 'economy', 90, 0, 12.99, ARRAY['AF5632']),
  ('spark_plug_set', 'EconoDrive', 'ED-SP-4PK', 'SKU-IGN-TYT-CAM-ECO-PLUG', 'EconoDrive Copper Spark Plug Set - Toyota 2.5L', 'aftermarket', 'economy', 90, 0, 24.99, ARRAY['LFR5AIX11-4']),
  ('spark_plug_set', 'Denso', 'SK16HR11-4', 'SKU-IGN-TYT-CAM-DEN-PREM-PLUG', 'Denso Iridium Spark Plug Set - Toyota 2.5L', 'oem', 'premium', 365, 0, 63.99, ARRAY['LFR5AIX11-4']),
  ('front_brake_pads', 'EconoDrive', 'ED914', 'SKU-BRK-HON-CIV-16-21-ECO-F', 'EconoDrive Economy Front Brake Pads - Honda Civic', 'aftermarket', 'economy', 90, 0, 36.99, ARRAY['BC914']),
  ('front_brake_pads', 'Akebono', 'ACT914', 'SKU-BRK-HON-CIV-16-21-AKE-F', 'Akebono Premium Ceramic Front Brake Pads - Honda Civic', 'aftermarket', 'premium', 365, 0, 76.99, ARRAY['BC914']),
  ('front_brake_pads', 'SureStop', 'SSR1367', 'SKU-BRK-CHE-SIL-ECO-F', 'SureStop Economy Front Brake Pads - Silverado 1500', 'aftermarket', 'economy', 90, 0, 44.99, ARRAY['17D1367CH']),
  ('front_brake_pads', 'Brembo', 'BREM1367', 'SKU-BRK-CHE-SIL-BREM-F', 'Brembo Premium Front Brake Pads - Silverado 1500', 'performance', 'premium', 365, 0, 99.99, ARRAY['17D1367CH']),
  ('battery', 'EconoDrive', 'ED-48FLOODED', 'SKU-BAT-UNV-ECO-48', 'EconoDrive Flooded Battery Group 48', 'aftermarket', 'economy', 180, 18, 149.99, ARRAY['48AGM']),
  ('battery', 'DemoOEM', 'OE-48AGM', 'SKU-BAT-UNV-OEM-48AGM', 'OEM AGM Battery Group 48', 'oem', 'oem', 365, 18, 249.99, ARRAY['48AGM'])
) AS x(part_norm, brand_name, mpn, sku, title, quality, product_grade, warranty_days, core_charge, msrp, interchange_part_numbers)
ON pt.normalized_name = x.part_norm
JOIN b ON b.name = x.brand_name
ON CONFLICT DO NOTHING;

INSERT INTO part_fitments (part_product_id, year_start, year_end, make, model, trim, engine, qualifiers)
SELECT pp.id, x.year_start, x.year_end, x.make, x.model, NULL, x.engine, x.qualifiers
FROM part_products pp
JOIN (VALUES
  ('ED1210', 2012, 2017, 'Toyota', 'Camry', NULL, 'front axle economy option'),
  ('ACT1210', 2012, 2017, 'Toyota', 'Camry', NULL, 'front axle premium ceramic option'),
  ('OE-TYT-CAM-1210', 2012, 2017, 'Toyota', 'Camry', NULL, 'front axle OEM option'),
  ('ED1212', 2012, 2017, 'Toyota', 'Camry', NULL, 'rear axle economy option'),
  ('ACT1212', 2012, 2017, 'Toyota', 'Camry', NULL, 'rear axle premium ceramic option'),
  ('SSR980418', 2012, 2017, 'Toyota', 'Camry', NULL, 'front rotor economy option'),
  ('BREM-980418', 2012, 2017, 'Toyota', 'Camry', NULL, 'front rotor premium option'),
  ('ED4386', 2010, 2017, 'Toyota', 'Camry', '2.5L', 'economy oil filter'),
  ('D3330', 2010, 2017, 'Toyota', 'Camry', '2.5L', 'premium oil filter'),
  ('EDA5632', 2012, 2017, 'Toyota', 'Camry', NULL, 'economy engine air filter'),
  ('ED-SP-4PK', 2012, 2017, 'Toyota', 'Camry', '2.5L', 'economy copper plugs'),
  ('SK16HR11-4', 2012, 2017, 'Toyota', 'Camry', '2.5L', 'premium iridium plugs'),
  ('ED914', 2016, 2021, 'Honda', 'Civic', NULL, 'front axle economy option'),
  ('ACT914', 2016, 2021, 'Honda', 'Civic', NULL, 'front axle premium ceramic option'),
  ('SSR1367', 2014, 2020, 'Chevrolet', 'Silverado 1500', NULL, 'front axle economy option'),
  ('BREM1367', 2014, 2020, 'Chevrolet', 'Silverado 1500', NULL, 'front axle premium option'),
  ('ED-48FLOODED', 2010, 2024, 'Toyota', 'Camry', NULL, 'group 48 economy battery'),
  ('ED-48FLOODED', 2015, 2024, 'Ford', 'F-150', NULL, 'group 48 economy battery'),
  ('OE-48AGM', 2010, 2024, 'Toyota', 'Camry', NULL, 'group 48 OEM battery'),
  ('OE-48AGM', 2015, 2024, 'Ford', 'F-150', NULL, 'group 48 OEM battery')
) AS x(mpn, year_start, year_end, make, model, engine, qualifiers)
ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

WITH shop AS (SELECT id FROM shops WHERE slug='partpilot-demo'),
     loc AS (SELECT id, city FROM shop_locations WHERE shop_id = (SELECT id FROM shop)),
     sup AS (SELECT id, name FROM suppliers WHERE shop_id = (SELECT id FROM shop)),
     pp AS (SELECT id, manufacturer_part_number FROM part_products)
INSERT INTO inventory_items (
  shop_id, location_id, supplier_id, part_product_id, quantity_available, price, cost,
  status, lead_time_hours, service_level, shelf_location, notes, last_synced_at
)
SELECT shop.id, loc.id, sup.id, pp.id, x.qty, x.price, x.cost, 'available',
       x.lead_time_hours, x.service_level, x.shelf, x.notes, now() - x.synced_ago::interval
FROM shop
CROSS JOIN (VALUES
  ('San Francisco', 'Budget Auto Parts', 'ED1210', 12, 29.99, 13.00, 0, 'local-same-day', 'B10', 'economy Camry front pad option', '3 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ACT1210', 4, 68.99, 39.00, 12, 'regional-same-day', 'B14', 'premium ceramic Camry front pad option', '3 minutes'),
  ('San Francisco', 'OEM Direct Dealer', 'OE-TYT-CAM-1210', 2, 94.99, 61.00, 24, 'next-day-oem', 'DROPSHIP', 'OEM Camry front pad option', '18 minutes'),
  ('Calgary', 'Budget Auto Parts', 'ED1212', 8, 27.99, 12.00, 0, 'local-same-day', 'B11', 'economy Camry rear pad option', '9 minutes'),
  ('Toronto', 'Premium Reman Supply', 'ACT1212', 3, 64.99, 38.00, 36, 'warehouse-transfer', 'B44', 'premium rear pad option', '22 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'SSR980418', 6, 44.99, 23.00, 0, 'local-same-day', 'R1-10', 'economy Camry rotor option', '3 minutes'),
  ('Toronto', 'Premium Reman Supply', 'BREM-980418', 2, 109.99, 66.00, 36, 'warehouse-transfer', 'R9-03', 'premium rotor option', '22 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ED4386', 30, 5.99, 1.95, 0, 'local-same-day', 'F1-00', 'economy oil filter option', '3 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'D3330', 10, 13.99, 6.25, 0, 'local-same-day', 'F1-02', 'premium oil filter option', '3 minutes'),
  ('Calgary', 'Budget Auto Parts', 'EDA5632', 15, 10.99, 5.00, 0, 'local-same-day', 'F2-01', 'economy air filter option', '9 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ED-SP-4PK', 8, 19.99, 8.00, 0, 'local-same-day', 'I1-01', 'economy spark plug set', '3 minutes'),
  ('Toronto', 'Premium Reman Supply', 'SK16HR11-4', 4, 54.99, 31.00, 36, 'warehouse-transfer', 'I9-03', 'premium iridium spark plug set', '22 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ED914', 10, 31.99, 14.00, 0, 'local-same-day', 'B16', 'economy Civic front pads', '3 minutes'),
  ('Toronto', 'Premium Reman Supply', 'ACT914', 3, 63.99, 36.00, 36, 'warehouse-transfer', 'B45', 'premium Civic front pads', '22 minutes'),
  ('Calgary', 'Budget Auto Parts', 'SSR1367', 7, 39.99, 18.00, 0, 'local-same-day', 'B35', 'economy Silverado front pads', '9 minutes'),
  ('San Francisco', 'OEM Direct Dealer', 'BREM1367', 2, 84.99, 49.00, 24, 'next-day-premium', 'DROPSHIP', 'premium Silverado front pads', '18 minutes'),
  ('San Francisco', 'Budget Auto Parts', 'ED-48FLOODED', 6, 119.99, 77.00, 0, 'local-same-day', 'BAT-1', 'economy battery group 48', '3 minutes'),
  ('San Francisco', 'OEM Direct Dealer', 'OE-48AGM', 2, 229.99, 158.00, 24, 'next-day-oem', 'BAT-OEM', 'OEM battery group 48', '18 minutes')
) AS x(city, supplier, mpn, qty, price, cost, lead_time_hours, service_level, shelf, notes, synced_ago)
JOIN loc ON loc.city = x.city
JOIN sup ON sup.name = x.supplier
JOIN pp ON pp.manufacturer_part_number = x.mpn
ON CONFLICT DO NOTHING;

DROP VIEW IF EXISTS inventory;
DROP FUNCTION IF EXISTS search_inventory_for_call(UUID, TEXT, INT, TEXT, TEXT, TEXT);
DROP VIEW IF EXISTS v_inventory_search;

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
  service_level TEXT,
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
    vis.brand_tier,
    vis.product_grade,
    vis.manufacturer_part_number,
    vis.quality,
    vis.price,
    vis.warranty_days,
    vis.lead_time_hours,
    vis.service_level,
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
  ii.service_level,
  ii.shelf_location AS shelf
FROM inventory_items ii
JOIN part_products pp ON pp.id = ii.part_product_id
JOIN part_types pt ON pt.id = pp.part_type_id
LEFT JOIN part_categories pc ON pc.id = pt.category_id
LEFT JOIN brands b ON b.id = pp.brand_id
LEFT JOIN part_fitments pf ON pf.part_product_id = pp.id
WHERE ii.status = 'available';

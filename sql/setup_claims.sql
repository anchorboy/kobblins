-- SQL: setup_claims.sql
-- Run this in Supabase SQL editor. Adjust table name if different.

-- 1) Add discovery columns if they don't exist (your CSV already had DISCOVERED etc; skip if present)
ALTER TABLE "Kobblins Database"
  ADD COLUMN IF NOT EXISTS discovered boolean DEFAULT false,
  ADD COLUMN IF NOT EXISTS discovered_date timestamptz NULL,
  ADD COLUMN IF NOT EXISTS finder text NULL;

-- 2) Create a discoveries table to record each claim (optional but useful)
CREATE TABLE IF NOT EXISTS discoveries (
  id uuid DEFAULT gen_random_uuid() PRIMARY KEY,
  kobblin_id text,
  found_at timestamptz DEFAULT now(),
  finder text,
  method text,
  secret_used text
);

-- 3) Create an atomic RPC that claims a kobblin by secret and returns the public data
--    It clears the "SECRET ID" so the secret cannot be reused.
CREATE OR REPLACE FUNCTION public.claim_kobblin(in_secret text, in_finder text)
RETURNS TABLE(
  id text,
  name text,
  collection text,
  o_num text,
  discovered boolean,
  discovered_date timestamptz,
  image text,
  thumbnail text
) AS $$
BEGIN
  RETURN QUERY
  WITH upd AS (
    UPDATE "Kobblins Database"
    SET discovered = true,
        discovered_date = now(),
        finder = NULLIF(in_finder, ''),
        "SECRET ID" = NULL
    WHERE "SECRET ID" = in_secret
      AND (discovered IS DISTINCT FROM true)
    RETURNING *
  ), ins AS (
    INSERT INTO discoveries (kobblin_id, finder, method, secret_used)
    SELECT "ID", NULLIF(in_finder, ''), 'qr-claim', in_secret FROM upd
    RETURNING kobblin_id
  )
  SELECT 
    upd."ID"::text AS id,
    upd."NAME"::text AS name,
    upd."COLLECTION"::text AS collection,
    COALESCE(upd."O NUM.", upd."C NUM")::text AS o_num,
    upd.discovered,
    upd.discovered_date,
    COALESCE(upd.image, 'images/' || lower(regexp_replace(upd."NAME", '[^a-z0-9]+','-','g')) || '.png')::text AS image,
    COALESCE(upd.thumbnail, 'images/thumbs/' || lower(regexp_replace(upd."NAME", '[^a-z0-9]+','-','g')) || '.png')::text AS thumbnail
  FROM upd;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Note: SECURITY DEFINER allows the RPC to be called by the Edge Function (or anon role) while running with the function owner privileges.
-- Make sure to review RLS policies for your project. The Edge Function will call this RPC using the service_role key.

-- @tag: trigram_indices_webshop
-- @description: Trigram Indizes für Fuzzysearch bei der Kundensuche im Shopmodul
-- @depends: release_3_5_0 shops
-- @encoding: utf-8
-- @ignore: 1

CREATE INDEX customer_street_gin_trgm_idx            ON customer        USING gin (street                  gin_trgm_ops);
-- @tag: create_part_if_notfound
-- @description: Falls Artikel nicht gefunden wird gleich in die Erfassung gehen
-- @depends: release_3_2_0
ALTER TABLE defaults ADD COLUMN create_part_if_notfound BOOLEAN DEFAULT FALSE;
UPDATE defaults SET create_part_if_notfound = TRUE;

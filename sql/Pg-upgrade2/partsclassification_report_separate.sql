-- @tag: partsclassification_report_separate
-- @description: "Artikelklassifikation mit weiterer boolschen Variable für separat ausweisen"
-- @depends: parts_classifications
ALTER TABLE parts_classifications ADD COLUMN report_separate BOOLEAN DEFAULT 'f' NOT NULL;

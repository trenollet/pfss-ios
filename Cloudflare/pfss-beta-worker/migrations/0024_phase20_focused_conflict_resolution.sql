-- Phase 20 Step 6: version every human conflict decision.

ALTER TABLE synchronization_conflicts
    ADD COLUMN policy_version INTEGER NOT NULL DEFAULT 1;

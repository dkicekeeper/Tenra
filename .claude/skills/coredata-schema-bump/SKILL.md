---
name: coredata-schema-bump
description: Bump the Tenra.xcdatamodeld CoreData schema version (new entity or attribute) — version-copy checklist, lightweight-migration rules, repository wiring. Use when adding or changing CoreData entities/attributes.
---

# CoreData Schema Bump Checklist

`Tenra.xcdatamodeld` is currently at v12 (v12 added `AccountEntity.includeInBalance` — accounts excluded from the Finances total + insights aggregates; v11 added `CategorySubcategoryLinkEntity.sortOrder`; v10 added `CategoryAggregateEntity.expenseAmount`). Bump checklist when adding an entity (additive — lightweight migration auto-handles):

1. `cp -r Tenra/CoreData/Tenra.xcdatamodeld/Tenra\ vN.xcdatamodel Tenra/CoreData/Tenra.xcdatamodeld/Tenra\ vN+1.xcdatamodel`, edit `contents` XML.
2. Update `Tenra/CoreData/Tenra.xcdatamodeld/.xccurrentversion` plist to point to vN+1.
3. Create `Tenra/CoreData/Entities/<Entity>+CoreDataClass.swift` + `<Entity>+CoreDataProperties.swift` (mirror `AccountAggregateEntity` for aggregate-style entities).
4. Add load/save to the matching `Services/Repository/<Domain>Repository.swift`, then forward in `CoreDataRepository.swift`, then add no-op stubs in `UserDefaultsRepository.swift` and any test mocks.
5. No backup-version constant to bump — `CloudBackupService.currentModelVersion` derives from the compiled model.

Lightweight migration only works for ADDITIVE changes (new entity, new optional attribute). Removing/renaming requires a mapping model — none in this project yet.

Reminder: the Xcode project uses file-system-synchronized groups, so the new `.swift` entity files need no `project.pbxproj` edits — creating them on disk is enough (see CLAUDE.md).

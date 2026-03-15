// Purpose: Documentation for the V1-to-V2 schema migration.
//
// SchemaV2 adds `anchorData: Data?` to the Highlight model.
// Stored as raw Data? (JSON bytes) rather than Codable AnnotationAnchor? to
// avoid SwiftData macro-generated accessor crashes on legacy rows that lack
// the column. The Highlight computed `anchor` property decodes with try?,
// returning nil on failure.
//
// Since the new field is optional with a nil default, SwiftData handles this
// as an automatic lightweight migration — no explicit MigrationStage is needed.
//
// Both SchemaV1 and SchemaV2 reference the same live model types. SwiftData
// infers the column addition by comparing the schema version identifiers.
//
// If future migrations require data transforms (willMigrate/didMigrate),
// define explicit MigrationStage instances here and register them in
// VReaderMigrationPlan.stages.
//
// @coordinates-with: SchemaV1.swift, SchemaV2.swift, Highlight.swift

import Foundation
import SwiftData

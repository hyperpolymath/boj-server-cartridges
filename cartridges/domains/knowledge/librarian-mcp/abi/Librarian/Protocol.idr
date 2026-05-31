-- SPDX-License-Identifier: MPL-2.0
||| Protocol: librarian-mcp tool operations and safety proofs.
|||
||| Defines the formal interface for the document RAG cartridge. Proves that:
|||   1. Query, listing, and info are read-only (a read is never denied).
|||   2. Ingest and deletion are writes (gated by the adapter).
|||   3. Operations map unambiguously to integer ABI codes.
|||   4. A collection name is path-safe, admitting no traversal.
module Librarian.Protocol

import Data.String

%default total

||| Every MCP tool the cartridge exposes.
public export
data Operation
  = -- Reads
    Query
  | ListCollections
  | CollectionInfo
    -- Writes
  | Ingest
  | DeleteCollection

||| Operations that are read-only (safe to serve without side effects). This
||| witness is what the cartridge trusts when enforcing "never deny a read".
public export
data IsReadOnly : Operation -> Type where
  QueryReadOnly : IsReadOnly Query
  ListReadOnly  : IsReadOnly ListCollections
  InfoReadOnly  : IsReadOnly CollectionInfo

||| Operations that mutate stored state and so must be gated by the adapter.
public export
data RequiresWrite : Operation -> Type where
  IngestWrites : RequiresWrite Ingest
  DeleteWrites : RequiresWrite DeleteCollection

||| No operation is both a read and a write. Stated as a refutation: given a
||| read-only witness and a write witness for the same operation, derive Void.
public export
readNotWrite : IsReadOnly op -> RequiresWrite op -> Void
readNotWrite QueryReadOnly IngestWrites impossible
readNotWrite QueryReadOnly DeleteWrites impossible
readNotWrite ListReadOnly  IngestWrites impossible
readNotWrite ListReadOnly  DeleteWrites impossible
readNotWrite InfoReadOnly  IngestWrites impossible
readNotWrite InfoReadOnly  DeleteWrites impossible

||| Integer codes exported across the C ABI. Reads occupy 0..2, writes 100..101;
||| must match the dispatch in the Zig core (ffi/src/librarian.zig).
public export
operationCode : Operation -> Int
operationCode Query            = 0
operationCode ListCollections  = 1
operationCode CollectionInfo   = 2
operationCode Ingest           = 100
operationCode DeleteCollection = 101

||| C ABI export: is this operation code read-only?
||| Returns 1 for true, 0 for false, -1 for an unknown code.
export
librarian_is_readonly : Int -> Int
librarian_is_readonly 0   = 1  -- Query
librarian_is_readonly 1   = 1  -- ListCollections
librarian_is_readonly 2   = 1  -- CollectionInfo
librarian_is_readonly 100 = 0  -- Ingest
librarian_is_readonly 101 = 0  -- DeleteCollection
librarian_is_readonly _   = -1

||| A character admissible in a collection name: ASCII alphanumerics, hyphen,
||| and underscore. This admits no path separator and no dot, hence no traversal.
public export
isSafeChar : Char -> Bool
isSafeChar c = isAlphaNum c || c == '-' || c == '_'

||| A collection name is path-safe when it is non-empty, at most 64 characters,
||| and composed solely of admissible characters. Mirrors store.validateSlug.
public export
pathSafe : String -> Bool
pathSafe s =
  let cs = unpack s in
  not (null cs) && length cs <= 64 && all isSafeChar cs

||| A collection name carrying a proof that it is path-safe. The adapter may
||| construct a Collection only from a name that validates, so a traversal name
||| is unrepresentable.
public export
data Collection : Type where
  MkCollection : (name : String) -> (0 prf : pathSafe name = True) -> Collection

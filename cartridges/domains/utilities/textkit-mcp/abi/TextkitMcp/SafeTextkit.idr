-- SPDX-License-Identifier: MPL-2.0
-- Copyright (c) 2026 Jonathan D.A. Jewell (hyperpolymath)
-- TextkitMcp ABI: type-level invariants for textkit-mcp (base64 encode).

module TextkitMcp.SafeTextkit

%default total

-- Request/response records.
public export
record TextkitRequest where
  constructor MkRequest
  text : String

public export
record TextkitResponse where
  constructor MkResponse
  base64 : String

-- P2: every request carries a text field.
export
requestHasText : (r : TextkitRequest) -> String
requestHasText r = r.text

-- P1: encoder is total.
public export
Encoder : Type
Encoder = TextkitRequest -> TextkitResponse

export
identityEncoder : Encoder
identityEncoder req = MkResponse req.text

export
encoderTotal : (e : Encoder) -> (req : TextkitRequest) -> TextkitResponse
encoderTotal e req = e req

-- P3: genuine response is not the stub marker.
public export
STUB_MARKER : String
STUB_MARKER = "stub"

public export
Genuine : TextkitResponse -> Type
Genuine resp = Not (resp.base64 = STUB_MARKER)

export
identityEncoderGenuine : (req : TextkitRequest) -> Not (req.text = STUB_MARKER) ->
                         Genuine (identityEncoder req)
identityEncoderGenuine _ notStub = notStub

-- Capability model: textkit-mcp grants no capabilities (pure computation).
public export
data Cap = Net | Fs | Cred | Clock | Rand

public export
textkitCaps : List Cap
textkitCaps = []

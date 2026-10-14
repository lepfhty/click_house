# 03 — Opt-in HTTP compression

- **Status:** proposed
- **Area:** network IO
- **Default-safe:** no → ship as opt-in
- **Effort:** S

## Problem
The client never requests compressed responses or compresses insert bodies. JSON results
and `JSONEachRow` inserts are highly compressible (keys repeat on every row).

## Evidence
Synthetic 22 MB JSON response → 1.1 MB gzipped (overstated; real data compresses less,
but several-fold is typical). Needs measurement on a real server and link.

## Why not on by default
- Response compression needs the `enable_http_compression=1` setting, which users with
  `readonly=1` cannot change via query params.
- Compression costs CPU on both ends; it slows things down on localhost or fast LANs.
- Some proxies in front of ClickHouse may handle `Content-Encoding` differently.

## Proposal
- `config.compression = nil` (default) | `:gzip`.
- When `:gzip`: send `enable_http_compression=1` on reads. `Net::HTTP` already sends
  `Accept-Encoding: gzip` and decompresses transparently; confirm other Faraday adapters
  do too, or decode in a middleware.
- Gzip insert bodies with `Content-Encoding: gzip` (consider a low compression level
  for speed).
- Document when to turn it on: remote / cloud / cross-region connections, large results
  or inserts.

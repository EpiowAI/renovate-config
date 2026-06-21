# EpiowAI Renovate Config

EpiowAI/renovate-config is the EpiowAI organization relay preset for Renovate. It extends the Sylphx org-wide Renovate preset and contains only EpiowAI-specific override points.

## Lifecycle

- State: `production`
- Layer: `tooling`
- Machine manifest: [`.doctrine/project.json`](./.doctrine/project.json)

## Goals

- Give EpiowAI repositories a stable Renovate preset entry point.
- Extend [SylphxAI/renovate-config](https://github.com/SylphxAI/renovate-config) as the base dependency-update policy.
- Keep any EpiowAI-specific Renovate overrides in `default.json`.

## Non-Goals

- This repository does not own the base Renovate policy.
- This repository does not own application dependency choices inside EpiowAI product repositories.
- This repository does not own enterprise engineering doctrine.

## Boundary

This repository owns only the EpiowAI org relay preset. Base policy changes go upstream to `SylphxAI/renovate-config`; product-specific dependency exceptions belong in the product repository that owns them.

## Public Surfaces

- Renovate preset: [`default.json`](./default.json)
- Usage context: [`README.md`](./README.md)

## Delivery

There are currently no required status contexts on `main`. Changes become effective after merge when Renovate resolves `github>EpiowAI/renovate-config`. Production proof is JSON validation, GitHub main readback, and the doctrine project-control audit; downstream Renovate runs prove consumer behavior.

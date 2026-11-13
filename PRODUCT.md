# Product

<!-- impeccable:product-schema 1 -->

## Platform

ios

## Stack

Swift 6, SwiftUI, iOS 26+ (AlarmKit). XcodeGen project, pure-Swift `WakelatchCore` package for scheduling and challenge logic.

## Users

Public App Store users who sleep through or snooze past ordinary alarms: heavy sleepers, chronic snoozers, people with a hard "must be up by" time (class, shift, flight). They meet the app twice a day: once at night, half-attentive, setting tomorrow's times; once in the morning, groggy, in a dark room, with one hand, trying to make the noise stop.

## Product Purpose

Get the user out of bed by their deadline. The user sets two times, an Ideal (when they'd like to be up) and a Deadline (when they must be up). Wakelatch rings softly before Ideal, then "latches" the main and deadline alarms: a latched alarm keeps re-ringing until the user finishes a challenge (math, eyes open, steps, typing, and others). Short "awake checks" after the challenge catch falling back asleep. Success is being up by the Deadline on every day it was set.

## Positioning

Free, MIT-licensed, no ads, no accounts, no network code. Two-time model (Ideal + Deadline) instead of one alarm plus snooze. Enforcement is honest about its limits: it blocks the common escape routes (Stop, leaving the app, deleting the app while ringing) and states the ones no app can block (turning the phone off).

## Operating Context

- Night: setting or checking tomorrow's Ideal and Deadline, often in bed, low light.
- Morning: the alarm rings at ringer volume through silent mode and Focus; the system alert's Stop opens Wakelatch to the challenge. Dark room, bleary eyes, one hand, sometimes no glasses.
- Awake checks a few minutes later: one tap within 60 seconds.
- All challenges run on the device; nothing leaves the phone.

## Capabilities and Constraints

- AlarmKit: system alarms, can't set volume, per-app cap on scheduled alarms (number unverified), the system Stop button can't be removed.
- Family Controls entitlement for blocking app deletion while ringing (requires Apple approval and user opt-in).
- Emergency skips: two per month, each requires typing a long phrase.
- Terminology: Ideal, Deadline, nudge, latch, ring, guard ring, challenge, awake check, skip.
- Undecided: sound set, full challenge list for v1, widget/Live Activity scope.

## Brand Commitments

- Name: Wakelatch.
- Voice: dry and matter-of-fact. Short plain statements ("Ring 3 of 10. Solve to stop."). No cheerleading, no scolding, no exclamation marks.
- Not bound to the owner's personal "Ledger" design system; the app has its own identity.

## Evidence on Hand

Sleep research summary in `docs/plan.md` (Hilditch 2019, Sundelin 2024, Ogawa 2022, McFarlane 2020, Fino 2020). No users, reviews, testimonials or usage stats exist yet; do not invent any.

## Product Principles

1. Morning screens are for a groggy person: one task per screen, huge targets, no reading required.
2. The latch must be trustworthy in both directions: it never lets you off by accident and never traps you because of a bug (skips exist).
3. Say exactly what will happen next (next ring time, rings left), never vaguer.
4. Nothing leaves the phone.

## Accessibility & Inclusion

Must work with Dynamic Type, VoiceOver and Reduce Motion, and every challenge type needs an accessible alternative (a challenge someone physically can't do must be swappable).

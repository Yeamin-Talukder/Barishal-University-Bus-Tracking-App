# Contributing to BU Bus Tracker

Thank you for helping University of Barishal students find their bus.

## Ways to help

- **Report wrong data.** A stop in the wrong place, a route line on the wrong
  road, or a departure time that differs from the transport office's
  schedule. Say which route and stop, and what is correct.
- **Report a bug.** Use the bug report template: what you did, what you
  expected, what happened, your phone model and Android version, and the app
  version (Profile tab).
- **Suggest an idea.** Use the feature request template.
- **Send a pull request** for code, documentation or translations.

## Development rules

The project has a few firm rules (see [DEVELOPMENT.md](DEVELOPMENT.md)):

- **Never invent data.** No made-up routes, stops, schedules, bus numbers or
  GPS positions. Sample data must be clearly labelled and kept apart from
  real data.
- **Do not claim a feature works until it has been tested,** and say how it
  was tested.
- Colours, shapes and motion come from the theme in `lib/core/theme/`; do
  not hard-code colours in screens.

## Before opening a pull request

```bash
flutter analyze
flutter test
```

Both must pass. Add tests for new behaviour, and update `DEVELOPMENT.md`
when you change what the app does.

## Setting up

See "Getting started" in the [README](README.md). You need your own Firebase
project for sign-in and live data (`flutterfire configure`); the map and the
built-in schedule work without one.

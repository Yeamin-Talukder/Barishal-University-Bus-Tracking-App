# Security policy

## Reporting a vulnerability

Please do not report security problems in public issues.

Report them privately through GitHub: on this repository, open **Security →
Report a vulnerability**. Include what you found, how to reproduce it, and
what an attacker could do with it.

You will get a reply as soon as possible, and credit once it is fixed if you
want it.

## Scope

Of most interest:

- Bypassing the Firestore or Realtime Database security rules
  (`firebase/firestore.rules`, `firebase/database.rules.json`), for example
  writing a bus position without being that bus's driver, or changing a
  user's role.
- Ways for a signed-in account to gain driver or admin rights.
- Exposure of personal data (staff profiles, emails).

Bus routes, stops, schedules and live positions are public by design.

## Releases

Only download the app from this repository's Releases page or the project
website, and check the SHA-256 checksum shown on the release.

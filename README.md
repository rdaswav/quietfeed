<p align="center">
  <img src="docs/assets/banner.svg" alt="Quiet Feed: Instagram, YouTube and Facebook, without the endless parts." width="100%">
</p>

Quiet Feed is a small iPhone app that opens Instagram, YouTube and Facebook as their mobile websites inside its own browser and hides the parts built to keep you scrolling: Reels, Shorts, Explore and "suggested for you" content. Your feed, stories, messages and subscriptions stay.

> **Status: early.** The app is built and runs on the author's own iPhone, but the hide rules for each site still need tuning against live pages, and it has only had light daily use. The screens below are mockups of the design, not screenshots. See [Roadmap](#roadmap) and [Limitations](#limitations).

<p align="center">
  <img src="docs/assets/screens.svg" alt="Three screens: Home with time left per site, the Browser with the feed and a countdown, and the calm limit reached screen." width="100%">
</p>

## How it works

iOS does not let one app change another, so nothing can remove Reels from the official Instagram app. Quiet Feed takes the same approach as other apps in this space:

1. Each site loads in its own `WKWebView` with its own cookie store, so logins are kept separate.
2. A small script injected before the page renders hides sections with CSS and watches for content that loads later.
3. Links to Reels and Shorts are redirected to somewhere useful (a Short opens as a normal video, a Reels link goes home).
4. Everything runs on the device. There is no account, no tracking and no server you have to trust.

On top of that:

- **Daily limits with friction.** A time budget per site. Extending it or loosening a setting makes you wait out a countdown and type a phrase first.
- **Shield the official apps.** Uses Screen Time (Family Controls) so the real apps can't be used to sidestep the filter. A short Post Mode unlocks them when you need to upload something.
- **Rules you can fix without a rebuild.** Hide rules live in a plain JSON file, `rules/rulepack.json`. The app can fetch an updated copy from a small server you host, so a site redesign is a file edit, not a new app release.

## Roadmap

- [x] Project scaffold and design
- [x] Rule pack and validator
- [x] Injected runtime and tests
- [x] Browser with navigation policy
- [x] Rules fetched from your own server
- [x] Limits and friction
- [x] Shielding the official apps
- [x] Onboarding and polish

## Building it

Requirements: macOS with Xcode 27 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Node 20 or later.

```bash
brew install xcodegen
xcodegen generate
./scripts/verify.sh
```

`verify.sh` runs the Swift package tests, the JavaScript tests against synthetic pages, the rule pack validator and a simulator build. To run on your own iPhone, copy `Local.xcconfig.example` to `Local.xcconfig` (git-ignored, picked up automatically through `Config/Base.xcconfig`) and set your development team. Shielding the official apps needs the Family Controls capability, which requires a paid Apple Developer account and a real device.

## Testing and feedback

Want to try it, or help test? See [`docs/TESTING.md`](docs/TESTING.md). Bugs and broken hide rules go in the [issue tracker](https://github.com/rdaswav/quietfeed/issues). The [privacy policy](docs/PRIVACY.md) is short: the app collects nothing.

## Hosting your own rules server

This is optional. Without it the app uses the rules built into it, which only change when you rebuild. With it, a site redesign is a one-file edit that reaches the phone without a rebuild.

The server is a small nginx container that serves one file, `rulepack.json`, and returns 404 for everything else. [`server/README.md`](server/README.md) has the setup for a NAS or any machine that runs Docker, and [`scripts/deploy-rules.sh`](scripts/deploy-rules.sh) validates and pushes a new pack over ssh. Then enter the address, for example `http://your-server:8787/rulepack.json`, in the app under Settings, Rules, Server address, and tap **Check now**.

Rules are plain data, never code, because the file travels over plain HTTP. Run the server on a network you trust, such as your home network, and do not expose it to the internet.

## Maintenance

### Fixing a hide rule

Sites change their pages, so rules go stale. The app shows "rules may be stale" for a site when one of its `canaries` is missing from the home page.

1. Attach the Web Inspector (below) and find the element that should be hidden.
2. Edit that site's entry in `rules/rulepack.json`: add a CSS selector to `hideSelectors`, or use `hideByText` when the class names are scrambled. Rules are plain data and never contain code.
3. Bump `packVersion`. A pack is only accepted if its version is not lower than the one the app already has.
4. Run `./scripts/verify.sh`. It validates the pack and runs the page tests.
5. Either rebuild the app, or, if you host your own rules server, run `./scripts/deploy-rules.sh` and then tap **Check now** under Settings, Rules. See [`server/README.md`](server/README.md).

### Web Inspector

Debug builds make each web view inspectable. On the iPhone turn on Settings, Safari, Advanced, Web Inspector. On the Mac turn on Safari, Settings, Advanced, Show features for web developers. With the phone connected and Quiet Feed open on a site, the phone appears in Safari's Develop menu, and the page opens in the inspector. Release builds are not inspectable.

### Re-signing each year

Builds installed from Xcode are signed with a development profile that expires after about a year, and the Apple Developer Program membership renews yearly. Before either runs out, renew the membership, connect the phone and run the app from Xcode again. Your logins and settings are kept. Until you do, the app stops launching once the profile lapses.

### Adding a fourth site

A new site needs a code change, because the app only accepts site ids it knows about. A rules-only update cannot add one.

1. Add an entry to `rules/rulepack.json` with a new `id`, `homeURL`, `allowedHosts`, rules and `canaries`, and bump `packVersion`.
2. Add the `id` to `knownSiteIds` in `Packages/QuietFeedCore/Sources/QuietFeedCore/Rules/RulePackValidator.swift` and to `KNOWN_IDS` in `scripts/validate-rules.mjs`.
3. Add a new fixed UUID for it in `App/Web/SiteWebView.swift`, so the site gets its own cookie store.
4. Optionally add a default daily budget in `LimitSettings.swift`. Without one it uses the 20 minute default.
5. Add a hand-written fixture page and a test next to the existing ones, then run `./scripts/verify.sh`.

## Design

Deliberately unexciting: nothing in the app competes for your attention. One sage accent, amber instead of red, system fonts, hairline borders and no animation beyond system defaults. Plain, short copy with no guilt ("That's today's Instagram.").

| Token | Light | Dark |
|---|---|---|
| Background | `#F6F5F1` | `#121311` |
| Surface | `#FFFFFF` | `#1C1D1A` |
| Text | `#1B1C19` | `#ECEBE6` |
| Accent (sage) | `#5E7A64` | `#8FB096` |
| Warning (amber) | `#B07A2A` | `#D9A65A` |

The logo is a sage rounded square with a single flat line: a feed with nothing left in it. Assets are in [`docs/assets`](docs/assets).

## Limitations

- The mobile sites do less than the native apps: no push notifications, and some message extras (voice notes, calls) and story tools are missing.
- Hide rules depend on each site's page structure and will break when a site changes. Keep `rules/rulepack.json` up to date.
- Quiet Feed is for personal use. It does not scrape, automate or alter your account, and it only hides parts of pages on your own device.
- Not affiliated with or endorsed by Instagram, YouTube, Facebook or Meta. Those names belong to their owners.

## Licence

[MIT](LICENSE). The Instagram, YouTube and Facebook names belong to their owners.

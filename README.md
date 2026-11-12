<p align="center">
  <img src="docs/assets/banner.svg" alt="Quiet Feed: Instagram, YouTube and Facebook, without the endless parts." width="100%">
</p>

Quiet Feed is a small iPhone app that opens Instagram, YouTube and Facebook as their mobile websites inside its own browser and hides the parts built to keep you scrolling: Reels, Shorts, Explore and "suggested for you" content. Your feed, stories, messages and subscriptions stay.

> **Status: in development.** The screens below are the design the app is being built to. They are mockups, not screenshots, and not every feature exists yet. See [Roadmap](#roadmap).

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
- [ ] Rule pack and validator
- [ ] Injected runtime and tests
- [ ] Browser with navigation policy
- [ ] Rules fetched from your own server
- [ ] Limits and friction
- [ ] Shielding the official apps
- [ ] Onboarding and polish

## Building it

Requirements: macOS with Xcode 27 or later, [XcodeGen](https://github.com/yonaskolb/XcodeGen) and Node 20 or later.

```bash
brew install xcodegen
xcodegen generate
./scripts/verify.sh
```

`verify.sh` runs the Swift package tests, the JavaScript tests against synthetic pages, the rule pack validator and a simulator build. To run on your own iPhone, copy `Local.xcconfig.example` to `Local.xcconfig` (git-ignored, picked up automatically through `Config/Base.xcconfig`) and set your development team. Shielding the official apps needs the Family Controls capability, which requires a paid Apple Developer account and a real device.

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

To be added before the repository is made public.

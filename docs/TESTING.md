# Testing Quiet Feed

Thank you for trying it. This is early software, and your notes on what breaks are the point.

## What it is

Quiet Feed opens Instagram, YouTube and Facebook as their mobile websites and hides Reels, Shorts, Explore and suggested content. It can also limit your daily time on each site and, if you allow it, stop the official apps from opening.

## Install

1. Install Apple's free **TestFlight** app from the App Store.
2. Open the invite link you were sent, then tap **Install** or **Accept**.
3. Open Quiet Feed. A three page welcome appears once.

You need an iPhone on iOS 18 or later.

## First things to try

- Sign in to each site once. YouTube uses Google sign-in, so check that works.
- Scroll the Instagram feed and open a profile. Check there are no Reels, Explore or suggested posts.
- On YouTube, check Shorts are gone and a Shorts link opens as a normal video.
- On Facebook, check Reels and suggested content are gone.
- On TikTok (early), check the Discover tab and the Open app pill are gone. The For You feed itself stays, so use the daily limit.
- In Settings, set a short daily limit for one site and use it up. Check the calm screen appears, and that adding time makes you wait.
- Try posting a photo from a site. This is where the mobile websites are weakest.

## What to expect

- The mobile sites do less than the real apps: no push notifications, and some message extras such as voice notes and calls are missing.
- Sites change their pages without warning, so a hidden section can come back. That is the most useful thing to report.
- Limits and usage are per phone. Nothing about you is sent to anyone. The only thing the app asks for over the network is an updated file of hiding rules, so a rule fix can reach you without a new build.
- If shielding of the official apps is in your build, it needs Screen Time access and you choose the apps yourself. You can switch it off in Settings, after a short wait.

## Reporting a problem

Tell me which site, what screen, what you expected and what happened. A screenshot helps. Please do not send passwords or private messages.

- Open an issue at https://github.com/rdaswav/quietfeed/issues, or
- message the person who invited you.

In TestFlight you can also send feedback straight from the app: take a screenshot and tap **Share Beta Feedback**.

Quiet Feed is not affiliated with or endorsed by Instagram, YouTube, Facebook, TikTok or Meta.

# Arc

Native iOS 26 navigation app. SwiftUI Liquid Glass, Mapbox Maps 11.32.0,
Navigation 3.32.0, Search 2.32.0, SwiftData and ActivityKit. Bundle ID: `dev.freddiephilpot.arc`.

## Windows → unsigned IPA

1. Copy `.env.example` to `.env.local` and supply your Mapbox tokens. The `pk.` runtime token is embedded in the application; the secret `sk.` downloads token is never bundled. Use a downloads token scoped to `DOWNLOADS:READ`.
2. Push this directory to your GitHub repository. Set Actions Secrets `MAPBOX_ACCESS_TOKEN` and `MAPBOX_DOWNLOADS_TOKEN`.
3. Run **Build unsigned Arc IPA** in Actions (or push to `main`). Download **Arc-unsigned-ipa** and sign/sideload `Arc-unsigned.ipa` with your external signing tool, including its `ArcActivity.appex` extension.

No Apple account, certificates, provisioning profiles or signing step is used in CI. XcodeGen generates the complete Xcode project from `project.yml`; edit Swift and YAML directly on Windows. macOS 26 / Xcode 26.6 performs dependency resolution and the device build. Build errors stay visible in the Actions log; failed build diagnostics are uploaded separately.

Optional Windows configuration check: `python scripts/configure.py`. Build tooling checks: `python -m unittest discover -s Tests/Build -v`. Local Xcode builds require generating the configuration and `xcodegen generate` first, plus a private `.netrc` for Mapbox package downloads.

## Use

Tap **Use my location** or the recenter button to enable location access. Search offers autocomplete; submitting a query or choosing a category shows resolved results on the map. Long-press to drop a pin. Place cards offer directions, local saves and sharing. Directions support driving/walking, alternative routes, a custom origin and reorderable stops. Guidance requires your GPS position near the selected origin. Finish on arrival saves a summary; End cancels a journey. Start an optional movement session from Profile.

The app keeps saved places, recents and journey summaries on the device. It doesn't persist a GPS trace. Live Activities respect the iOS activity setting; background location is requested when starting a journey/session. Speed limits, lanes, traffic and place metadata depend on Mapbox coverage. Unknown speed limits remain blank. Normal pan/rotation gestures pause following, and Resume restores it. Offline downloads are outside this version; the service boundaries and SDK predictive cache provide a future integration point.

## Verification boundary

This source was built from current released SDK signatures on Windows. An iOS compile, simulator tests and visual/device QA require the Actions macOS runner; they have not been run from Windows. Check the first workflow result before treating the IPA as verified. Real-device QA should cover route deviation, multistop arrival, denied permissions, audio ducking, Dynamic Island, reduced motion and poor connectivity.

API references: [Navigation](https://github.com/mapbox/mapbox-navigation-ios/tree/3.32.0), [Maps](https://github.com/mapbox/mapbox-maps-ios/tree/11.32.0), [Search](https://github.com/mapbox/mapbox-search-ios/tree/2.32.0), [Liquid Glass](https://developer.apple.com/documentation/swiftui/glasseffectcontainer), [runner image](https://github.com/actions/runner-images/blob/main/images/macos/macos-26-Readme.md).


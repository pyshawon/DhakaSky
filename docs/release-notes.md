A living, illustrated wallpaper of Dhaka for your Mac. Universal app for Apple silicon and Intel, macOS 14 Sonoma or later.

### Fixed in 2.1

- The lock-screen still no longer fills up your disk. Version 2.0 saved a new desktop picture every few minutes, and macOS keeps a large cached copy of every desktop picture it is given. Now there is one still per look (day, golden hour, night, dry or rainy), drawn once in clean conditions and reused, so it costs no extra disk space over time.
- Nicer nights in every view: lights glow softly, moonlight brightens the scene, the night sky is deeper and clouds blend in, and the paper grain is lighter in the dark.

### Install

1. Download **DhakaSky-*.dmg** below, open it and drag **Dhaka Sky** into **Applications**. (Or download the .zip and move the app to Applications.)
2. Open it. The app isn't notarized by Apple (it's a free open-source project), so the first time macOS will say it can't verify the app. Click **Done**, then go to **System Settings > Privacy & Security**, scroll down and click **Open Anyway** next to Dhaka Sky.

   Or, in Terminal: `xattr -dr com.apple.quarantine "/Applications/Dhaka Sky.app"`
3. Look for the weather icon in the menu bar. The screen saver for the animated lock screen installs itself.

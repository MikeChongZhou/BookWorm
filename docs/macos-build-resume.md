# macOS build completed

2026-11-27: macOS Release 1.0.10 (13) built, Developer ID signed, dedicated BookWorm iCloud profile embedded, strict deep signature verification passed. Not notarized. Output: dist/BookWorm-1.0.10-build13-macOS.zip. No GitHub upload. Only macOS distribution build number incremented; shared source version remains 1.0.10+11.

Includes bounded private local diagnostic files and Settings export for all four platforms, plus translation diagnostics and cloud expired-grant recovery. 28 targeted unit checks passed; static analysis clean. Real Mac launch and native save/export verified; exported metadata file: dist/BookWorm-macOS-build13-export-check.txt. Other platform packages/export dialogs not tested this turn. No simulator testing.

Observed live incident: Google Drive SDK invalid_grant. Native sync now shows a concise reauthorization prompt without raw SDK error data. Explicit reauthorization succeeded. Real sync completed: 0 files uploaded, 20 downloaded; completion event persisted in the diagnostic log. Receipt: dist/macos-build13-status.json. Local library preserved. App still running from build/macos/Build/Products/Release/BookWorm.app. Another legacy com.yuejian.yuejian app also exists and has a separate library.

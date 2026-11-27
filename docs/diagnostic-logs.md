# Local diagnostic logs

Available in the shared iOS, Android, Windows and macOS implementation. Open Settings > Diagnostic logs > Export logs. The native save dialog writes a text snapshot to the selected destination; cancellation does not report success or send data anywhere. The settings card also displays the actual private log directory.

Logs live in a `logs` subdirectory of path_provider's application-support directory. Exact paths depend on OS and sandbox/container configuration. Active file: `bookworm.log`; archives: `bookworm.log.1` through `.3`. Each file is limited to approximately 1 MiB. Rotation/export/writes share an asynchronous queue; at most 200 pending events are retained. Storage failure does not interrupt reading or listening, and export reports an error if files cannot be read/saved.

Recorded metadata: UTC timestamp, app version/build/platform, translation request ID, model, HTTP status, retry timing, safe known provider status/code/type, safe provider request ID, sync provider/counts/duration/result and error class, audio playback/progress-save error class. Metadata keys are allowlisted and string values constrained. No raw SDK/provider exception message, request/response body, authorization header, API key, login token, cloud URL, book title/content, translation or account identifier is written. Logs are local and excluded from book sync; export never uploads automatically. Events before this feature was installed cannot be recovered.

## Sync incident observed 2026-11-27

The existing macOS App displayed an AppAuth `invalid_grant` error: token expired or revoked. Google Drive was the active cloud. Local books were still present. This requires renewed user authentication; it is not evidence of lost book files. Raw SDK exception details have been replaced by a concise reauthorization message. Background sync never opens authentication UI. When an explicit reconnect encounters expired Google SDK login state, it signs out locally and opens a fresh authorization flow; it does not revoke remote consent or delete any cloud/library files.

Validation: static analysis clean; 28 targeted data/native-channel unit checks passed (log safety/rotation/export/disk failures, auth classification, translation, TTS and cloud transfer). No simulator testing. Cross-platform export dialogs and actual account reauthorization still require native acceptance; macOS Release is built separately and its receipt records observed outcomes.

Native macOS acceptance completed: Settings export saved a valid diagnostic text file; the active log directory was shown correctly and the app-start metadata carried build 13. Google Drive reauthorization recovered the expired grant, then real sync completed with 0 uploaded and 20 downloaded files. Completion metadata was verified in the local log. Other three native export dialogs remain unverified.

# StreetZim maps

Open Maps directly from the Library sidebar on macOS and iPad, or the Maps
tab in the iPhone library sheet. Maps is also available under Categories.
The map catalog loads independently of the ordinary OPDS book catalog.
Choose a map area and a map language. The initial language follows
the app's language, then English, then the first language the region offers.
An explicit choice is preserved when switching regions that offer it.
Languages in the library's ordinary OPDS filter do not hide multilingual maps.

## Choosing a map area

Open **Map area** to browse **Cities & local areas**, **Countries**, or
**Regions & continents**. Each group is alphabetical by its displayed titles.
Search from the first screen to find areas across all groups, or search inside
a group to narrow its list. Search ignores case and accents and also matches
catalog IDs with spaces or hyphens.

Selecting an area closes the browser and returns to the language/download
controls. Cancel leaves the existing selection untouched. Switching areas keeps
an explicit language choice when the new area offers it; saved maps are unchanged.

`Support/StreetZimAreaGroups.plist` is an explicit geographic snapshot of
StreetZim's `cloud/regions.tsv` and `cloud/region-variants.tsv`. Build-size tiers
are not geographic categories: Canada, China, Russia and the United States remain
countries even though their build tier is `continent`. Variants retain their
own IDs. The snapshot never adds unavailable downloads, and new/unrecognized IDs
remain selectable under **Other areas** until the snapshot is updated.


## Languages and translation status

Maps uses Kiwix's existing **37 shipped UI locales**; it does not add app languages
just for this feature. The Dagbani and Igala source folders remain excluded by
`project.yml`. The Maps controls, progress and errors now have unreviewed machine
translations in the other **35 non-English locales**. Northern Sami keeps the
existing English fallback until a reliable translation is available.

Only the Maps controls carry the machine-translation notice; it makes no claim
about Kiwix's existing translations. `Support/MapsMachineTranslatedLocales.plist`
records the unreviewed locales. After a native speaker reviews a Maps translation,
remove that locale from the list. The initial Kabyle Maps batch used actual
`agbalu/Amrouche-1.3B` inference; the later area-browser labels and other new
translations are machine-generated, not native-speaker approved. Preserve `%@`
placeholders when correcting them.

App-interface language and map-content language are independent. Every language
the StreetZim catalog offers remains selectable, including languages without a
Kiwix UI translation. Defaults preserve script and region when available:
Traditional Chinese is not replaced by an earlier Simplified Chinese entry, and
an explicit Brazilian Portuguese version wins over a generic Portuguese entry.

The native map-language picker puts available region-local languages first under
**Local languages**, followed by a separator and **Other languages**. Both sections
are alphabetical by their displayed names in the app's interface language, not
by catalog insertion order. Regional membership comes from the bundled
`Support/StreetZimRegionLanguages.plist` snapshot of StreetZim's
`cloud/region-languages.tsv` registry. Membership matches the language regardless
of script or regional tag, while each original catalog version remains separately
selectable. Only versions available for the selected region appear; the registry
does not add content languages. If no local versions are available, including for
an unknown region, the picker shows all available languages alphabetically without
a local section. This presentation does not change the default-language rules or
an explicit selection.
Refresh the bundled snapshot from that registry when regional language membership
changes; adding a region must not infer its local languages from menu order.

The embedded viewer and article content come from the selected ZIM; adding native
app translations does not rewrite previously downloaded archives.

## Saved maps and composition

The **Downloaded maps** section in both Downloads and Maps lists available
map files from the local library, even when the network catalog is unavailable
or a different region/language is selected. Tap a saved map's title to open it.
Saved maps use the catalog's canonical region title, matched by the archive's
`Name` (`ZimFile.persistentID`) against a region's `menu.name`. The subtitle
shows the localized language and preserves the original archive title when
different: a Russian Iceland map is **Iceland** with “Russian · Исландия”,
while Spanish Baltics is **Baltics** with “Spanish · OSM - Baltics” (language
labels may also include their native names).
Without a matching catalog entry, names in the form `osm_<language>_<region>`
provide an offline label: underscores and hyphens in the region slug become
spaces, with title casing. Unknown naming formats keep the archive title and
use the stored language codes. These are display labels only; stored archive
metadata is never rewritten.
Completed maps also remain under Opened. Downloads shows active book downloads,
the active map's composition/network progress and Cancel action, and saved maps.
Finishing or cancelling a map transfer does not hide previously saved maps.

The catalog is StreetZim's `streetzim-build-index/1`. Its relative recipe
paths are resolved against `/build/`, as in StreetZim's browser builder.
The assembler supports `streetzim-recipe/2`; it verifies masked source
chunks and generated bytes with SHA-256, appends and checks the ZIM's MD5,
and checks the optional whole-file MD5 before publishing a file. Only a
verified result is passed to the existing `LibraryOperations.open` import
path. Existing files are never overwritten. An already installed version is offered
for opening rather than composed into a duplicate file.
Import success is reported only after an owned background context saves the
library record. A failed save rolls back that import without discarding unrelated
pending library edits. The verified map file is retained; opening it again retries
the import rather than claiming success from an in-memory file registration alone.
An unreadable installed archive is treated as a reuse miss: Download can rebuild
it from verified chunks without overwriting the damaged file. If the existing
archive is readable but its library import fails, that failure is still reported
rather than triggering a redundant download.

Recipe validation runs off the UI actor and propagates cancellation into
hash, mask and segment validation. Mask bounds are checked before arithmetic;
unordered, duplicate and overlapping masks are normalized to a sorted union
in O(M log M) time. Segment overlap checks use binary search, and chunk
hashing visits only masks intersecting that chunk, rather than rescanning all
M masks for every segment or chunk. No recipe-size or mask-count cutoff is
imposed; masked source bytes still cannot be copied into the output.
Disk preflight checks output capacity first, then unions referenced chunk
intervals per source before counting missing cache data. Repeating a source
range in many segments does not repeatedly scan the same source chunks.

## Map size and progress

Before downloading, the chooser shows only **Map size**: the selected map's
saved file size (`menu.size`). There is no pre-download transfer estimate.
While downloading, progress shows bytes written and bytes arriving for the
current part. Reuse of saved map data and downloaded parts is automatic.

## Configuration

`project.yml` defines these build settings, expanded into `Support/Info.plist`:

| Setting | Default |
| --- | --- |
| `STREETZIM_CATALOG_URL` | `https://streetzim.web.app/build/recipes/index.json` |
| `STREETZIM_PROXY_URL` | `https://streetzim-build-proxy.tiltastech.workers.dev` |

These are external StreetZim services, not Kiwix-operated infrastructure. The
catalog is published on StreetZim's Firebase Hosting site. The build proxy is
StreetZim's Cloudflare Worker, serving source ranges from Archive.org; it shares
the operator's request quotas with other StreetZim services. Availability and
operational ownership need agreement before an upstream production release.
This feature does not deploy these services or require a StreetZim-patched
CoreKiwix: the repository's stock CoreKiwix **14.2.1-2** reads the completed ZIMs.

Override the settings in Xcode or on an `xcodebuild` command to use a staging
deployment. The catalog must be HTTPS, with recipe paths relative to `/build/`.
No Firebase preview-channel or preview-proxy URL is compiled into the app.
An unavailable catalog displays an error and Reload; saved maps remain usable.

## Small offline reviewer demo

After the repository's normal setup (`brew bundle`, `python3 localizations.py
generate`, `xcodegen generate`), use the Kiwix scheme. The checked-in
`Tests/Fixtures/streetzim-demo.zim` is a 36 KB, standard libzim-generated ZIM
containing an original tiny SVG map and a linked detail page. It has no network
assets. Open it with Kiwix on macOS, or copy it to Files and open it on iOS.
It should appear in Opened, Maps and Downloads; opening it displays **StreetZim
test map**, and **Fixture detail** opens the second page.

For a reproducible iPhone/iPad lifecycle demo, run `SavedMapsUITests` from the
corresponding UI-test scheme. The test launches Debug with
`-streetzim-ui-test-store <fresh UUID>`. This selects an isolated SQLite store,
loads the bundled tiny catalog, and imports the real ZIM exactly once. Relaunch
uses the same store; deleting the map does not reseed it. The hook and fixture
bundle are absent from Release builds. The catalog's French option intentionally
does not change the language of the saved English archive.

The permanent scenario changes language, navigates to Downloads, opens both
real HTML pages, terminates/relaunches the app, reopens the saved map, deletes
it through the normal library action, and verifies deletion after another launch.
It requires no accounts, live catalog, or multi-GB download.

### Reader-search regression on iOS apps running on Mac

`SavedMapsUITests.testReaderSearchOpensResultAndCanBeReopenedAndDismissed`
opens the real offline fixture, focuses native reader search, searches for
**StreetZim**, opens **StreetZim fixture detail**, then repeatedly searches and
dismisses search. The iPad's native control uses Clear text rather than a
Cancel button. Result queries are scoped to the results scroll view so the
reader's sidebar tab cannot satisfy them.

`testReaderTextFieldSearchSupportsClearAndCancellation` exercises the same
archive/results flow with the scene-local text field, including clear and
repeated cancellation. The Debug-only `-reader-search-text-field-ui-test`
argument makes that presentation testable on simulators; release builds ignore
it. Xcode does not support UI tests on its Designed for iPad Mac destination,
and this Mac rejected the isolated iOS development app at launch. Simulator
coverage of the text-field presentation is not an end-to-end iOS-on-Mac run.

SDK 27-built iOS apps on older macOS can assert inside
`_UISearchPresentationController` → `UINavigationBar.defaultSizeForOrientation`
→ `UIScreen._preferredFocusedWindow` because screen-based focus is unsupported.
The matching stock-UIKit report is
[Apple Developer Forums thread 841090](https://developer.apple.com/forums/thread/841090)
(FB24201508); its author reports an OS fix in macOS 27.2 beta.
Enabling multiple scenes also avoids that assertion, but would change this
app's shared navigation model, so the app does not enable it as a workaround.

Only when `ProcessInfo.processInfo.isiOSAppOnMac` is true, reader search uses a
standard SwiftUI text field in the current navigation toolbar instead of
creating UIKit's search presentation controller. It still uses the existing
archive search model and result views. Beta acceptance should check focus,
typing, clear, opening a result, Cancel, Escape, and Command-F in the actual
iOS-on-Mac runtime. The workaround applies to all iOS-on-Mac versions rather
than guessing the host macOS version from iOS availability checks. iPhone,
iPad, and native macOS retain `.searchable`. Other native searchable screens
are not covered by this targeted workaround.


## Reusing a downloaded language version

The assembler first looks for the exact base UUID in the library. If it
isn't installed, it tries an installed language version whose `Name`
occurs in the selected region's catalog. A composed version preserves the
shared map bytes at their original offsets. Every candidate chunk is
masked and checked against the **new recipe's** SHA-256 before use.

Changed headers, tables, missing bytes and unreadable files fall back to
the verified cache or a range download. Consequently an older build is
safe to try, but only matching bytes are reused. A new base or recipe does
not require special migration logic. A language version can usually
supply most of another version's map bytes; the first and last chunks may
need downloading because the header and tables differ (up to 32 MiB with
16 MiB chunks), along with any new Wikipedia/search data. The source file
is opened read-only.

Chunks obtained from the network are retained under the app's caches
directory, keyed by SHA-256 and length. A retry reconstructs the output
from the beginning using verified cached chunks; it does not resume a
partial output file. Cache eviction is safe. “Clear downloaded map parts”
removes the cache and preserves completed library files.

## Current boundaries

- Composition is a foreground operation, independent of the existing
  background book downloader. Its progress and Cancel action appear in both
  Maps and Downloads. It stays alive when navigating library tabs, but does
  not continue after process termination. iOS auto-lock is
  disabled during the job and restored afterward; manually backgrounding
  Kiwix can suspend the transfer. Keep Kiwix open.
- One map can be composed at a time. Source requests retry twice, then
  leave verified chunks available for the next attempt.
- The composition counter shows bytes written to the finished map. A separate
  “Downloading current part” counter reports incoming network bytes while
  each part (up to 16 MiB) is fetched. Received parts are verified before use;
  slow transfers no longer appear idle until an entire part is available.
- Downloads honor the existing cellular-data preference; Maps provides
  the same toggle as ordinary ZIM downloads.
- Output goes to Documents on iOS and the configured download directory
  on macOS. The destination's security scope is held through import.
- A composed map occupies its full final size. Cached shared chunks use
  additional space until cleared or evicted. Disk space is checked before
  assembly; a write failure still stops and removes the partial output.
- Abnormal process termination can leave a hidden `.streetzim-*.part`
  file in the destination. It can be removed; no incomplete file is
  imported into the library.

## Tests and fixture provenance

`StreetZimTests` covers upstream byte equality, bounds and hash failures,
masked viewer data, app-language matching, canonical/offline/unknown saved-map
labels, catalog overflow/duplicate validation, worker cancellation, cache-only
retry, installed-base reuse, and using another composed language as a source.
Capacity tests cover preflight rejection and rechecking a failed local candidate;
retry tests cover transient recovery and cancellation during backoff.
`StreetZimHTTPTests` exercises range semantics, unknown response lengths,
truncated/oversized data, oversized JSON, and incoming progress while the
response is deliberately held incomplete.
`StreetZimViewModelTests` checks visible incoming progress, stale callback isolation
after cancellation/restart, importing a verified map when cancellation arrives
after publication, and rebuilding an unreadable installed map while preserving
its damaged file. `DownloadedMapsTests` uses real SQLite stores and the real
CoreKiwix importer to cover reopen, deduplication, map filtering, failed saves,
and preserving unrelated pending edits.

`StreetZimAreaTests` covers geographic classification, unknown IDs, distinct
variants, locale-aware ordering, accent/case-insensitive search and empty results.
The small Debug catalog includes representative city, country, larger-region
and unknown-area entries, with only the real Testland ZIM pre-imported.
Native picker UI scenarios exercise browsing, cross-group search, cancellation,
selection and language preservation on iPhone/iPad and macOS.

`Tests/Fixtures/generate_streetzim_demo.py` regenerates the small UI/import fixture
and its catalog using `python-libzim`. Its content is original GPL-3.0-or-later
test data. The test reads the archive's actual UUID rather than pinning a
generator-specific identity.

`Tests/StreetZimFixture.json` was produced from StreetZim commit `4d8190e`:
`tests.langpack.lpzims.write_base` and `write_pack` created a Testland base
and German/French Wikipedia packs, `tools.langpack.recipe2.build_recipe`
created the German recipe, and `tools.langpack.merge_zim.merge` produced
both expected language versions independently. For streaming boundary
coverage the source chunk size is reduced to 256 bytes and SHA-256 hashes
are recalculated; the recipe segments and expected merged bytes are
unchanged. The JSON embeds those inputs and expected outputs so tests do
not depend on a network catalog or a multi-GB map.

Before each network fallback, free space is checked again while reserving
space for the remaining output. This matters when an older installed
language version turns out not to match the new recipe's chunks.

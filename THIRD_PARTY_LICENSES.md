# Third-party licences

Liz's own code is licensed under the Apache License 2.0 ([LICENSE](LICENSE)).
The software and assets below are not: each keeps its own licence, and none is
relicensed by this project. Every licence found is permissive (MIT, BSD,
Apache-2.0, ISC, SIL OFL) or file-level copyleft (MPL-2.0), and all are
compatible with distributing Liz under Apache-2.0.

Generated from `pubspec.lock`, `scrapers/requirements.txt` and the Edge
Functions' imports, by reading each package's own licence file. Regenerate it
when dependencies change.

## Bundled assets

| Asset | Licence |
| --- | --- |
| Space Grotesk font (`assets/fonts/SpaceGrotesk-Latin.ttf`) | SIL Open Font License 1.1 (`assets/fonts/SpaceGrotesk-OFL.txt`) |
| JetBrains Mono font (`assets/fonts/JetBrainsMono-Latin.ttf`) | SIL Open Font License 1.1 (`assets/fonts/JetBrainsMono-OFL.txt`) |
| Google "G" logo on Continue with Google | Trademark of Google LLC, used under Google's sign-in branding guidelines |

## Edge Functions (Deno)

| Module | Licence |
| --- | --- |
| `@supabase/supabase-js` | MIT |
| `deno_dom` | MIT |
| `rss` (deno.land/x) | MIT |
| `@std/assert` (tests only) | MIT |

Embeddings use the `gte-small` model through Supabase's runtime (MIT). AI
summaries call an external, OpenAI-compatible API; no model is distributed
with this repository.

## Python scraper (`scrapers/requirements.txt`)

| Package | Licence |
| --- | --- |
| beautifulsoup4 | MIT |
| requests | Apache-2.0 |
| lxml | BSD-3-Clause |
| Pillow | MIT-CMU (HPND) |
| pytest (tests only) | MIT |

## Dart and Flutter packages (`pubspec.lock`)

Direct dependencies, including development tools, are in bold. The rest are transitive; several are
platform implementations (Android, iOS, Linux, macOS, Windows) that are not
part of the web build.

| Package | Version | Licence |
| --- | --- | --- |
| _flutterfire_internals | 1.3.79 | BSD-3-Clause |
| ansicolor | 2.0.3 | Apache-2.0 |
| app_links | 7.2.1 | Apache-2.0 |
| app_links_linux | 1.0.3 | Apache-2.0 |
| app_links_platform_interface | 2.0.4 | Apache-2.0 |
| app_links_web | 1.0.4 | Apache-2.0 |
| archive | 4.3.0 | MIT |
| args | 2.7.0 | BSD-3-Clause |
| async | 2.13.1 | BSD-3-Clause |
| boolean_selector | 2.1.2 | BSD-3-Clause |
| **cached_network_image** | 4.0.5 | MIT |
| cached_network_image_platform_interface | 5.0.3 | MIT |
| cached_network_image_web | 2.0.3 | MIT |
| characters | 1.4.1 | BSD-3-Clause |
| checked_yaml | 2.0.4 | BSD-3-Clause |
| cli_util | 0.4.2 | BSD-3-Clause |
| clock | 1.1.3 | Apache-2.0 |
| code_assets | 2.1.0 | BSD-3-Clause |
| collection | 1.19.1 | BSD-3-Clause |
| convert | 3.1.2 | BSD-3-Clause |
| cross_file | 0.3.5+5 | BSD-3-Clause |
| **crypto** | 3.0.8 | BSD-3-Clause |
| csslib | 1.0.2 | BSD-3-Clause |
| cupertino_ui | 1.1.1 | BSD-3-Clause |
| dart_jsonwebtoken | 3.4.1 | MIT |
| fake_async | 1.3.3 | Apache-2.0 |
| ffi | 2.2.0 | BSD-3-Clause |
| ffi_leak_tracker | 0.1.2 | BSD-3-Clause |
| file | 7.0.1 | BSD-3-Clause |
| file_selector_linux | 0.9.4+1 | BSD-3-Clause |
| file_selector_macos | 0.9.5+1 | BSD-3-Clause |
| file_selector_platform_interface | 2.7.0 | BSD-3-Clause |
| file_selector_windows | 0.9.3+6 | BSD-3-Clause |
| **firebase_auth** | 7.0.1 | BSD-3-Clause |
| firebase_auth_platform_interface | 9.1.2 | BSD-3-Clause |
| firebase_auth_web | 6.3.2 | BSD-3-Clause |
| **firebase_core** | 5.1.0 | BSD-3-Clause |
| firebase_core_platform_interface | 8.1.1 | BSD-3-Clause |
| firebase_core_web | 4.1.0 | BSD-3-Clause |
| **firebase_messaging** | 17.0.1 | BSD-3-Clause |
| firebase_messaging_platform_interface | 4.11.1 | BSD-3-Clause |
| firebase_messaging_web | 4.3.1 | BSD-3-Clause |
| fixnum | 1.1.1 | BSD-3-Clause |
| flutter_cache_manager | 3.4.5 | MIT |
| **flutter_launcher_icons** | 0.14.4 | MIT |
| **flutter_lints** | 6.0.0 | BSD-3-Clause |
| **flutter_native_splash** | 2.4.8 | MIT |
| flutter_plugin_android_lifecycle | 2.0.35 | BSD-3-Clause |
| **flutter_riverpod** | 3.5.0 | MIT |
| functions_client | 2.7.1 | MIT |
| **go_router** | 18.1.1 | BSD-3-Clause |
| gotrue | 2.27.3 | MIT |
| gtk | 2.2.0 | MPL-2.0 |
| hooks | 2.2.0 | BSD-3-Clause |
| html | 0.15.7 | MIT |
| **http** | 1.6.0 | BSD-3-Clause |
| http_parser | 4.1.2 | BSD-3-Clause |
| **image** | 4.10.1 | MIT |
| **image_picker** | 1.2.4 | BSD-3-Clause, with Apache-2.0 parts |
| image_picker_android | 0.8.13+25 | BSD-3-Clause, with Apache-2.0 parts |
| image_picker_for_web | 3.1.1 | BSD-3-Clause |
| image_picker_ios | 0.8.13+9 | BSD-3-Clause, with Apache-2.0 parts |
| image_picker_linux | 0.2.2 | BSD-3-Clause |
| image_picker_macos | 0.2.2+1 | BSD-3-Clause |
| image_picker_platform_interface | 2.11.1 | BSD-3-Clause |
| image_picker_windows | 0.2.2 | BSD-3-Clause |
| **intl** | 0.20.3 | BSD-3-Clause |
| jni | 1.1.0 | BSD-3-Clause |
| jni_flutter | 1.0.3 | BSD-3-Clause |
| jni_util | 1.0.0 | BSD-3-Clause |
| json_annotation | 4.12.0 | BSD-3-Clause |
| leak_tracker | 11.0.2 | BSD-3-Clause |
| leak_tracker_flutter_testing | 3.0.10 | BSD-3-Clause |
| leak_tracker_testing | 3.0.2 | BSD-3-Clause |
| lints | 6.1.0 | BSD-3-Clause |
| listen | 1.0.1 | BSD-3-Clause |
| logging | 1.3.0 | BSD-3-Clause |
| matcher | 0.12.20 | BSD-3-Clause |
| material_color_utilities | 0.13.0 | Apache-2.0 |
| material_ui | 1.5.0 | BSD-3-Clause |
| meta | 1.19.0 | BSD-3-Clause |
| mime | 2.1.0 | BSD-3-Clause |
| objective_c | 9.6.2 | BSD-3-Clause |
| octo_image | 2.1.2 | MIT |
| package_config | 3.0.0 | BSD-3-Clause |
| passkeys_platform_interface | 2.10.0 | BSD-3-Clause |
| path | 1.9.1 | BSD-3-Clause |
| path_provider | 2.1.6 | BSD-3-Clause |
| path_provider_android | 2.3.1 | BSD-3-Clause |
| path_provider_foundation | 2.6.0 | BSD-3-Clause |
| path_provider_linux | 2.2.2 | BSD-3-Clause |
| path_provider_platform_interface | 2.1.3 | BSD-3-Clause |
| path_provider_windows | 2.3.0 | BSD-3-Clause |
| petitparser | 7.1.0 | MIT |
| platform | 3.2.0 | BSD-3-Clause |
| plugin_platform_interface | 2.1.8 | BSD-3-Clause |
| pointycastle | 4.0.0 | MIT |
| posix | 6.5.2 | MIT |
| postgrest | 2.9.1 | MIT |
| pub_semver | 2.2.1 | BSD-3-Clause |
| qr | 3.0.2 | BSD-3-Clause |
| **qr_flutter** | 4.1.0 | BSD-3-Clause |
| realtime_client | 2.13.2 | MIT |
| record_use | 1.1.1 | BSD-3-Clause |
| riverpod | 3.5.0 | MIT |
| rxdart | 0.28.0 | Apache-2.0 |
| **share_plus** | 13.3.1 | BSD-3-Clause |
| share_plus_platform_interface | 7.2.0 | BSD-3-Clause |
| **shared_preferences** | 2.5.6 | BSD-3-Clause |
| shared_preferences_android | 2.4.28 | BSD-3-Clause |
| shared_preferences_foundation | 2.5.7 | BSD-3-Clause |
| shared_preferences_linux | 2.4.1 | BSD-3-Clause |
| shared_preferences_platform_interface | 2.4.2 | BSD-3-Clause |
| shared_preferences_web | 2.4.3 | BSD-3-Clause |
| shared_preferences_windows | 2.4.1 | BSD-3-Clause |
| source_span | 1.10.2 | BSD-3-Clause |
| sqflite | 2.4.4 | BSD-2-Clause |
| sqflite_android | 2.4.4 | BSD-2-Clause |
| sqflite_common | 2.5.13 | BSD-2-Clause |
| sqflite_darwin | 2.4.4 | BSD-2-Clause |
| sqflite_platform_interface | 2.4.2 | BSD-2-Clause |
| stack_trace | 1.12.2 | BSD-3-Clause |
| state_notifier | 1.0.0 | MIT |
| storage_client | 2.8.1 | MIT |
| stream_channel | 2.1.4 | BSD-3-Clause |
| string_scanner | 1.4.1 | BSD-3-Clause |
| supabase | 2.16.5 | MIT |
| supabase_common | 0.1.2 | MIT |
| **supabase_flutter** | 2.18.3 | MIT |
| synchronized | 3.4.2 | MIT |
| term_glyph | 1.2.2 | BSD-3-Clause |
| test_api | 0.7.14 | BSD-3-Clause (Dart SDK package) |
| typed_data | 1.4.0 | BSD-3-Clause |
| universal_io | 2.3.1 | Apache-2.0 |
| **url_launcher** | 6.3.3 | BSD-3-Clause |
| url_launcher_android | 6.3.33 | BSD-3-Clause |
| url_launcher_ios | 6.4.2 | BSD-3-Clause |
| url_launcher_linux | 3.2.3 | BSD-3-Clause |
| url_launcher_macos | 3.2.6 | BSD-3-Clause |
| url_launcher_platform_interface | 2.3.2 | BSD-3-Clause |
| url_launcher_web | 2.4.3 | BSD-3-Clause |
| url_launcher_windows | 3.1.6 | BSD-3-Clause |
| uuid | 4.6.0 | MIT |
| vector_math | 2.4.3 | BSD-3-Clause |
| vm_service | 15.3.0 | BSD-3-Clause |
| **web** | 1.1.2 | BSD-3-Clause |
| web_socket | 1.0.1 | BSD-3-Clause |
| web_socket_channel | 3.0.3 | BSD-3-Clause |
| win32 | 6.4.0 | BSD-3-Clause |
| xdg_directories | 1.1.0 | BSD-3-Clause |
| xml | 7.1.0 | MIT |
| yaml | 3.1.4 | MIT |
| yet_another_json_isolate | 2.1.1 | MIT |

The Flutter SDK itself is BSD-3-Clause.

# Original DevBox dark palettes

These are byte-for-byte copies of the three custom palettes before their replacement with Catppuccin Mocha, Tokyo Night and Dracula. Snapshot source: `d4c9847eb3e` (the version used for DevBox .35). Forest and the four light themes are unchanged.

| Original name | Replacement |
| --- | --- |
| DevBox Charcoal | DevBox Mocha |
| DevBox Cinder | DevBox Tokyo Night |
| DevBox Cobalt | DevBox Dracula |

The files here are an archive; the application does not load them. The identically named resources under `Resources/devbox-themes` are compatibility names for the **new** palettes.

## Preview an original without changing the application

Copy the desired file into Ghostty's user themes directory under a distinct name such as `DevBox Original Charcoal`, then select that name using `cmux themes set`. The different name avoids colliding with the compatibility resources. The full foreground, background, cursor, selection and 16 ANSI colors are preserved here.

## Restore the original sidebar choices in a future build

Copy all three archived files back over their namesakes in `Resources/devbox-themes`. In `DevBoxThemeSwitcher.themes`, restore the original names, backgrounds and accents from the archived files (the accent used the cursor color), and remove those names from `legacyThemeNames`. Keep new themes available as separate resources if desired. Build using `scripts/build-devbox.sh` and verify switching and selection before release.

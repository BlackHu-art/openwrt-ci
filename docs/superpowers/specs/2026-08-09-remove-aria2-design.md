# Remove Aria2 Design

## Goal

Remove Aria2 from firmware images and standalone SDK package builds. No supported build path should select, replace, compile, publish, or advertise `aria2`, `ariang`, or `luci-app-aria2`.

## Scope

- Remove Aria2, AriaNg, LuCI Aria2, and Aria2 feature selections from `JDCloud.config`, `x86-64.config`, and `Packages.config`.
- Stop `Roc-script.sh` from deleting or replacing the built-in Aria2 and AriaNg feed directories.
- Remove Aria2 aliases, custom feed loading, compile targets, artifact grouping, and artifact filters from `SDK-script.sh`.
- Remove `luci-app-aria2` from the `Build-Packages` workflow input choices.
- Remove Aria2-specific standalone-package documentation from `README.md`.
- Change the existing Roc script integration regression test to verify that the script preserves the built-in Aria2 and AriaNg feed directories rather than restoring custom copies.

## Behavior

Firmware configuration generation will not request `luci-app-aria2`, so APK root installation will not require the absent `aria2` and `ariang` packages. The standalone package workflow will reject old Aria2 selections instead of silently accepting a removed option. Other package selections and custom feed replacements remain unchanged.

## Verification

- Run the Roc script integration test and confirm the built-in Aria2 and AriaNg directories survive.
- Run Bash syntax checks for both shell scripts and the integration test.
- Parse the GitHub Actions workflow as YAML when a YAML parser is available.
- Search the supported build configuration, scripts, workflow, and README for residual Aria2 references.
- Run `git diff --check` and inspect the final diff.

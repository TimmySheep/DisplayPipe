#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
mkdir -p .build
xcrun swiftc GUI/Localization.swift GUI/DiagnosticCore.swift GUI/Presentation.swift GUI/CoreTests.swift -o .build/gui-tests
.build/gui-tests
xcrun swiftc -swift-version 5 GUI/Localization.swift GUI/DiagnosticCore.swift GUI/Presentation.swift GUI/RecoveryPresentation.swift GUI/RecoveryClient.swift GUI/RecoveryTests.swift -o .build/recovery-ui-tests
.build/recovery-ui-tests
# Native view hierarchy only: no live collector, setter, window activation or event loop.
xcrun swiftc -D UI_TESTING -swift-version 5 -framework AppKit -framework CoreGraphics GUI/Localization.swift GUI/DiagnosticCore.swift GUI/Presentation.swift GUI/Diagnostics.swift GUI/RecoveryPresentation.swift GUI/RecoveryClient.swift GUI/App.swift GUI/CompactUITests.swift -o .build/compact-ui-tests
.build/compact-ui-tests
/usr/bin/python3 -B scripts/test-diagnostics-scope.py -v

xcrun swiftc -D UI_TESTING -swift-version 5 -framework AppKit -framework CoreGraphics GUI/Localization.swift GUI/DiagnosticCore.swift GUI/Presentation.swift GUI/Diagnostics.swift GUI/RecoveryPresentation.swift GUI/RecoveryClient.swift GUI/App.swift GUI/LocalizationTests.swift -o .build/localization-tests
.build/localization-tests

# Isolated UserDefaults suites; fail-only collector/backend, never the user’s app preferences.
xcrun swiftc -D UI_TESTING -swift-version 5 -framework AppKit -framework CoreGraphics GUI/Localization.swift GUI/DiagnosticCore.swift GUI/Presentation.swift GUI/Diagnostics.swift GUI/RecoveryPresentation.swift GUI/RecoveryClient.swift GUI/App.swift GUI/PreferenceTests.swift -o .build/preference-tests
.build/preference-tests

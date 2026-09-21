# health (local override)

Vendored from pub.dev `health` 13.3.2 with Android Gradle changes for AGP 9 built-in Kotlin:

- Removed `apply plugin: 'kotlin-android'` (required; Flutter detects KGP by regex)
- Migrated to `kotlin { compilerOptions { jvmTarget = JVM_17 } }`
- Java 17 compile options

Remove this override when upstream publishes a Built-in Kotlin release, and switch back to `health: ^13.3.2` on pub.dev.

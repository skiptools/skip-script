// Include the generated gradle projects after the
// Skip build plugin transpiles the Swift to Kotlin 
gradle.settingsEvaluated {
    exec { commandLine("swift", "build", "--build-tests") }
    //apply(".build/checkouts/skip/local.gradle.kts")

    // perform the transpilation
    apply(from = ".build/plugins/outputs/skip-unit/SkipUnit/skipstone/gradle/skip.gradle.kts")
}


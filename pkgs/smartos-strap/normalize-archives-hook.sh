# The archives of the output without times and owners (./normalize-archives.pl), after the install. A setup hook,
# so that a package given it twice (a strap package's extra build is that package with strap = false) runs it once.
normalizeArchives() {
    @perl@ @script@ "$out"
}
postInstallHooks+=(normalizeArchives)

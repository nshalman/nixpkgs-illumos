# The zip archives of the output (jars, jmods, zips) without times and owners (./normalize-zips.pl), after the
# install.
normalizeZips() {
    @perl@ @script@ "$out"
}
postInstallHooks+=(normalizeZips)

# The sources pinned by data, by name: sources.json says where each comes from and what to follow (owner, repo,
# branch), pins.json what it is pinned to (rev, hash: the NAR hash of GitHub's archive of rev, as fetchFromGitHub and
# fetchTarball check; date: rev's commit time; submodules, by path: url, rev and hash likewise). update.sh rewrites
# pins.json from the branches; changing a branch in sources.json and updating builds from another.
#
# Each is the merge of the two, with url (the repository) and archive (GitHub's tarball of rev); a submodule on
# GitHub has its archive too.
let
  sources = builtins.fromJSON (builtins.readFile ./sources.json);
  pins = builtins.fromJSON (builtins.readFile ./pins.json);
  githubArchive =
    sub:
    let
      repo = builtins.match "https://github.com/(.+)\\.git" sub.url;
    in
    if repo == null then
      { }
    else
      { archive = "https://github.com/${builtins.head repo}/archive/${sub.rev}.tar.gz"; };
in
builtins.mapAttrs (
  name: source:
  let
    pin = pins.${name} or (throw "pins.json has no pin for ${name}; run pins/update.sh ${name}");
  in
  source
  // pin
  // {
    url = "https://github.com/${source.owner}/${source.repo}.git";
    archive = "https://github.com/${source.owner}/${source.repo}/archive/${pin.rev}.tar.gz";
    submodules = builtins.mapAttrs (_: sub: sub // githubArchive sub) (pin.submodules or { });
  }
) sources

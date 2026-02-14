{ config, lib, ... }:
let
  inherit (lib)
    mkEnableOption
    mkIf
    mkDefault
    mkMerge
    mapAttrs
    mapAttrs'
    filterAttrs
    hasPrefix
    removePrefix
    stringLength
    attrNames
    filter
    head
    ;

  metadata = import ./service-metadata.nix;

  knownServiceNames = attrNames metadata;

  containers =
    config.virtualisation.quadlet.containers or config.virtualisation.oci-containers.containers or { };

  findServiceMatch =
    containerName:
    let
      matches = filter (sn: hasPrefix sn containerName) knownServiceNames;
      # Prefer longest match (most specific)
      sorted = lib.sort (a: b: stringLength a > stringLength b) matches;
    in
    if sorted != [ ] then head sorted else null;

  getSuffix =
    containerName: serviceName:
    let
      raw = removePrefix serviceName containerName;
      suffix = removePrefix "-" raw;
    in
    if suffix == "" then null else suffix;

  containersWithMatch = mapAttrs (name: container: {
    inherit container;
    serviceName = findServiceMatch name;
    suffix =
      let
        sn = findServiceMatch name;
      in
      if sn != null then getSuffix name sn else null;
  }) containers;

  directMatches = filterAttrs (_: v: v.serviceName != null && v.suffix == null) containersWithMatch;
  subComponentMatches = filterAttrs (
    _: v: v.serviceName != null && v.suffix != null
  ) containersWithMatch;
  unknownContainers = filterAttrs (_: v: v.serviceName == null) containersWithMatch;
in
{
  options.topology.extractors.quadlet-container.enable =
    mkEnableOption "topology quadlet-container extractor"
    // {
      default = true;
    };

  config.topology.self.services = mkIf config.topology.extractors.quadlet.enable (mkMerge [
    # Direct match: reuse existing service, just add container info
    (mapAttrs' (containerName: v: {
      name = v.serviceName;
      value = {
        inherit (metadata.${v.serviceName}) name image;
        details.container.text = v.container.image or containerName;
      };
    }) directMatches)

    # Sub-component: inherit parent icon/name, append suffix
    (mapAttrs' (containerName: v: {
      name = containerName;
      value = {
        name = "${metadata.${v.serviceName}.name or v.serviceName} (${v.suffix})";
        icon = metadata.${v.serviceName}.icon or "services.docker";
        details.container.text = v.container.image or containerName;
        details.role.text = v.suffix;
      };
    }) subComponentMatches)

    # No match: generic container entry
    (mapAttrs' (containerName: v: {
      name = containerName;
      value = {
        name = mkDefault containerName;
        icon = mkDefault "services.docker";
        details.container.text = v.container.image or containerName;
      };
    }) unknownContainers)
  ]);
}

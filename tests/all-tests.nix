{
  pkgs ? <nixpkgs>,
  system ? builtins.currentSystem
}:
let
  nixpkgs = import pkgs {};
  lib = nixpkgs.lib;

  distributions = import ./distributions.nix;

  makeSingleTest = name:
    import (./suite + "/${name}.nix") { inherit pkgs system; };

  makeTemplateTest = { template, instances }:
    map (args:
      let
        t = import (./suite + "/${template}.nix") { templateArgs = args; inherit pkgs system; };
      in {
        name = "${template}@${t.instance}";
        value = {
          type = "template";
          template = template;
          args = args;
          test = t;
        };
      }
    ) instances;

  makeTest = v:
    if builtins.isAttrs v then
      makeTemplateTest v
    else
      {
        name = v;
        value = {
          type = "single";
          test = (makeSingleTest v);
        };
      };

  tests = list: builtins.listToAttrs (lib.flatten (map makeTest list));
in tests [
  "boot"
  { template = "cgroups/mounts"; instances = distributions; }
  "cgroups/system-v1"
  "cgroups/system-v2"
  "ctstartmenu/setup"
  { template = "dist-config/netif-routed"; instances = distributions; }
  { template = "dist-config/start-stop"; instances = distributions; }
  "docker/almalinux-8"
  "docker/alpine-latest"
  "docker/centos-7"
  "docker/debian-latest"
  "docker/fedora-latest"
  "docker/ubuntu-18.04"
  "docker/ubuntu-20.04"
  "driver"
  "lxcfs/loadavgs"
  { template = "lxcfs/overlays"; instances = distributions; }
  "osctl/ct-exec"
  "osctl/ct-runscript"
  "osctl-exportfs/mount"
  "zfs/ugidmap"
  "zfs/xattr"
]

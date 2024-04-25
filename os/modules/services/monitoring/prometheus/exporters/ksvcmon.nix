{ config, lib, pkgs, options }:

with lib;

let
  cfg = config.services.prometheus.exporters.ksvcmon;
in {
  user = "root";
  group = "root";
  port = 9299;

  serviceRun = with cfg; concatStringsSep " " ([
      "execExporter"
      "${pkgs.ksvcmon}/bin/ksvcmon"
      "-h ${listenAddress} -p ${toString port}"
    ] ++ extraFlags);
}

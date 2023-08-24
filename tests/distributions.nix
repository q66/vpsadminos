{ lib }:
let
  table = {
    almalinux_8      = { distribution = "almalinux"; version = "8";               };
    alpine           = { distribution = "alpine";    version = "latest";          };
    arch             = { distribution = "arch";      version = "latest";          };
    centos_7         = { distribution = "centos";    version = "7";               };
    centos_8_stream  = { distribution = "centos";    version = "latest-8-stream"; };
    centos_9_stream  = { distribution = "centos";    version = "latest-9-stream"; };
    debian_11        = { distribution = "debian";    version = "11";              };
    debian_12        = { distribution = "debian";    version = "12";              };
    debian_testing   = { distribution = "debian";    version = "testing";         };
    fedora           = { distribution = "fedora";    version = "latest";          };
    gentoo_openrc    = { distribution = "gentoo";    version = "latest-openrc";   };
    gentoo_systemd   = { distribution = "gentoo";    version = "latest-systemd";  };
    gentoo_musl      = { distribution = "gentoo";    version = "latest-musl";     };
    nixos_stable     = { distribution = "nixos";     version = "stable";          };
    nixos_unstable   = { distribution = "nixos";     version = "unstable";        };
    opensuse         = { distribution = "opensuse";  version = "latest";          };
    slackware        = { distribution = "slackware"; version = "latest";          };
    ubuntu_1804      = { distribution = "ubuntu";    version = "18.04";           };
    ubuntu_2004      = { distribution = "ubuntu";    version = "20.04";           };
    ubuntu_2204      = { distribution = "ubuntu";    version = "22.04";           };
    void_glibc       = { distribution = "void";      version = "latest-glibc";    };
    void_musl        = { distribution = "void";      version = "latest-musl";     };
  };
in {
  cgroupv2 = with table; [
    almalinux_8
    alpine
    arch
    centos_8_stream
    centos_9_stream
    debian_11
    debian_12
    debian_testing
    fedora
    gentoo_systemd
    nixos_stable
    nixos_unstable
    opensuse
    slackware
    ubuntu_1804
    ubuntu_2004
    ubuntu_2204
    void_glibc
    void_musl
  ];

  cgroupv1 = with table; [
    centos_7
  ];

  systemd = with table; [
    almalinux_8
    arch
    centos_7
    centos_8_stream
    centos_9_stream
    debian_11
    debian_12
    debian_testing
    fedora
    gentoo_systemd
    nixos_stable
    nixos_unstable
    opensuse
    ubuntu_1804
    ubuntu_2004
    ubuntu_2204
  ];

  non-systemd = with table; [
    alpine
    gentoo_openrc
    gentoo_musl
    slackware
    void_glibc
    void_musl
  ];

  all = lib.mapAttrsToList (k: v: v) table;
}

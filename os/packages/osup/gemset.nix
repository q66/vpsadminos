{
  gli = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "1sxpixpkbwi0g1lp9nv08hb4hw9g563zwxqfxd3nqp9c1ymcv5h3";
      type = "gem";
    };
    version = "2.20.1";
  };
  json = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0r9jmjhg2ly3l736flk7r2al47b5c8cayh0gqkq0yhjqzc9a6zhq";
      type = "gem";
    };
    version = "2.7.1";
  };
  libosctl = {
    dependencies = ["rainbow" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0bd8vybnq6a8ar8160dks93sv2fpqfwg5gqq57jljklh9fcr4b6m";
      type = "gem";
    };
    version = "23.11.0.build20240306185636";
  };
  osup = {
    dependencies = ["gli" "json" "libosctl" "require_all"];
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.vpsfree.cz"];
      sha256 = "0szhzgw7x8vakf1k7g06f6air0bwnq4sb0j73cqgx5hyhly1kxbm";
      type = "gem";
    };
    version = "23.11.0.build20240306185636";
  };
  rainbow = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0smwg4mii0fm38pyb5fddbmrdpifwv22zv3d3px2xx497am93503";
      type = "gem";
    };
    version = "3.1.1";
  };
  require_all = {
    groups = ["default"];
    platforms = [];
    source = {
      remotes = ["https://rubygems.org"];
      sha256 = "0sjf2vigdg4wq7z0xlw14zyhcz4992s05wgr2s58kjgin12bkmv8";
      type = "gem";
    };
    version = "2.0.0";
  };
}

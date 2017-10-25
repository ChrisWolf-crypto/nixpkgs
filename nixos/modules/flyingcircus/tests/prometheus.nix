import ../../../tests/make-test.nix ({lib, pkgs, ... }:
{
  name = "prometheus";
  machine =
    { config, ... }:
    {
      imports = [
        ./setup.nix
        ../platform
        ../services
        ../static
      ];

      config.services.prometheus.enable = true;
    };
  testScript =
    ''
      $machine->waitForUnit("prometheus.service");
      $machine->sleep(5);
      $machine->succeed("curl 'localhost:9090/metrics' | grep go_goroutines");
    '';
})

{ pkgs, ... }:

let
  inherit (pkgs) epnixLib;
  inherit (pkgs.stdenv.hostPlatform) system;

  mock_server = pkgs.poetry2nix.mkPoetryApplication {
    projectDir = ./mock-server;
  };

  ioc = epnixLib.mkEpnixBuild system {
    imports = [ (epnixLib.importTOML ./top/epnix.toml) ];
  };
in
pkgs.nixosTest {
  name = "support-StreamDevice-simple";
  meta.maintainers = with epnixLib.maintainers; [ minijackson ];

  machine =
    let
      listenAddr = "127.0.0.1:1234";
    in
    {
      environment.systemPackages = [ pkgs.epnix.epics-base ];

      systemd.sockets.mock-server = {
        wantedBy = [ "multi-user.target" ];
        listenStreams = [ listenAddr ];
        socketConfig.Accept = true;
      };

      systemd.services = {
        "mock-server@".serviceConfig = {
          ExecStart = "${mock_server}/bin/mock_server";
          StandardInput = "socket";
          StandardError = "journal";
        };

        ioc = {
          wantedBy = [ "multi-user.target" ];

          environment.STREAM_PS1 = listenAddr;

          serviceConfig = {
            ExecStart = "${ioc}/iocBoot/iocsimple/st.cmd";
            WorkingDirectory = "${ioc}/iocBoot/iocsimple";
            # TODO: this is hacky, find a way to have EPICS keep going without
            # a shell
            StandardInputText = "epicsThreadSleep(100)";
          };
        };
      };
    };

  testScript = ''
    import time

    start_all()

    machine.wait_for_unit("default.target")
    machine.wait_for_unit("ioc.service")

    # TODO: this is a HACK to ensure EPICS is started
    time.sleep(5)

    with subtest("getting fixed values"):
      assert "42.1234" == machine.succeed("caget -t FLOAT:IN").strip()
      assert "69.1337" == machine.succeed("caget -t FLOAT_WITH_PREFIX:IN").strip()
      assert "1" == machine.succeed("caget -t ENUM:IN").strip()

    with subtest("setting values"):
      assert "0" == machine.succeed("caget -t VARFLOAT:IN").strip()
      machine.succeed("caput VARFLOAT:OUT 123.456").strip()
      time.sleep(0.2)
      assert "123.456" == machine.succeed("caget -t VARFLOAT:IN").strip()

    with subtest("calc integration"):
      assert "10A" == machine.succeed("caget -t SCALC:IN").strip()
      machine.succeed("caput SCALC:OUT.A 2")
      assert "14A" == machine.succeed("caget -t SCALC:IN").strip()
      assert "sent" == machine.succeed("caget -t SCALC:OUT.SVAL").strip()

    with subtest("regular expressions"):
      assert "Hello, World!" == machine.succeed("caget -t REGEX_TITLE:IN").strip()
      assert "abcXcXcabc" == machine.succeed("caget -t REGEX_SUB:IN").strip()
  '';

  passthru = {
    inherit mock_server ioc;
  };
}
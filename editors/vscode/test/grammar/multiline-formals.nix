{
  lib,
  stdenv,
  fetchurl ? null,
  ...
}:

stdenv.mkDerivation rec {
  pname = "hello";
  version = "2.12";
  src = fetchurl {
    url = "mirror://gnu/hello/${pname}-${version}.tar.gz";
    hash = "sha256-AAAA";
  };
  buildPhase = ''
    make -j$NIX_BUILD_CORES
  '';
  meta = with lib; {
    description = "A program that produces a familiar, friendly greeting";
    platforms = platforms.all;
  };
}

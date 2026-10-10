# Third-party components

`docker-mql-compiler`'s own code (the compile script, the command, the installer, the tests) is WTFPL, see [LICENSE](LICENSE).

The image is built from Debian packages. The ones it exists for:

| Component | SPDX license | Source | Where it lives |
|---|---|---|---|
| [Wine](https://www.winehq.org) | LGPL-2.1-or-later | Debian `wine`, `wine64`, `wine32:i386` | the image |
| [Xvfb](https://www.x.org) | MIT | Debian `xvfb` | the image |
| [osslsigncode](https://github.com/mtrojnar/osslsigncode) | GPL-3.0-or-later | Debian `osslsigncode` | the image |
| [jq](https://jqlang.org) | MIT | Debian `jq` | the image |
| [inotify-tools](https://github.com/inotify-tools/inotify-tools) | GPL-2.0-or-later | Debian `inotify-tools` | the image |
| [actions/cache](https://github.com/actions/cache) | MIT | GitHub, pinned by commit in `action.yml` | the GitHub Action, at run time |

Their corresponding source is available from Debian (`apt-get source <package>`).

## MetaQuotes software

MetaTrader 4, MetaTrader 5 and MetaEditor are proprietary MetaQuotes software. They are not in this repository and not in the published image. On the first run the image downloads the broker's installers (RoboForex's by default, or the URLs in `MQL_COMPILER_MT4_URL` and `MQL_COMPILER_MT5_URL`), checks that MetaQuotes signed them, and installs them into the user's own cache volume. Their use is governed by MetaQuotes' license terms.

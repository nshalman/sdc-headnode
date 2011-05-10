{
    "platform-release": "develop"
  , "use-proxy": "false"
  , "build-tgz": "true"
  , "build-hvm": "false"
  , "hvm-agents": "https://guest:GrojhykMid@216.57.203.66:444/coal/hvm/agents-hvm-20110504T125643Z.sh"
  , "hvm-platform": "https://guest:GrojhykMid@216.57.203.66:444/coal/hvm/platform-HVM-20110504T125644Z.tgz"
  , "agents-shar": "develop"
  , "datasets": [
      { "name": "smartos-1.3.12"
      , "uuid": "febaa412-6417-11e0-bc56-535d219f2590"
      , "headnode_zones": "true"
      }
    , { "name": "nodejs-1.1.4"
      , "uuid": "41da9c2e-7175-11e0-bb9f-536983f41cd8"
      }
    , { "name": "ubuntu-10.04.2.1"
      , "uuid": "b66fb52a-6a8a-11e0-94cd-b347300c5a06"
      }
  ]
  , "adminui-checkout": "origin/develop"
  , "atropos-tarball": "^atropos-develop-.*.tar.bz2$"
  , "ca-tarball": "^ca-pkg-master-.*.tar.bz2$"
  , "capi-checkout": "origin/develop"
  , "dhcpd-checkout": "origin/develop"
  , "mapi-checkout": "origin/develop"
  , "portal-checkout": "origin/develop"
  , "cloudapi-checkout": "origin/develop"
  , "pubapi-checkout": "origin/develop"
  , "rabbitmq-checkout": "origin/develop"
  , "upgrades": {
      "agents": [
          "atropos/develop/atropos-develop-*"
        , "cloud_analytics/master/cabase-master-*"
        , "cloud_analytics/master/cainstsvc-master-*"
        , "dataset_manager/develop/dataset_manager-develop-*"
        , "heartbeater/develop/heartbeater-develop-*"
        , "provisioner/develop/provisioner-develop-*"
        , "smartlogin/develop/smartlogin-develop-*"
        , "zonetracker/develop/zonetracker-develop-*"
      ]
    , "appzones": [
          "adminui"
        , "capi"
        , "dnsapi"
        , "mapi"
        , "pubapi"
      ]
  }
}

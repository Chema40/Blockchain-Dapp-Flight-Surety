const HDWalletProvider = require("@truffle/hdwallet-provider");
var mnemonic = "napkin miracle history jungle old dial outside south stove rice envelope water";

module.exports = {
  networks: {
    development: {
      provider: function() {
        return new HDWalletProvider(mnemonic,"http://127.0.0.1:7545/", 0, 30);
      },
      network_id: "*", // Match any network id
    },
  },
  compilers: {
    solc: {
      version: ">=0.4.24"
    }
  }
};
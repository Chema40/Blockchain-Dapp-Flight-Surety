const HDWalletProvider = require("@truffle/hdwallet-provider");
var mnemonic = "chalk topic wink nerve pilot hub attend much pen girl solid fortune";

module.exports = {
  networks: {
    development: {
      provider: function() {
        return new HDWalletProvider(mnemonic,"http://127.0.0.1:7545/", 0, 9);
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
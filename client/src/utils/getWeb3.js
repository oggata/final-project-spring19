// import Portis from '@portis/web3';
import Web3 from 'web3';

const FALLBACK_WEB3_PROVIDER = process.env.REACT_APP_NETWORK || 'http://0.0.0.0:8545';
const PORTIS_APP_ID = process.env.PORTIS_APP_ID || '53689f2e-5ed0-4fb2-a54d-397358c49fc0';

const walletConnectProviderOpts = {
  portis: {
    id: PORTIS_APP_ID,
    network: 'rinkeby',
    // network: 'ropsten',
    // network: {
    //   nodeUrl: 'http://localhost:8545',
    //   chainId: 1565816938766,
    //   gasRelayHubAddress: '0x9C57C0F1965D225951FE1B2618C92Eefd687654F',
    // },
    config: {
      gasRelay: true,
    },
  },
  disableWalletConnect: true,
};

const web3Networks = {
  '1': {
    name: 'mainnet',
    explorerTx: 'https://etherscan.io/tx',
    explorerAddress: 'https://etherscan.io/address/',
  },
  '3': {
    name: 'ropsten',
    explorerTx: 'https://ropsten.etherscan.io/tx/',
    explorerAddress: 'https://ropsten.etherscan.io/address/',
  },
  '4': {
    name: 'rinkeby',
    explorerTx: 'https://rinkeby.etherscan.io/tx/',
    explorerAddress: 'https://rinkeby.etherscan.io/address/',
  },
  '5': {
    name: 'goerli',
    explorerTx: 'https://blockscout.com/eth/goerli/tx/',
    explorerAddress: 'https://blockscout.com/eth/goerli/address/',
  },
  '42': {
    name: 'kovan',
    explorerTx: 'https://blockscout.com/eth/kovan/tx/',
    explorerAddress: 'https://blockscout.com/eth/kovan/address/',
  },
};

const walletConnect = provider =>
  new Promise((resolve, reject) => {
    try {
      const web3 = new Web3(provider);
      resolve(web3);
    } catch (error) {
      reject(error);
    }
  });

// const getPortis = network =>
//   new Promise((resolve, reject) => {
//     try {
//       const portis = new Portis(PORTIS_APP_ID, network);
//       resolve(portis);
//     } catch (error) {
//       reject(error);
//     }
//   });

const getWeb3 = () =>
  new Promise((resolve, reject) => {
    // Wait for loading completion to avoid race conditions with web3 injection timing.
    window.addEventListener('load', async () => {
      // Modern dapp browsers...
      if (window.ethereum) {
        const web3 = new Web3(window.ethereum);
        try {
          // Request account access if needed
          await window.ethereum.enable();
          // Acccounts now exposed
          resolve(web3);
        } catch (error) {
          reject(error);
        }
      }
      // Legacy dapp browsers...
      else if (window.web3) {
        // Use Mist/MetaMask's provider.
        const web3 = window.web3;
        console.log('Injected web3 detected.');
        resolve(web3);
      }
      // Fallback to localhost; use dev console port by default...
      else {
        const provider = new Web3.providers.HttpProvider(FALLBACK_WEB3_PROVIDER);
        const web3 = new Web3(provider);
        console.log('No web3 instance injected, using Infura/Local web3.');
        resolve(web3);
      }
    });
  });

const getGanacheWeb3 = () => {
  const isProd = process.env.NODE_ENV === 'production';
  if (isProd) {
    return null;
  }
  const provider = new Web3.providers.HttpProvider('http://0.0.0.0:8545');
  const web3 = new Web3(provider);
  console.log('No local ganache found.');
  return web3;
};

export default getWeb3;
// export { walletConnectProviderOpts, web3Networks, getGanacheWeb3, walletConnect, getPortis };
export { walletConnectProviderOpts, web3Networks, getGanacheWeb3, walletConnect };

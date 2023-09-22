## How To Understand The `developmentContractAddresses/` Folder

The general syntax for each `.json` file is set up to be:

> `<DeployerObject>.<NetworkDeployedOn>.json`

This folder contrasts with the `productionContractAddresses/` folder. `productionContractAddresses` contains addresses of contracts which we have battle-tested and want to designate for production/uat use. These should be committed to source control for the team to have reference to.

The `.json` files in the `productionContractAddresses` folder should not be freely manipulated and they can be manually constructed via copy-pasting new addresses in as we see them via `console.dir` / `console.log`.

The `.json` files in the `developmentContractAddresses` are git-ignored because there's no point sharing them around; they will likely only cause unnecessary merge conflicts. Again, if you want to share the addresses around, doing it manually is the best way.

Unless otherwise required, dev contract addresses should be deployed on Tenderly's `devnets`.

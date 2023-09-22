# jaspervault-v1-core

## Context

The goal of this repo is to integrate Tenderly's tooling as much as possible into our dev-deploy-test-fix process.

Right now, I'd like to be able to verify as many contract deployments as possible.

## Steps

### Install Dependencies

```bash
yarn
```

### Create your own `.env`

See `.env.example` for the variables I'm working with.

### Run the deploy script

```bash
npx hardhat run scripts/deployEverything.js network --devnet
```

What you should see:

1. SetTokenCreator deploys but doesn't verify because of mis-matching bytecode
2. AaveLeverageModule deploys but doesn't verify due to 'internal server error'
3. VaultFactory fails to deploy because of an 'invalid format' error (not quite sure what I'm doing wrongly; seems identical to examples in Tenderly docs)

## Would love help on

Getting the 3 things mentioned above solved.

Thank you guys : )

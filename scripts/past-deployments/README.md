## What the `scripts/past-deployments` folder should be used for

The `past-deployments/` folder is used to archive deployment scripts we used which are unlikely to be re-used in other deployment scripts.

For example, we may write a script that makes use of the `NewIntegration` class from the `deployers/` folder to deploy a new contract adapter for staking in [ApeStake](https://docs.apestake.io/#/). Once the adapter has been deployed and registered with the `IntegrationRegistry`, we won't need that script any more. We can place it in `archive` for future reference/re-use if we need to re-deploy contracts for an ApeStake integration.

The **benefit** of this is that we avoid cluttering the root of the `scripts/` folder, while making it easy for teammates to understand how things have been done in the past.

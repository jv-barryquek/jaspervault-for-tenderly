## How `networkSpecificAddresses/`'s files can be used

The contents of this folder were largely inspired by the `settingInfo.py` file in 王志's SDK (I received a copy sometime late August 2023).

<!-- todo: remove the above para if no longer relevant -->

The idea is export key-value pairs for the various external contracts/entities that we require either addresses or urls for. For example, we export the address of the `EntryPoint` contract on Mainnet, which is different from the the address of the `EntryPoint` on Polygon.

These will be used in our `scripts/`, `sdk/`, and our `test/` files, so we place this folder in the root of the project.

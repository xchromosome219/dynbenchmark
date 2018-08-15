
Synthetic datasets
------------------

Each synthetic dataset is based on some characteristics of some real datasets. These characteristics include:

-   The number of cells and features
-   The number of features which are differentially expressed in the trajectory
-   Estimates of the distribution of the library sizes, average expression, dropout probabilities, ... estimated by [Splatter](https://github.com/Oshlack/splatter)

These are estimated in [01-estimate\_platform.R](01-estimate_platform.R) and are called "platforms".

Next, we simulate datasets using different simulators:

-   [Dyngen](https://github.com/dynverse/dyngen), simulations of regulatory networks which will produce a particular trajectory
-   [PROSSTT](https://github.com/soedinglab/prosstt), simulations of tree topologies using random walks
-   [Splatter](https://github.com/Oshlack/splatter), simulations of non-linear paths between different states
-   [Dynplot](https://github.com/dynverse/dynplot), simulations of toy data using random expression gradients in a reduced space

Each simulation script (02a-02d) first creates a design dataframe, which links particular platforms, different topologies, seeds and other parameters specific for a simulator.

The data is then simulated using wrappers around the simulators (see [/package/R/simulators.R](/package/R/simulators.R)), so that they all return datasets in a format consistent with dynwrap.
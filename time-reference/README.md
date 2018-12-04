
A few small examples to demonstrate the usefulness of having a
time reference in P4 programs.

Primitives:
* sum of samples over a sliding window
* average of samples over a sliding window
* token buckets
* decaying counter
* periodic reset

Also see:
* [Adaptive GSP prototype](/AQM/GSP/adaptive-gsp-prototype.p4) which
  needs to track the amount of time that the queue size spends
  above and below some threshold value
* [AFD prototype](https://github.com/PIFO-TM/ns3-bmv2/blob/master/traffic-control/examples/p4-src/afd/afd.p4)
  which needs to periodically sample queue size to update some state.


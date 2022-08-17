# Kata Containers network metrics

Kata Containers provides a series of network performance tests. Running these provides
a basic reference for measuring  network essentials like bandwidth, jitter, latency and
parallel bandwidth.

## Performance tools

- `iperf3` measures bandwidth and the quality of a network link.
- `ping` is the simplest command to test basic connectivity testing.

## Networking tests

- `k8s-network-metrics-iperf3.sh` measures bandwidth which is the speed of the data transfer.
- `latency-network.sh` measures network latency.

## Running the tests

Individual tests can be run by hand, for example:

```
$ cd metrics
$ bash network/iperf3_kubernetes/k8s-network-metrics-iperf3.sh -b
```

## Expected results

In order to obtain repeatable and stable results it is necessary to run the
tests multiple times (at least 15 times to have standard deviation < 3%).

> **NOTE** Networking tests results can vary between platforms and OS
> distributions.

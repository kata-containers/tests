# Kata Containers Iperf3 and Nuttcp network metrics

Currently, Kata Containers have a series of network performance tests. Use
the tests as a basic reference to measure network essentials like bandwidth,
jitter, packet per second throughput and latency.

## Performance tools

- Iperf3 measures bandwidth and the quality of a network link.

- Nuttcp determines the raw UDP layer throughput.

## Networking tests

- `network-metrics-iperf3.sh` measures bandwidth, jitter, bidirectional bandwidth,
and packet-per-second throughput using iperf3 on single threaded connections. The
bandwidth test shows the speed of the data transfer. The jitter test measures the
variation in the delay of received packets. The packet-per-second tests show the
maximum number of (smallest sized) packets allowed through the transports.

- `network-metrics-nuttcp.sh` measures the UDP bandwidth using nuttcp. This tool
shows the speed of the data transfer for the UDP protocol.
 
## Running the tests

Individual tests run by hand, for example:

```
$ cd metrics
$ bash network/network-metrics-nuttp.sh

```

## Expected results

In order to obtain repeteable and stable results is necessary to run the
tests multiple times (at least 15 times to have standard deviation < 3%).

> **NOTE** Networking tests results can vary between platforms and OS
> distributions.

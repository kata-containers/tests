# Overhead calculation test

Kata uses VMs to sandbox a set of containers. The additional components used by
Kata add an extra overhead on CPU or memory.

These scripts run a set of workloads where it is expected and extra CPU usage
due to network or IO operations.

- network: `tttcp`
- IO : `fio`
- web server: `nginx` + `apache ab`

To collect the overhead information of the workloads, run the next command on a
`kubernetes` cluster.

```
$./run-all.sh
```

To add a new workload add a directory with a prefix `test_`. The directory must
provide the following structure:

```
/test_<workload-name>/
|-- check_before_get_overhead.sh (optional)
`-- workloads.yaml
```


- `workloads.yaml`

Must provide a pod with the label `app=overhead`. That pod  will be used to
collect its overhead.

- `check_before_get_overhead.sh` optional.

If the script exists, it will be called and will wait until is considered OK to
start collecting the overhead data.

# Cost Optimization

## Strategy by environment

| Lever | dev | stage | prod |
|---|---|---|---|
| NAT gateways | 1 shared | 1 shared | 1 per AZ |
| Node capacity type | spot only | on-demand + spot | on-demand + spot |
| Node instance size | `t3.medium` | `m5.large` | `m5.xlarge` |
| Node group min size | 1 | 2 | 3 |

See `product-infrastructure/environments/*/*.tfvars` for the exact current
numbers — this doc explains the *why*, those files are the source of
truth for the *current* values.

## Spot instances (capstone Task 9)

The `spot` node group is tainted (`spot=true:NoSchedule`) so only
workloads with a matching toleration land on it — currently just
`analytics-data-processor` (`product-kubernetes/deployment.yaml`), since
it's re-triggered hourly and tolerates interruption. `analytics-api` /
`analytics-web` stay on the `general` (on-demand) group to protect
interactive-traffic availability.

## Autoscaling (capstone Task 9)

- **Horizontal (pods):** not yet wired up as a `HorizontalPodAutoscaler` —
  replica counts are currently fixed in `product-kubernetes/deployment.yaml`.
  Adding an HPA keyed on CPU or request rate is a natural next step.
- **Vertical (nodes):** each node group's `desired_size` has
  `ignore_changes` in its `lifecycle` block
  (`product-infrastructure/modules/eks-cluster/main.tf`) so the Cluster
  Autoscaler (deployed separately) can scale node count without every
  `terraform apply` fighting it back to the Terraform-defined value.

## Resource rightsizing

Kubernetes `requests`/`limits` are set per-container in
`product-kubernetes/deployment.yaml`. Requests drive bin-packing/cost;
limits are the runaway-process safety net. The CloudWatch alarms in
`product-infrastructure/modules/monitoring-stack`
(`node_cpu_high`, `node_memory_high`) are the trigger for revisiting these
numbers.

## Cost anomaly detection

Not yet automated — recommended next step is enabling
[AWS Cost Anomaly Detection](https://aws.amazon.com/aws-cost-management/aws-cost-anomaly-detection/),
routed to the same SNS topic `modules/monitoring-stack` already creates.

## Trusted Advisor findings (capstone Task 9 expected outcome)

Run through the AWS Trusted Advisor cost-optimization checks (idle
load balancers, low-utilization EC2/RDS, underutilized EBS, Reserved
Instance coverage) against your actual deployed environments and attach
the findings — this is account-specific and can't be pre-filled here.

## Current spend tracking

Placeholder for your AWS Cost Explorer saved report / Athena CUR query or
a monthly spend snapshot once real usage exists.

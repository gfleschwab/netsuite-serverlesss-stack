# NetSuite ETL (AWS Glue)

AWS Glue pipelines that extract NetSuite data through SuiteQL REST and land it in the Snowflake ETL bucket for
Snowpipe. Infrastructure is Terraform, deployed with GitHub Actions, following the same layout as
`salesforce-serverless-stack` and `rc015-aws-stack`.

| Pipeline | Started by | Code |
| --- | --- | --- |
| **FCM310 / FCM311.07 – Customer delta extract** (CHG0032633, replaces the Boomi `CUSTOMERS` driver) | EventBridge Scheduler (FCM310 crons) | `terraform/infrastructure/customer.tf`, `assets/glue-scripts/fcm311-07-netsuite-customer-extract.py` |
| **Historical load – TransactionLine** (Parquet, one `load_date=` folder per run) | By hand: Step Functions `netsuite-etl-<stage>-historical-load` with `{"startDate", "endDate"}` | `terraform/infrastructure/historical-load.tf`, `assets/glue-scripts/netsuite2-historical-load.py`, `handler.js`, `dateGeneratorHandler.js` |

## Architecture

```
FCM310 Customer
  EventBridge Scheduler ──► Step Functions (FCM310) ──► Glue Python shell (FCM311.07) ──► S3 ──► Snowpipe ──► Snowflake
                                    └─ failures ──► EventBridge rule ──► SNS

Historical load
  Step Functions ──► Lambda dateGenerator (chunks) ──► Lambda triggerNetsuiteEtl ──► Glue (Spark) ──► S3 Parquet
```

Both read the NetSuite TBA credentials from the stage's Secrets Manager secret (`<stage>/netsuite/suiteql/secret`,
owned by operations). Operations for the Customer extract — credentials, cutover, validation, replay and rollback —
are in [docs/runbooks/FCM310-FCM311.07-customer.md](docs/runbooks/FCM310-FCM311.07-customer.md).

## Project structure

```
assets/glue-scripts/           Glue scripts, uploaded by Terraform to the stage's netsuite-etl-<stage>-glue-scripts bucket
handler.js, dateGeneratorHandler.js   Historical-load Lambdas (nodejs20.x, ES modules)
terraform/infrastructure/      Root module: main, variables, data-stores, customer, historical-load, outputs
terraform/envs/<stage>.tfvars  dev, qa, preprod, prod
tests/                         Unit tests for the Customer extract script
docs/runbooks/                 Operations
makefile                       Entry point for CI and for running by hand
```

## Stages

| Stage | Account | Snowflake bucket | State bucket |
| --- | --- | --- | --- |
| dev | 319580086754 | `ls-snowflake-dev-etl` | `platform-infra-terraform-state-dev` |
| qa | 319580086754 | `ls-snowflake-qa-etl` | `platform-infra-terraform-state-dev` |
| preprod | 319580086754 | `ls-snowflake-etl-preprod` | `platform-infra-terraform-state-dev` |
| prod | 470439681586 | `ls-snowflake-prod-etl` | `platform-infra-terraform-state-prod` |

The state key is `netsuite-etl/<stage>/terraform.tfstate`. The provider pins each stage to the account id in its
tfvars, so an apply with the wrong credentials fails during plan instead of building a duplicate stack in the wrong
account.

## Deployment

Prerequisites: Terraform 1.10+, Python 3.12 (unit tests), GNU make, AWS credentials for the stage.

```bash
make fmt validate test      # the checks CI runs
make plan STAGE=dev         # see what would change
make apply STAGE=dev        # plan and apply the saved plan
make apply STAGE=prod TFSTATE_BUCKET=platform-infra-terraform-state-prod
```

## CI/CD

Two workflows, both driving the same `make` targets:

| Workflow | Trigger | What it does |
| --- | --- | --- |
| `.github/workflows/pr-checks.yml` | PR into `main` | `make fmt`, `make validate`, `make test`, and a check that every stage tfvars carries an account id and a Snowflake bucket. No AWS credentials. |
| `.github/workflows/deploy.yml` | Manual (`workflow_dispatch`) | Deploys one commit through DEV -> QA -> PREPROD -> PROD as sequential jobs. |

Each deploy job declares a GitHub Environment (`DEV`, `QA`, `PREPROD`, `PROD`); PREPROD and PROD require a reviewer.
Authentication is OIDC (`DEV_DEPLOYMENT_ROLE_ARN`, `PROD_DEPLOYMENT_ROLE_ARN` repository secrets); `platform-infra`
must list this repository in its `repos.yaml`.

Two repository variables gate the rollout:

- `ENABLE_PROMOTION` — leave unset to stop after DEV. Set to `true` when QA should receive deploys.
- `ENABLE_PROD` — prod stays off until prod OIDC access and `PROD_DEPLOYMENT_ROLE_ARN` exist.

### Migration from Serverless / CodePipeline

This repository used to deploy with the Serverless Framework (`netsuite-etl-service-<stage>` CloudFormation stacks)
from a CodePipeline. The Terraform stack uses new resource names (`netsuite-etl-<stage>-*`), so both can coexist
while the migration happens:

1. Deploy the Terraform stack to the stage.
2. Disable the CodePipeline that runs `serverless deploy` for this repository.
3. Delete the old `netsuite-etl-service-<stage>` CloudFormation stack once nobody runs the old historical-load state
   machine (`netsuite`).
4. Add the `push` trigger documented at the top of `deploy.yml`.

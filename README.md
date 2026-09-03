# fdp-infra-serverless

Serverless transaction-decisioning pipeline for FDP.

```
Kinesis stream            Lambda (Python 3.12)             DynamoDB
fdp-<env>-euw2-        ->  fdp-<env>-euw2-txn-processor  ->  fdp-<env>-euw2-
  transactions              sample GOOD/CHALLENGE/BLOCK       transactions
                            rule engine
```

A Kinesis event-source mapping delivers batches of transaction records to the
Lambda. For each record the function decodes the JSON payload, runs the sample
rule engine, and writes a decision row to the pre-existing DynamoDB
`fdp-<env>-euw2-transactions` table. Failed records are returned via
`ReportBatchItemFailures` so Kinesis retries only those.

## Layout

```
.
├── lambda_main.tf                    # root: dev/prod locals + module call
├── providers.tf / backend.tf / versions.tf / outputs.tf
├── src/                              # Lambda sources (packaged & deployed)
│   ├── handler.py                    # Kinesis entry point
│   ├── rules.py                      # sample GOOD/CHALLENGE/BLOCK rule engine
│   └── dynamo.py                     # DynamoDB batch writer
├── scripts/package.sh               # build step: zip src/ -> build/transaction_processor.zip
├── modules/transaction-processor/
│   ├── kinesis.tf  lambda.tf  iam.tf
│   ├── variables.tf  outputs.tf  versions.tf
└── .github/workflows/               # plan / apply / destroy (manual dispatch only)
```

## Sample rules (`src/rules.py`)

Each rule is a pure function; the final decision is the most severe hit.
Thresholds and lists are passed from Terraform as Lambda env vars, so they are
tuned per environment without a code change.

| Rule | Decision | Fires when |
|---|---|---|
| `amount_over_block_threshold` | BLOCK | `amount >= RULE_BLOCK_AMOUNT` (default 10000) |
| `sanctioned_or_blocked_country` | BLOCK | `country` in `RULE_BLOCKED_COUNTRIES` |
| `amount_over_challenge_threshold` | CHALLENGE | `amount >= RULE_CHALLENGE_AMOUNT` (default 2000) |
| `card_not_present_elevated_amount` | CHALLENGE | `card_present == false` and `amount >= half the challenge threshold` |
| `high_risk_merchant_category` | CHALLENGE | `mcc` in `RULE_HIGH_RISK_MCC` |
| `account_velocity_in_batch` | CHALLENGE | more than `RULE_MAX_TXNS_PER_ACCOUNT` records for one account in a batch |
| (none matched) | GOOD | — |

### Expected transaction payload

Kinesis record data is base64-encoded JSON. The handler is lenient about field
names (`id`/`txn_id`/`transaction_id`, `customer_id`/`account_id`, …):

```json
{
  "transaction_id": "txn_01HZY...",
  "account_id": "acct_4823",
  "amount": 4200.00,
  "currency": "GBP",
  "country": "GB",
  "mcc": "5411",
  "card_present": false
}
```

### Decision row written to DynamoDB

```json
{
  "transaction_id": "txn_01HZY...",
  "account_id": "acct_4823",
  "amount": 4200.0,
  "currency": "GBP",
  "country": "GB",
  "decision": "CHALLENGE",
  "reason": "amount 4200.00 >= challenge threshold 2000.00",
  "rules_matched": ["amount_over_challenge_threshold"],
  "kinesis_sequence_number": "4957...",
  "processed_at": "2026-09-02T12:34:56.789+00:00",
  "source": "fdp-transaction-processor"
}
```

The partition-key attribute defaults to `transaction_id`; override with
`table_partition_key` / `table_sort_key` in the root locals if the table uses a
different schema.

## Build & deploy

The Python sources are packaged and deployed as part of the Terraform run:

- **Terraform** — `data "archive_file"` in `modules/transaction-processor/lambda.tf`
  zips `src/` on every `plan`/`apply`. `source_code_hash` tracks the zip, so any
  source change redeploys the function on the next apply.
- **CI build stage** — `scripts/package.sh` runs before Terraform in the plan and
  apply workflows: it byte-compiles the sources (syntax gate) and uploads
  `build/transaction_processor.zip` as a workflow artifact.

`boto3` is provided by the Lambda runtime, so there is nothing to vendor. If a
third-party dependency is added, install it into the staging dir in
`scripts/package.sh`.

Local build:

```bash
./scripts/package.sh                 # -> build/transaction_processor.zip
```

## Deploying

Environment is selected with `-var="environment=<dev|prod>"` (see the
`terraform-aws-conventions` house style). Workflows are **manual dispatch only** —
nothing runs on push or PR.

```bash
gh workflow run terraform-plan.yml  -f environment=dev
gh workflow run terraform-apply.yml -f environment=dev
```

Local:

```bash
terraform init -backend-config="key=fdp-infra-serverless/dev/terraform.tfstate"
terraform apply -var="environment=dev"
```

### Prerequisites

1. State bucket `fdp-infra-state-bucket-861477414666-eu-west-2-an` (eu-west-2).
2. Repo secrets `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`; GitHub
   Environments `dev` and `prod` (required reviewers on `prod`).
3. The destination DynamoDB table already exists
   (`arn:aws:dynamodb:eu-west-2:861477414666:table/fdp-dev-euw2-transactions`)
   — this repo references it, it does not create it. Set the `prod` table
   name/ARN in `lambda_main.tf` before deploying prod.
4. `main` is the default branch; do change work on `feature/dev` and PR into `main`.

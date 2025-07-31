# Serverless AWS Glue ETL Trigger for NetSuite

This project provides a serverless, infrastructure-as-code template for extracting data from NetSuite in monthly batches. It uses an AWS Glue ETL job triggered by a scheduled AWS Lambda function. All resources are defined and deployed using the Serverless Framework.

-----

## 🏛️ Architecture Overview

The pipeline follows a simple, event-driven architecture:

```
┌──────────────────┐      ┌───────────────┐      ┌───────────────────────────┐
│ CloudWatch Event │ ──►  │ Lambda        │ ──►  │ AWS Glue Job              │
│ (Cron Schedule)  │      │ (Orchestrator)│      │ (netsuite-transaction-etl)│
└──────────────────┘      └───────────────┘      └─┬─────────────────────────┘
                                                   │
                                     ┌─────────────▼──────────────┐
                                     │                            │
                            ┌────────┴─────────┐         ┌────────┴─────────┐
                            │ AWS S3           │         │ NetSuite         │
                            │ (Glue Script/JAR)│         │ (JDBC Source)    │
                            └──────────────────┘         └──────────────────┘
                            ┌────────┴─────────┐         ┌────────┴─────────┐
                            │ Secrets Manager  │         │ AWS S3           │
                            │ (Credentials)    │         │ (Parquet Output) │
                            └──────────────────┘         └──────────────────┘
```

-----

## ✨ Features

  * **Dynamic Date Batching**: The Lambda function automatically calculates the date range for the previous full month and passes it to the Glue job.
  * **Infrastructure as Code (IaC)**: All AWS resources (Lambda, Glue, S3, IAM Roles) are defined in `serverless.yml` for repeatable and version-controlled deployments.
  * **Automated Asset Deployment**: Automatically uploads your Python Glue script and JDBC JAR file to S3 during deployment.
  * **Secure Credential Management**: Leverages AWS Secrets Manager to securely store and access NetSuite credentials, avoiding hardcoded secrets.
  * **Least-Privilege IAM Roles**: Creates specific IAM roles for the Lambda and Glue job, ensuring they only have the permissions they need.

-----

## prerequisites

Before you begin, ensure you have the following installed and configured:

  * [Node.js](https://nodejs.org/en/) (v20.x or later) and npm
  * [Serverless Framework CLI](https://www.serverless.com/framework/docs/getting-started)
  * [AWS CLI](https://aws.amazon.com/cli/) with credentials configured in your environment.

-----

## 📂 Project Structure

```
your-project-root/
├── assets/
│   ├── glue-scripts/
│   │   └── glue_script.py      # Your Python ETL script
│   └── jdbc-drivers/
│       └── NQjc.jar            # Your NetSuite JDBC driver
├── cloudformation/
│   ├── functions.yml         # Lambda function definitions
│   └── resources.yml         # AWS resource definitions (Glue, S3, IAM)
├── config/
│   └── config.dev.json         # Stage-specific configurations
├── handler.js                  # Lambda function code
├── package.json
├── README.md                   # This file
└── serverless.yml              # Main serverless configuration
```

-----

## 🚀 Setup and Deployment

Follow these steps to configure and deploy the stack.

### 1\. Install Dependencies

Install the project dependencies defined in `package.json`.

```bash
npm install
```

### 2\. Place Your Assets

1.  Place your Python Glue ETL script into the `assets/glue-scripts/` directory.
2.  Place your NetSuite JDBC driver (`.jar` file) into the `assets/jdbc-drivers/` directory.


### 3\. Deploy the Stack

Deploy the entire stack to your AWS account using the Serverless Framework CLI.

```bash
serverless deploy --stage dev
```

This command will provision all the AWS resources, create the S3 asset bucket, upload your script and JAR file, and deploy the Lambda function.

-----
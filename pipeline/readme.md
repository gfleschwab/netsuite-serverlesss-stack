# CI/CD Pipeline

## Overview

The Pipeline service provides cloudformation templates for creating an AWS CodePipeline setup for managing CI/CD. The CI/CD process will:
  - Build and deploy the back-end
  - Update Cloudformation stacks
  - Build and deploy front-end to AWS S3 hosting bucket
  - Sync log files with S3 buckets for learning documents and CI/CD artifacts

## Sub-Prod Environments

1.  Replace the project name in the **template.yml** file. Configure any additional permissions needed for project, if you need more than the defaults. You can also remove any unecessary ones.
2.  From the root folder, build the CI/CD by running this command: `npm run build-cicd --stage={env}`  (WINDOWS run `npm run build-cicd-windows --stage={env}`)
3.  If after building the CI/CD you change anything in the template.yml, you can update the CI/CD by running: `npm run update-cicd --stage={env}`  (WINDOWS run `npm run update-cicd-windows --stage={env}`)
   
**NOTE:** *You will need aws-cli setup and configured locally. Documentation: https://docs.aws.amazon.com/polly/latest/dg/setup-aws-cli.html.*

## Prod Environment

1. Configure YML and Buildspec located in pipeline/prod by replacing default github and project name values.
2. Rename YML file to include actual project name and verify this file is ref in Buildspec.
3. Head to [CodePipelineFactory](https://github.com/LesSchwab062017/CodePipelineFactory) and create a new branch with app name.
4. Copy over the prod pipeline YML and Buildspec from step 1 to the new branch.
5. Create a pull request from your new branch into master.
6. Monitor pull request and watch for build errors in CodePipeline


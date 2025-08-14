// handler.js
import { GlueClient, StartJobRunCommand, GetJobRunCommand } from "@aws-sdk/client-glue";
import { SFNClient, SendTaskSuccessCommand, SendTaskFailureCommand } from "@aws-sdk/client-sfn";

const formatDate = (date) => {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
};

const delay = (ms) => new Promise(resolve => setTimeout(resolve, ms));

export const handler = async (event) => {
    console.log("Trigger event received:", JSON.stringify(event, null, 2));

    const glueClient = new GlueClient({});
    const sfnClient = new SFNClient({});
    const jobName = process.env.GLUE_JOB_NAME;
    const secretName = process.env.SECRET_NAME;
    const pollIntervalMs = 30000; // Poll every 30 seconds

    if (!jobName || !secretName) {
        await sfnClient.send(new SendTaskFailureCommand({
            taskToken: event.TaskToken,
            error: "EnvironmentVariableError",
            cause: "GLUE_JOB_NAME and SECRET_NAME env vars must be set."
        }));
        throw new Error("GLUE_JOB_NAME and SECRET_NAME env vars must be set.");
    }

    const { startDate, endDate, TaskToken } = event;

    if (!startDate || !endDate || !TaskToken) {
        throw new Error("Event must contain 'startDate', 'endDate', and 'TaskToken' properties.");
    }

    const jobArgs = {
        "--start_date": formatDate(new Date(startDate)),
        "--end_date": formatDate(new Date(endDate)),
        "--secret_name": secretName,
    };

    const command = new StartJobRunCommand({
        JobName: jobName,
        Arguments: jobArgs,
    });

    let jobRunId;
    try {
        console.log(`Starting Glue job '${jobName}' with arguments:`, jobArgs);
        const response = await glueClient.send(command);
        jobRunId = response.JobRunId;
        console.log(`Successfully started Glue job. JobRunId: ${jobRunId}`);
    } catch (error) {
        console.error("Failed to start Glue job:", error);
        await sfnClient.send(new SendTaskFailureCommand({
            taskToken: TaskToken,
            error: error.name,
            cause: error.message
        }));
        throw error;
    }

    // Polling loop to wait for the Glue job to complete
    let jobStatus = 'STARTING';
    try {
        while (jobStatus === 'STARTING' || jobStatus === 'RUNNING') {
            console.log(`Polling status for JobRunId: ${jobRunId}. Current status: ${jobStatus}`);
            await delay(pollIntervalMs);
            const getCommand = new GetJobRunCommand({
                JobName: jobName,
                RunId: jobRunId,
            });
            const getResponse = await glueClient.send(getCommand);
            jobStatus = getResponse.JobRun.JobRunState;
        }

        if (jobStatus !== 'SUCCEEDED') {
            const errorMessage = `Glue job with ID: ${jobRunId} failed or was stopped. Final status: ${jobStatus}`;
            console.error(errorMessage);
            await sfnClient.send(new SendTaskFailureCommand({
                taskToken: TaskToken,
                error: "GlueJobFailed",
                cause: errorMessage
            }));
            throw new Error(errorMessage);
        }

        console.log(`Glue job with ID: ${jobRunId} completed successfully.`);
        await sfnClient.send(new SendTaskSuccessCommand({
            taskToken: TaskToken,
            output: JSON.stringify({ message: `Glue job with ID: ${jobRunId} completed successfully.` })
        }));
    } catch (error) {
        console.error("Error during job polling:", error);
        await sfnClient.send(new SendTaskFailureCommand({
            taskToken: TaskToken,
            error: error.name || "PollingError",
            cause: error.message
        }));
        throw error;
    }
};
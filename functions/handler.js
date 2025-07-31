// handler.js
import { GlueClient, StartJobRunCommand } from "@aws-sdk/client-glue";

const formatDate = (date) => {
    const year = date.getFullYear();
    const month = (date.getMonth() + 1).toString().padStart(2, '0');
    const day = date.getDate().toString().padStart(2, '0');
    return `${year}-${month}-${day}`;
};

export const handler = async (event) => {
    console.log("Trigger event received:", JSON.stringify(event, null, 2));

    const glueClient = new GlueClient({});
    const jobName = process.env.GLUE_JOB_NAME;
    const secretName = process.env.SECRET_NAME;

    if (!jobName || !secretName) {
        throw new Error("glueJobName and secretName env vars must be set.");
    }

    let startDate, endDate;

    if (event.start_date && event.end_date) {
        console.log("Manual trigger detected. Using provided date range.");
        startDate = event.start_date;
        endDate = event.end_date;
    } else {
        console.log("Scheduled trigger detected. Calculating date range for the previous month.");
        const today = new Date();
        const startOfThisMonth = new Date(today.getFullYear(), today.getMonth(), 1);
        const startOfLastMonth = new Date(today.getFullYear(), today.getMonth() - 1, 1);
        startDate = formatDate(startOfLastMonth);
        endDate = formatDate(startOfThisMonth);
    }

    const jobArgs = {
        "--start_date": startDate,
        "--end_date": endDate,
        "--secret_name": secretName,
    };

    const command = new StartJobRunCommand({
        JobName: jobName,
        Arguments: jobArgs,
    });

    try {
        console.log(`Starting Glue job '${jobName}' with arguments:`, jobArgs);
        const response = await glueClient.send(command);
        const message = `Successfully started Glue job. JobRunId: ${response.JobRunId}`;
        console.log(message);
        
        return {
            statusCode: 200,
            body: JSON.stringify({ message, jobRunId: response.JobRunId }),
        };
    } catch (error) {
        console.error("Failed to start Glue job:", error);
        throw error;
    }
};
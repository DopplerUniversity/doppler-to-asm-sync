# Doppler Manual AWS Secrets Manager Sync

This is a script designed to be used inside of an AWS Lambda function that runs in the docker container defined in the provided `Dockerfile`.

## Usage

1. Create a new private AWS ECR repository named `doppler-to-asm-sync`.
2. Build the image (replace `<repository-uri>` with the URI for your private AWS ECR repository):

```shell
docker build -t doppler-to-asm-sync . \
  && docker tag doppler-to-asm-sync:latest <repository-uri>:latest \
  && docker push <repository-uri>:latest
```

3. Create a new AWS IAM Policy called `dopplerToAsmSync` (if you're going to be having many syncs that don't share the same underlying role, then you should name this accordingly because you'll need a separate role per sync) with the following policy JSON:

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": ["secretsmanager:PutSecretValue"],
      "Resource": ["<AWS-ARN-for-ASM-secret-being-updated>"]
    }
  ]
}
```

When we apply this to the Lambda, it'll give the function permission to update the secret you specify. If you're going to be using the same function to update multiple secrets, be sure to include the ARN for every secret it'll be updating here.

4. Create a new AWS Lambda container image function named `dopplerToAsmSync` (feel free to name it however you like – the actual name is unimportant).

- Choose the image you pushed in the previous step.
- Be sure you choose whichever architecture you're building the docker container with as well (e.g., choose `arm64` if you're building on a Mac running on Apple Silicon).
- Use the "Create a new role with basic Lambda permissions" option for the execution role (we'll update the role it creates later).

5. Switch to the **Configuration** tab for the Lambda function and edit the **General configuration**. Increase the timeout from 3 seconds to 30 seconds and increase memory from 128MB to 150MB to allow the script to execute faster.
6. Switch to the **Permissions** section from the left sidebar and click the link to the role it's using that's near the top of that section under "Role name".
7. Click the **Add permissions** button and choose **Attach policies**.
8. Find the `dopplerToAsmSync` policy we created earlier and add that permission.
9. Switch to the **Function URL** section from the left sidebar and click the "Create function URL" button. For the purposes of this example, choose the "NONE" option for Auth type. This URL is only used to trigger a sync, so no major damage could be done, but ultimately you'd likely want to use "AWS_IAM" auth and use a user's IAM credentials to trigger the run.
10. Switch to the **Environment variables** section from the left sidebar and click the "Edit" button. Add a new variable for `DOPPLER_TOKEN` with its value set to a Doppler access token that has read permission to whichever config you want to sync. If you're using an access token that can access more than one config, then you can set `DOPPLER_PROJECT` and `DOPPLER_CONFIG` to specify which should be used. If neither is specified, then the script will attempt to use what's specified in the webhook payload Doppler sends.
11. To specify which AWS Secrets Manager secret gets synced to, either add another environment variable named `AWS_SECRET_ARN` to the lambda function OR add an `AWS_SECRET_ARN` secret to the Doppler config you're syncing. The variable should contain the ARN for the secret you're syncing secrets from Doppler to (this should be the same secret you added `PutSecretValue` permissions for earlier). If no `AWS_SECRET_ARN` variable is set for the lambda, it will check the secrets in the Doppler config for one there. If it exists, it'll use that. If not, the sync will fail (you have to specify one or the other).
12. Open your Doppler dashboard and browse to the project you want to sync to AWS Secrets Manager.
13. Click the **Webhooks** link in the left sidebar and click the "Add" button.
14. Give the webhook a name and then paste in the Function URL that we created earlier. Choose the config(s) you want to sync and click "Save" (we want the default payload and no authentication for the purposes of this example).

Now, every time you save your Doppler config, it will trigger the lambda which will sync secrets from Doppler to the AWS Secrets Manager secret you specified. As of right now, the execution time of the script is very close to the timeout for Doppler webhooks. Each Doppler webhook retries up to 5 times, so it's fairly typical for it to retry once or twice before it registers a success. Either way, the actual sync will complete successfully the first try even though it's not registering as such on the Doppler side.

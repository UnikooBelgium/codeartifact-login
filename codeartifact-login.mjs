import { exec } from "child_process";
import { promisify } from "util";
import { stat, readFile, writeFile } from "fs/promises";
import { join } from "path";
import { homedir } from "os";

const execAsync = promisify(exec);

const domain = "studio-fledge";
const domainOwner = "491085412041";
const region = "eu-west-1";
const typescriptRepo = "studio-fledge-framework-typescript";
const scope = "@studio-fledge";

const registryBaseUrl = `https://${domain}-${domainOwner}.d.codeartifact.${region}.amazonaws.com`;
const typescriptRegistryUrl = `${registryBaseUrl}/npm/${typescriptRepo}/`;

const tokenFilePath = join(homedir(), ".codeartifact-token");
const FILE_MODE = 0o600; // Read/write for owner only
const TOKEN_MAX_AGE = 43200; // 12 hours in seconds
const TOKEN_REFRESH_BUFFER = 1800; // Refresh 30 minutes before expiry

async function main() {
  const token = await getToken();

  await execAsync(
    `npm config set "${scope}:registry" "${typescriptRegistryUrl}" --global`,
  );
  await execAsync(
    `npm config set "//${domain}-${domainOwner}.d.codeartifact.${region}.amazonaws.com/npm/${typescriptRepo}/:_authToken" "${token}" --global`,
  );

  console.log("✅ npm codeartifact configured");
}

async function getToken() {
  // Check if cached token exists and is still valid
  try {
    const stats = await stat(tokenFilePath);
    const fileAge = Math.floor((Date.now() - stats.mtimeMs) / 1000);

    if (fileAge < TOKEN_MAX_AGE - TOKEN_REFRESH_BUFFER) {
      const token = (await readFile(tokenFilePath, "utf8")).trim();
      const timeRemaining = TOKEN_MAX_AGE - fileAge;
      const hoursRemaining = Math.floor(timeRemaining / 3600);
      const minutesRemaining = Math.floor((timeRemaining % 3600) / 60);
      console.log(
        `✅ Using cached CodeArtifact token (expires in ${hoursRemaining}h ${minutesRemaining}m)`,
      );
      return token;
    }
  } catch {
    // File doesn't exist or can't be read, will fetch new token
  }

  // Fetch new token
  try {
    const { stdout } = await execAsync(
      `aws codeartifact get-authorization-token --domain ${domain} --domain-owner ${domainOwner} --region ${region} --query authorizationToken --output text`,
    );
    const token = stdout.trim();

    await writeFile(tokenFilePath, token, { mode: FILE_MODE });
    console.log("✅ CodeArtifact token refreshed (expires in 12h)");
    return token;
  } catch {
    console.log(
      "Unable to fetch CodeArtifact authorization token. Please check your AWS credentials and permissions.",
    );
    process.exit(0);
  }
}

main().catch((error) => {
  console.error("Error:", error.message);
  process.exit(1);
});

![TestDriver.ai](https://github.com/dashcamio/testdriver/assets/318295/2a0ad981-8504-46f0-ad97-60cb6c26f1e7)

# TestDriver.ai v6 Quickstart

Sample repo that has a guide for common web use cases. Using a Desktop app and need help? Email us at support@testdriver.ai and we can help if you get stuck.

---

**What is TestDriver?**

Next generation autonomous AI agent for end-to-end testing of web & desktop

[Website](https://testdriver.ai) | [Docs](https://docs.testdriver.ai) | [Join our Forum](https://forums.testdriver.ai) | [Signup](https://app.testdriver.ai)

---

## Setup

First, [fork this repository](https://github.com/testdriverai/quickstart-web/fork).

> TestDriver requires an API key. Get one by signing up at [app.testdriver.ai](https://app.testdriver.ai) and start your 7-day trial.

## Test Generation

Tests are defined in YAML files located in the `testdriver/tests` directory. Each test file contains a series of steps that the AI agent will execute.

### Two Ways to Create Tests

**1. Interactive Mode** (see `mytest.yaml`)
- Run `npx testdriverai@latest testdriver/tests/mytest.yaml` and enter prompts interactively
- TestDriver will generate specific commands for each prompt and save them to the file
- For more info see [Interactive Mode Documentation](https://docs.testdriver.ai/interactive/explore)

**2. Prompt-Based Testing** (see `prompts.yaml`)
- Write your test plan/steps/exit criteria as a set of prompts in a YAML file
- TestDriver executes them in order, creating commands on the fly
- Use `--heal` and `--write` flags to save working steps and enable auto-retry
- TestDriver can also generate prompts using the `/generate` command - see [Generation Documentation](https://docs.testdriver.ai/features/generation)

### Auto-Healing
Use the `--heal` flag to enable automatic retry of failed steps. Documentation: [Auto-Healing](https://docs.testdriver.ai/features/auto-healing)

**Note:** The website will be loaded automatically before the first step (configured in `prerun.yaml`), so you don't need to include navigation commands.

## Lifecycle Scripts

TestDriver uses three types of lifecycle scripts that run at different stages of the testing process:

### Prerun Scripts (`testdriver/lifecycle/prerun.yaml`)

- Run **BEFORE** each test in the suite
- Used for setting up the testing environment
- Example: Launching Chrome with specific configurations, setting up TestDriver Dashcam for replays and logs

### Provision Scripts (`testdriver/lifecycle/provision.yaml`)

- Run **ONCE** when your VM is created
- Used for initial setup that only needs to happen once per VM
- Example: Downloading files from Google Drive or GitHub repositories to add to the VM during provisioning

### Postrun Scripts (`testdriver/lifecycle/postrun.yaml`)

- Run **AFTER** each test in the suite
- Used for cleanup or post-processing tasks
- Example: Sending dashcam recordings to the server

## Environment Variables

The `.env.example` file shows the required environment variables:

- `TD_API_KEY`: Your TestDriver API key
- `TD_WEBSITE`: The website to test
- `TD_TEST_USERNAME` and `TD_TEST_PASSWORD`: Optional - Credentials for testing

Rename `.env.example` to `.env` and fill in your actual values.

## Running a test

To run a test, use the following command from your favorite terminal:

```bash
npx testdriverai@latest run tests/test_case.yaml
```

To use an integrated IDE experience for creating, viewing, debugging and running tests, we recommend VS Code with the [TestDriver.ai extension](https://marketplace.visualstudio.com/items?itemName=testdriver.testdriver).

## GitHub Actions

The repository includes a GitHub Actions workflow (`testdriver.yml`) that allows you to run tests manually or automatically. You can select a specific test folder or file to run through the GitHub Actions interface.

Using a different CI/CD tool? No problem! The `testdriver.yml` file can be used as a template for other CI/CD tools. Just run the `npx testdriverai@latest run` command with the path to your test file in your CI/CD pipeline.

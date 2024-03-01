# Welcome to Klaviyo Swift SDK contributing guide

Thank you for considering contributing to the Klaviyo Swift SDK!

In this guide you will get an overview of the contribution workflow from engaging in discussion to
opening an issue, creating a PR, reviewing, and merging the PR.

We welcome your contributions and strive to respond in a timely manner. In return, we ask that you do your
**due diligence** to answer your own questions using public resources, and check for related issues (including
closed ones) before posting. This helps keep the discussion focused on the most important topics. Issues deemed
off-topic or out of scope for the SDK will be closed. Likewise, please keep comments on-topic and productive. If
you have a different question, please open a new issue rather than commenting on an unrelated issue.

Before contributing, please read the [code of conduct](./CODE_OF_CONDUCT.md). We want this community to be friendly
and respectful to each other. Please follow it in all your interactions with the project.

## Github Issues

If you suspect a bug or have a feature request, please open an issue, following the guidelines below:

- Research your issue using public resources such as Google, Stack Overflow, Apple documentation, etc.
- Check if the issue has already been reported before.
- Use a clear and descriptive title for the issue to identify the problem.
- Include as much information as possible, including:
  - The version of the SDK you are using.
  - The version of iOS, Swift and XCode you are using.
  - Any error messages you are seeing.
  - The expected behavior and what went wrong.
  - Detailed steps to reproduce the issue
  - A code snippet or a minimal example that reproduces the issue.

> Answer all questions in the issue template. It is designed to help you follow all the above guidelines.
>
> ⚠️ Incomplete issues will be de-prioritized or closed. ⚠️

## New contributor guide

To get an overview of the project, read the [README](README.md).
Here are some additional resources to help you get started:

- [Engage in Discussions](https://docs.github.com/en/discussions/collaborating-with-your-community-using-discussions/participating-in-a-discussion)
- [Finding ways to contribute to open source on GitHub](https://docs.github.com/en/get-started/exploring-projects-on-github/finding-ways-to-contribute-to-open-source-on-github)
- [Set up Git](https://docs.github.com/en/get-started/quickstart/set-up-git)
- [GitHub flow](https://docs.github.com/en/get-started/quickstart/github-flow)
- [Collaborating with pull requests](https://docs.github.com/en/github/collaborating-with-pull-requests)

### Create a new issue

If you spot a problem, or want to suggest a new feature, first
[search if an issue already exists](https://docs.github.com/en/github/searching-for-information-on-github/searching-on-github/searching-issues-and-pull-requests#search-by-the-title-body-or-comments).
If a related issue doesn't exist, you can open a new issue using a relevant [issue form](https://github.com/klaviyo/klaviyo-swift-sdk/issues/new/choose).

### Solve an issue

If you want to recommend a code fix for an existing issue, you are welcome to open a PR with a fix.

1. Fork the repository and clone to your machine, open in XCode
2. Make your changes to the SDK. While we encourage test-driven development, we will not require
   unit tests to submit a PR. That said, tests are an easy way to verify your changes as you go.
   We have a very high coverage rate, so there are plenty of examples to follow.
3. We also encourage you to test your changes against your own app or the sample app in this repository.
4. Commit the changes once you are happy with them, please include a detailed commit message.

### Pull Request

When you're finished with the changes, create a pull request, also known as a PR.
- Fill the template so that we can review your PR. This template helps reviewers
  understand your changes and the purpose of your pull request.
- Don't forget to [link the PR to an issue](https://docs.github.com/en/issues/tracking-your-work-with-issues/linking-a-pull-request-to-an-issue)
  if you are solving one.
- Enable the checkbox to [allow maintainer edits](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/allowing-changes-to-a-pull-request-branch-created-from-a-fork)
  so the branch can be updated for a merge. Once you submit your PR, a team member will review your
  proposal. We may ask questions or request additional information.
- We may ask for changes to be made before a PR can be merged, either using [suggested changes](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/incorporating-feedback-in-your-pull-request)
  or pull request comments.
- As you update your PR and apply changes, mark each conversation as [resolved](https://docs.github.com/en/github/collaborating-with-issues-and-pull-requests/commenting-on-a-pull-request#resolving-conversations).
- Alternatively, we may incorporate your suggestions into another feature branch and communicate
  progress in the original issue or PR.

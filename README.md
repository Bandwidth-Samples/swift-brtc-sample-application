# Bandwidth WebRTC Swift Sample Application

This is a sample command-line application demonstrating how to use the [Bandwidth WebRTC Swift SDK](https://github.com/Bandwidth/in-app-calling-swift-sdk).

## Features

*   Creates a WebRTC endpoint.
*   Connects to the Bandwidth WebRTC service.
*   Places an outbound call.
*   Unpublishes a stream.
*   Disconnects from the WebRTC service.
*   Deletes the WebRTC endpoint on exit.

## Prerequisites

*   A Bandwidth account.
*   A configured Voice API application.
*   Xcode or the Swift toolchain installed.

## Getting Started

1.  **Clone the repository:**
    ```bash
    git clone https://github.com/Bandwidth/brtc-swift-sample-application.git
    cd brtc-swift-sample-application
    ```

2.  **Set the following environment variables:**
    *   `ACCOUNT_ID`: Your Bandwidth account ID.
    *   `BW_USERNAME`: Your Bandwidth API credentials username.
    *   `BW_PASSWORD`: Your Bandwidth API credentials password.
    *   `CALLBACK_BASE_URL`: A publicly accessible URL for receiving webhook events.

    You can set them in your shell profile (e.g., `~/.zshrc` or `~/.bash_profile`) or export them in your terminal session:
    ```bash
    export ACCOUNT_ID="your_account_id"
    export BW_USERNAME="your_username"
    export BW_PASSWORD="your_password"
    export CALLBACK_BASE_URL="https://your-callback-url.com"
    ```

3.  **Build and run the application:**
    ```bash
    swift run
    ```

4.  **Follow the interactive prompts to use the application.**

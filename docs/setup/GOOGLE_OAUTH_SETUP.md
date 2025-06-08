# Google OAuth Setup Instructions

This guide will help you set up Google OAuth for the AgentleGuide application.

## Prerequisites

1. A Google account
2. Access to the Google Cloud Console

## Steps

### 1. Create a Google Cloud Project

1. Go to the [Google Cloud Console](https://console.cloud.google.com/)
2. Click "Select a project" and then "New Project"
3. Enter project name: `agentleguide-oauth`
4. Click "Create"

### 2. Enable Required APIs

1. In the Google Cloud Console, go to "APIs & Services" > "Library"
2. Enable the following APIs:
   - **Google+ API** (for basic profile information)
   - **Gmail API** (for email access)
   - **Google Calendar API** (for calendar access)

### 3. Configure OAuth Consent Screen

1. Go to "APIs & Services" > "OAuth consent screen"
2. Choose "External" user type (unless you have a Google Workspace account)
3. Fill in the required information:
   - **App name**: AgentleGuide
   - **User support email**: Your email
   - **Developer contact email**: Your email
4. Add the following scopes:
   - `email`
   - `profile`
   - `https://www.googleapis.com/auth/gmail.readonly`
   - `https://www.googleapis.com/auth/gmail.send`
   - `https://www.googleapis.com/auth/calendar.readonly`
   - `https://www.googleapis.com/auth/calendar`
5. Add test users:
   - **webshookeng@gmail.com** (as requested)
   - Your own email address

### 4. Create OAuth 2.0 Credentials

1. Go to "APIs & Services" > "Credentials"
2. Click "Create Credentials" > "OAuth 2.0 Client IDs"
3. Choose "Web application"
4. Set the name: `AgentleGuide Web Client`
5. Add authorized redirect URIs:
   - `http://localhost:4000/auth/google/callback` (for development)
   - Add your production URL when deploying: `https://yourdomain.com/auth/google/callback`
6. Click "Create"
7. Copy the Client ID and Client Secret

### 5. Set Environment Variables

Create a `.env` file in your project root with the following:

```bash
export GOOGLE_CLIENT_ID="your_client_id_here"
export GOOGLE_CLIENT_SECRET="your_client_secret_here"
```

Or set them directly in your shell:

```bash
export GOOGLE_CLIENT_ID="your_client_id_here"
export GOOGLE_CLIENT_SECRET="your_client_secret_here"
```

### 6. Load Environment Variables

Before starting your Phoenix server, make sure to load the environment variables:

```bash
# If using .env file
source .env

# Start the server
mix phx.server
```

## Testing the Setup

1. Start your Phoenix server: `mix phx.server`
2. Go to `http://localhost:4000`
3. Click "Connect with Google"
4. You should be redirected to Google's OAuth consent screen
5. After authorization, you should be redirected back to your app and see the connected status

## Troubleshooting

### "redirect_uri_mismatch" Error
- Make sure your redirect URI in Google Cloud Console exactly matches `http://localhost:4000/auth/google/callback`
- Check for trailing slashes or typos

### "access_denied" Error
- Make sure you've added your email as a test user in the OAuth consent screen
- Ensure all required scopes are added

### "invalid_client" Error
- Double-check your Client ID and Client Secret
- Make sure environment variables are loaded correctly

## Security Notes

- Never commit your `.env` file or expose your Client Secret
- Add `.env` to your `.gitignore` file
- In production, use secure environment variable management
- Consider using different OAuth apps for development and production

## Next Steps

Once OAuth is working, you can:
1. Test the Gmail and Calendar integrations
2. Set up HubSpot OAuth (similar process)
3. Implement the AI agent features 
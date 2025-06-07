# HubSpot OAuth Setup Guide

This guide will walk you through setting up HubSpot OAuth integration for your AgentleGuide application.

## Prerequisites

- HubSpot Developer Account
- Your application running locally at `http://localhost:4000`

## Step 1: Create a HubSpot Developer Account

1. Go to [HubSpot Developer Portal](https://developers.hubspot.com/)
2. Sign up for a developer account or log in if you already have one
3. Accept the developer terms of service

## Step 2: Create a New App

1. In the HubSpot Developer Portal, navigate to **Apps**
2. Click **Create app** button
3. Fill in the app details:
   - **App name**: `AgentleGuide AI Assistant`
   - **Description**: `AI-powered assistant for financial advisors with CRM integration`
   - **App logo**: Upload a logo (optional)

## Step 3: Configure OAuth Settings

### Auth Tab Configuration

1. Go to the **Auth** tab in your app settings
2. Configure the following:

#### Required Scopes
Select these scopes for your app:
- `crm.objects.contacts.read` - Read contact data
- `crm.objects.contacts.write` - Create and update contacts
- `crm.objects.companies.read` - Read company data
- `crm.objects.companies.write` - Create and update companies
- `crm.objects.deals.read` - Read deal data
- `crm.objects.deals.write` - Create and update deals
- `crm.lists.read` - Read contact lists
- `crm.lists.write` - Create and manage lists
- `crm.schemas.contacts.read` - Read contact properties
- `timeline` - Create timeline events
- `oauth` - Required for OAuth flow

#### Redirect URLs
Add this redirect URL:
```
http://localhost:4000/auth/hubspot/callback
```

#### Optional Redirect URLs (for production later)
```
https://yourdomain.com/auth/hubspot/callback
```

## Step 4: Get Your Credentials

1. After saving your auth settings, you'll see:
   - **Client ID**: Copy this value
   - **Client Secret**: Copy this value (keep it secure!)

## Step 5: Configure Environment Variables

### Option A: Using .env file (recommended for development)

1. Create a `.env` file in your project root:

```bash
# HubSpot OAuth Configuration
HUBSPOT_CLIENT_ID=your_actual_client_id_here
HUBSPOT_CLIENT_SECRET=your_actual_client_secret_here
```

2. Add `.env` to your `.gitignore` file to keep secrets secure:

```bash
echo ".env" >> .gitignore
```

3. Install and use a package like `dotenv` to load environment variables:

```bash
# Add to mix.exs dependencies
{:dotenv, "~> 3.0.0", only: [:dev, :test]}
```

### Option B: Export environment variables directly

```bash
export HUBSPOT_CLIENT_ID="your_actual_client_id_here"
export HUBSPOT_CLIENT_SECRET="your_actual_client_secret_here"
```

### Option C: Update dev.exs directly (not recommended for production)

Update `config/dev.exs` with your actual credentials:

```elixir
config :ueberauth, Ueberauth.Strategy.Hubspot.OAuth,
  client_id: "your_actual_client_id_here",
  client_secret: "your_actual_client_secret_here"
```

## Step 6: Add Test Users (Important!)

1. In your HubSpot app settings, go to the **Auth** tab
2. Scroll down to **Test users**
3. Add these email addresses as test users:
   - `webshookeng@gmail.com` (as requested)
   - Your own email address
   - Any other email addresses you want to test with

**Note**: Only users added to this test list can authorize your app during development.

## Step 7: Test Your Integration

1. Make sure your environment variables are set
2. Restart your Phoenix server:

```bash
mix phx.server
```

3. Navigate to `http://localhost:4000`
4. Sign in with Google first
5. Click the **Connect** button next to HubSpot
6. You should be redirected to HubSpot's authorization page

## Step 8: Production Setup

When you're ready to go to production:

1. **Update redirect URLs** in your HubSpot app to include your production domain
2. **Set environment variables** in your production environment
3. **Submit your app for review** if you plan to make it publicly available

## Troubleshooting

### "Missing parameters" error
- Verify your environment variables are set correctly
- Check that `client_id` and `client_secret` are not empty
- Restart your server after setting environment variables

### "Unauthorized" error
- Make sure you've added test users to your HubSpot app
- Verify the redirect URL matches exactly (including `http://` vs `https://`)

### "Invalid scope" error
- Check that all required scopes are selected in your HubSpot app
- Make sure the scopes in your app match the ones in your Elixir configuration

### Still having issues?
1. Check the server logs for more detailed error messages
2. Verify your HubSpot app is in "Draft" mode for testing
3. Make sure your HubSpot developer account is active

## Current Configuration

Your application is configured with these settings:

- **Redirect URI**: `http://localhost:4000/auth/hubspot/callback`
- **Required Scopes**: Contact, Company, Deal read/write, Lists, Timeline, OAuth
- **Provider**: HubSpot (via ueberauth_hubspot)

## Security Notes

- Never commit your `HUBSPOT_CLIENT_SECRET` to version control
- Use environment variables for all sensitive configuration
- Consider using a service like HashiCorp Vault for production secrets management
- Rotate your client secret periodically for security

---

Once you've completed these steps, your HubSpot OAuth integration should work smoothly! 
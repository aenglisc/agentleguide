# HubSpot Token Refresh Setup

The HubSpot token refresh system has been implemented to automatically renew OAuth tokens before they expire (HubSpot tokens expire after 30 minutes).

## How It Works

### Automatic Token Refresh
1. **Scheduled Jobs**: When you connect HubSpot, a token refresh job is automatically scheduled
2. **Smart Timing**: Refreshes tokens 5 minutes before expiry (or 25 minutes after connection if no expiry is set)
3. **Auto-Retry**: If refresh fails, retries in 5 minutes
4. **Fallback**: API calls also check token expiry and auto-refresh if needed

### What's Been Added

#### New Job: `HubspotTokenRefreshJob`
- Monitors token expiry times
- Automatically refreshes tokens using refresh tokens
- Handles edge cases like expired refresh tokens
- Logs all refresh activities

#### Enhanced HubSpot Service
- `refresh_access_token/1` - Core refresh functionality
- `debug_token_status/1` - Check token status for debugging
- Auto-refresh on API calls when tokens are expiring

#### Updated Auth Flow
- Token refresh job is scheduled when HubSpot is connected
- Initial sync is also triggered on connection

## Testing the System

### 1. Check Current Token Status
```elixir
# In IEx console
user = Agentleguide.Accounts.get_user!(user_id)
{:ok, status} = Agentleguide.Services.Hubspot.HubspotService.debug_token_status(user)
IO.inspect(status)
```

This will show:
- `:valid` - Token is fine
- `:expiring_soon` - Will refresh in next 5 minutes
- `:expired` - Token has expired
- `:no_expiry_set` - No expiry time recorded

### 2. Manual Token Refresh
```elixir
# Force refresh immediately
{:ok, updated_user} = Agentleguide.Services.Hubspot.HubspotService.refresh_access_token(user)
```

### 3. Schedule Token Refresh Job
```elixir
# Schedule immediate refresh
Agentleguide.Jobs.HubspotTokenRefreshJob.schedule_now(user_id)

# Schedule next refresh based on expiry time
Agentleguide.Jobs.HubspotTokenRefreshJob.schedule_next_refresh(user_id)
```

## Monitoring

### Logs to Watch For
- `Successfully refreshed HubSpot token for user X` - Successful refresh
- `Failed to refresh token for user X: reason` - Refresh failure
- `Auto-refreshed HubSpot token for user X` - API call triggered refresh

### Common Error Scenarios

#### 1. `refresh_token_expired`
The refresh token has expired. User needs to reconnect HubSpot:
```
Visit /auth/hubspot to reconnect
```

#### 2. `no_refresh_token`
No refresh token stored. Check the initial OAuth flow:
```
Ensure refresh_token is being captured during OAuth
```

#### 3. `auth_failed` / `bad_request`
API credentials or request format issues:
```
Verify HUBSPOT_CLIENT_ID and HUBSPOT_CLIENT_SECRET
```

## Production Deployment

### Environment Variables Required
```bash
HUBSPOT_CLIENT_ID=your_client_id
HUBSPOT_CLIENT_SECRET=your_client_secret
```

### Job Queue Configuration
The token refresh job runs in the `:sync` queue. Ensure Oban is properly configured:

```elixir
config :agentleguide, Oban,
  repo: Agentleguide.Repo,
  queues: [
    default: 10,
    sync: 5,    # Token refresh jobs run here
    ai: 3
  ]
```

## Troubleshooting

### Token Refresh Not Working
1. Check if refresh token exists:
   ```elixir
   user.hubspot_refresh_token
   ```

2. Verify environment variables:
   ```elixir
   System.get_env("HUBSPOT_CLIENT_ID")
   System.get_env("HUBSPOT_CLIENT_SECRET")
   ```

3. Check job queue:
   ```elixir
   # View scheduled jobs
   Oban.Job
   |> where(worker: "Agentleguide.Jobs.HubspotTokenRefreshJob")
   |> Agentleguide.Repo.all()
   ```

### Manual Intervention
If automatic refresh isn't working, you can manually refresh:

```elixir
# Get user
user = Agentleguide.Accounts.get_user!(user_id)

# Debug status
{:ok, status} = Agentleguide.Services.Hubspot.HubspotService.debug_token_status(user)
IO.inspect(status)

# Force refresh
case Agentleguide.Services.Hubspot.HubspotService.refresh_access_token(user) do
  {:ok, updated_user} -> 
    IO.puts("✓ Token refreshed successfully")
  {:error, reason} -> 
    IO.puts("✗ Refresh failed: #{inspect(reason)}")
end
```

## Benefits

1. **No More 401 Errors**: Tokens are refreshed before expiry
2. **Seamless User Experience**: Users don't need to reconnect manually
3. **Reliable Integrations**: HubSpot API calls won't fail due to expired tokens
4. **Smart Scheduling**: Efficient refresh timing minimizes API calls

## Next Steps

The token refresh system is now active. When you connect HubSpot again, the system will:

1. Capture the refresh token
2. Schedule automatic token refresh
3. Keep your HubSpot integration running smoothly

No additional setup is required - the system works automatically once HubSpot is connected! 
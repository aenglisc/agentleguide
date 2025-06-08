defmodule Agentleguide.Services.Hubspot.HubspotService do
  @moduledoc """
  Service for interacting with HubSpot API to sync contacts and manage CRM data.
  """

  @behaviour Agentleguide.Services.Hubspot.HubspotServiceBehaviour

  require Logger

  @hubspot_api_base "https://api.hubapi.com"

  @doc """
  Sync contacts from HubSpot for a user (incremental sync).
  Only fetches contacts that are new or modified since the last sync.
  """
  def sync_contacts(user) do
    # Check if this is the first sync (no contacts exist)
    existing_contacts_count = Agentleguide.Rag.count_hubspot_contacts(user)

    if existing_contacts_count == 0 do
      # First sync - fetch all contacts
      with {:ok, contacts} <- fetch_contacts(user),
           {:ok, _results} <- store_contacts(user, contacts) do
        # Update user's last sync time
        update_hubspot_sync_time(user)
        {:ok, length(contacts)}
      else
        {:error, reason} ->
          Logger.debug("HubSpot initial sync error for user #{user.id}: #{inspect(reason)}")
          {:error, reason}
      end
    else
      # Incremental sync - only fetch modified contacts
      last_sync_time = get_last_hubspot_sync_time(user)

      with {:ok, contacts} <- fetch_new_contacts(user, last_sync_time),
           {:ok, _results} <- store_contacts(user, contacts) do
        # Update user's last sync time
        update_hubspot_sync_time(user)
        # Don't log here to avoid duplicate logging (job will log)
        {:ok, length(contacts)}
      else
        {:error, reason} ->
          Logger.debug("HubSpot sync error for user #{user.id}: #{inspect(reason)}")
          {:error, reason}
      end
    end
  end

  # Get the last HubSpot sync time for a user.
  defp get_last_hubspot_sync_time(user) do
    # Use explicit last sync time, fallback to connection time, or default to 30 days ago
    user.hubspot_last_synced_at ||
      user.hubspot_connected_at ||
      DateTime.add(DateTime.utc_now(), -30, :day)
  end

  # Update the user's last HubSpot sync time.
  defp update_hubspot_sync_time(user) do
    Agentleguide.Accounts.update_user(user, %{hubspot_last_synced_at: DateTime.utc_now()})
  end

  # Fetch only NEW or MODIFIED contacts from HubSpot API since last sync.
  defp fetch_new_contacts(user, since_datetime) do
    # Format datetime for HubSpot API (Unix timestamp in milliseconds)
    since_timestamp = DateTime.to_unix(since_datetime, :millisecond)

    # Use HubSpot's search API to get recently modified contacts
    url = "#{@hubspot_api_base}/crm/v3/objects/contacts/search"

    search_body = %{
      "filterGroups" => [
        %{
          "filters" => [
            %{
              "propertyName" => "lastmodifieddate",
              "operator" => "GTE",
              "value" => since_timestamp
            }
          ]
        }
      ],
      "properties" => [
        "email",
        "firstname",
        "lastname",
        "phone",
        "company",
        "notes_last_contacted",
        "notes_last_updated",
        "notes_next_activity_date",
        "lastmodifieddate",
        "createdate"
      ],
      "limit" => 100
    }

    case make_hubspot_request(user, url, :post, search_body) do
      {:ok, %{"results" => contacts}} ->
        # Filter out contacts we already have with the same lastmodifieddate
        new_contacts = filter_existing_contacts(user, contacts)
        {:ok, new_contacts}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Filter out contacts that haven't actually changed since our last sync.
  defp filter_existing_contacts(user, contacts) do
    hubspot_ids = Enum.map(contacts, & &1["id"])
    existing_sync_times = Agentleguide.Rag.get_hubspot_contact_sync_times(user, hubspot_ids)

    Enum.filter(contacts, fn contact ->
      contact_id = contact["id"]
      last_modified = get_in(contact, ["properties", "lastmodifieddate"])

      case {Map.get(existing_sync_times, contact_id), last_modified} do
        {nil, _} ->
          # New contact
          true

        {existing_sync, contact_modified} when is_binary(contact_modified) ->
          # Parse HubSpot timestamp and compare
          with {contact_ms, ""} <- Integer.parse(contact_modified),
               contact_datetime <- DateTime.from_unix!(contact_ms, :millisecond) do
            DateTime.compare(contact_datetime, existing_sync) == :gt
          else
            # If parsing fails, sync to be safe
            _ -> true
          end

        _ ->
          # If we can't determine, sync to be safe
          true
      end
    end)
  end

  @doc """
  Fetch contacts from HubSpot API (original method - now deprecated).
  Use fetch_new_contacts/2 for incremental sync.
  """
  def fetch_contacts(user) do
    url =
      "#{@hubspot_api_base}/crm/v3/objects/contacts?limit=100&properties=email,firstname,lastname,phone,company,notes_last_contacted,notes_last_updated,notes_next_activity_date"

    case make_hubspot_request(user, url) do
      {:ok, %{"results" => contacts}} ->
        {:ok, contacts}

      {:ok, %{}} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Store HubSpot contacts in our database.
  """
  def store_contacts(user, contacts) do
    results =
      Enum.map(contacts, fn contact ->
        case store_contact(user, contact) do
          {:ok, stored_contact} ->
            {:ok, stored_contact}

          {:error, reason} ->
            Logger.warning("Failed to store contact #{contact["id"]}: #{inspect(reason)}")
            {:error, reason}
        end
      end)

    successes = Enum.filter(results, &match?({:ok, _}, &1))
    {:ok, successes}
  end

  defp store_contact(user, contact_data) do
    hubspot_id = contact_data["id"]
    properties = contact_data["properties"] || %{}

    contact_attrs = %{
      hubspot_id: hubspot_id,
      email: properties["email"],
      first_name: properties["firstname"],
      last_name: properties["lastname"],
      phone: properties["phone"],
      company: properties["company"],
      notes_last_contacted: properties["notes_last_contacted"],
      notes_last_updated: properties["notes_last_updated"],
      notes_next_activity_date: properties["notes_next_activity_date"],
      last_synced_at: DateTime.utc_now()
    }

    case Agentleguide.Rag.upsert_hubspot_contact(user, contact_attrs) do
      {:ok, contact} ->
        # Queue embedding generation as a background job
        %{user_id: user.id, contact_id: contact.id}
        |> Agentleguide.Jobs.EmbeddingJob.new()
        |> Oban.insert()

        {:ok, contact}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Create a new contact in HubSpot.
  """
  def create_contact(user, contact_attrs) do
    url = "#{@hubspot_api_base}/crm/v3/objects/contacts"

    properties =
      %{
        "email" => contact_attrs[:email],
        "firstname" => contact_attrs[:first_name],
        "lastname" => contact_attrs[:last_name],
        "phone" => contact_attrs[:phone],
        "company" => contact_attrs[:company]
      }
      |> Enum.filter(fn {_k, v} -> v && String.trim(v) != "" end)
      |> Enum.into(%{})

    body = %{
      "properties" => properties
    }

    case make_hubspot_request(user, url, :post, body) do
      {:ok, contact_data} ->
        # Store the new contact locally
        store_contact(user, contact_data)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Send an email via HubSpot (if available) or fallback to Gmail.
  """
  def send_email(user, to_email, subject, body) do
    # For now, we'll use Gmail to send emails
    # In the future, we could integrate HubSpot's email sending capabilities
    Agentleguide.Services.Google.GmailService.send_email(user, to_email, subject, body)
  end

  @doc """
  Debug function to check HubSpot token status and force refresh if needed.
  Useful for testing and troubleshooting token issues.
  """
  def debug_token_status(user) do
    case user.hubspot_token_expires_at do
      nil ->
        {:ok,
         %{
           status: :no_expiry_set,
           has_access_token: !is_nil(user.hubspot_access_token),
           has_refresh_token: !is_nil(user.hubspot_refresh_token)
         }}

      expiry_time ->
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())

        status =
          cond do
            seconds_until_expiry <= 0 -> :expired
            seconds_until_expiry <= 300 -> :expiring_soon
            true -> :valid
          end

        {:ok,
         %{
           status: status,
           expires_at: expiry_time,
           seconds_until_expiry: seconds_until_expiry,
           has_access_token: !is_nil(user.hubspot_access_token),
           has_refresh_token: !is_nil(user.hubspot_refresh_token)
         }}
    end
  end

  @doc """
  Refresh the HubSpot access token using the refresh token.
  HubSpot access tokens expire after 30 minutes.
  """
  def refresh_access_token(user) do
    if user.hubspot_refresh_token do
      url = "#{@hubspot_api_base}/oauth/v1/token"

      body = %{
        "grant_type" => "refresh_token",
        "client_id" => System.get_env("HUBSPOT_CLIENT_ID"),
        "client_secret" => System.get_env("HUBSPOT_CLIENT_SECRET"),
        "refresh_token" => user.hubspot_refresh_token
      }

      headers = [
        {"Content-Type", "application/x-www-form-urlencoded"}
      ]

      # HubSpot expects form-encoded data for token refresh
      form_body = URI.encode_query(body)
      request = Finch.build(:post, url, headers, form_body)

      case Finch.request(request, Agentleguide.Finch) do
        {:ok, %{status: 200, body: response_body}} ->
          case Jason.decode(response_body) do
            {:ok, %{"access_token" => access_token, "expires_in" => expires_in} = token_data} ->
              # Calculate expiry time
              expires_at = DateTime.add(DateTime.utc_now(), expires_in, :second)

              # Update user with new token
              user_params = %{
                hubspot_access_token: access_token,
                hubspot_token_expires_at: expires_at
              }

              # Update refresh token if provided (HubSpot may issue a new one)
              user_params =
                if token_data["refresh_token"] do
                  Map.put(user_params, :hubspot_refresh_token, token_data["refresh_token"])
                else
                  user_params
                end

              case Agentleguide.Accounts.update_user(user, user_params) do
                {:ok, updated_user} ->
                  Logger.info("Successfully refreshed HubSpot token for user #{user.id}")
                  {:ok, updated_user}

                {:error, changeset} ->
                  Logger.error(
                    "Failed to update user with new HubSpot token: #{inspect(changeset)}"
                  )

                  {:error, :update_failed}
              end

            {:error, error} ->
              Logger.error("Failed to parse HubSpot token refresh response: #{inspect(error)}")
              {:error, :json_decode_error}
          end

        {:ok, %{status: 400, body: response_body}} ->
          Logger.error("HubSpot token refresh failed with 400: #{response_body}")

          case Jason.decode(response_body) do
            {:ok, %{"error" => "invalid_grant"}} ->
              # Refresh token is invalid/expired - user needs to reconnect
              Logger.error("HubSpot refresh token expired for user #{user.id}")
              {:error, :refresh_token_expired}

            _ ->
              {:error, :bad_request}
          end

        {:ok, %{status: 401}} ->
          Logger.error("HubSpot token refresh authentication failed for user #{user.id}")
          {:error, :auth_failed}

        {:ok, %{status: status, body: response_body}} ->
          Logger.error("HubSpot token refresh failed with status #{status}: #{response_body}")
          {:error, {:api_error, status}}

        {:error, error} ->
          Logger.error("HubSpot token refresh request failed: #{inspect(error)}")
          {:error, {:request_failed, error}}
      end
    else
      Logger.warning(
        "Cannot refresh HubSpot token for user #{user.id}: no refresh token available"
      )

      {:error, :no_refresh_token}
    end
  end

  defp make_hubspot_request(user, url, method \\ :get, body \\ nil) do
    # Check if token needs refresh before making the request
    user =
      case check_and_refresh_token_if_needed(user) do
        {:ok, updated_user} -> updated_user
        # Continue with current user if refresh fails
        {:error, _reason} -> user
      end

    headers = [
      {"Authorization", "Bearer #{user.hubspot_access_token}"},
      {"Content-Type", "application/json"}
    ]

    request =
      case method do
        :get -> Finch.build(:get, url, headers)
        :post -> Finch.build(:post, url, headers, Jason.encode!(body))
        :put -> Finch.build(:put, url, headers, Jason.encode!(body))
        :delete -> Finch.build(:delete, url, headers)
      end

    case Finch.request(request, Agentleguide.Finch) do
      {:ok, %{status: status, body: response_body}} when status in 200..299 ->
        case Jason.decode(response_body) do
          {:ok, data} -> {:ok, data}
          {:error, error} -> {:error, {:json_decode_error, error}}
        end

      {:ok, %{status: 401}} ->
        Logger.error("HubSpot API authentication failed for user #{user.id}")
        {:error, :auth_failed}

      {:ok, %{status: status, body: response_body}} ->
        Logger.error("HubSpot API error #{status}: #{response_body}")
        {:error, {:api_error, status, response_body}}

      {:error, error} ->
        Logger.error("HubSpot API request failed: #{inspect(error)}")
        {:error, {:request_failed, error}}
    end
  end

  # Check if token is expiring soon and refresh if needed
  defp check_and_refresh_token_if_needed(user) do
    case user.hubspot_token_expires_at do
      nil ->
        {:ok, user}

      expiry_time ->
        # Refresh if token expires in the next 5 minutes
        seconds_until_expiry = DateTime.diff(expiry_time, DateTime.utc_now())

        if seconds_until_expiry <= 300 do
          case refresh_access_token(user) do
            {:ok, updated_user} ->
              Logger.debug("Auto-refreshed HubSpot token for user #{user.id}")
              {:ok, updated_user}

            {:error, reason} ->
              Logger.warning(
                "Failed to auto-refresh HubSpot token for user #{user.id}: #{inspect(reason)}"
              )

              {:error, reason}
          end
        else
          {:ok, user}
        end
    end
  end
end

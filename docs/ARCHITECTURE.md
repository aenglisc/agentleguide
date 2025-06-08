# AgentleGuide Architecture

## Project Structure

The AgentleGuide project has been organized into a clean, modular architecture that separates concerns and makes the codebase more maintainable.

### Directory Structure

```
lib/agentleguide/
├── 📊 Core Business Logic
│   ├── accounts.ex              # User management and authentication
│   ├── accounts/user.ex         # User schema
│   ├── tasks.ex                 # Task management system
│   ├── tasks/                   # Task-related schemas
│   ├── rag.ex                   # RAG (Retrieval-Augmented Generation) system
│   └── rag/                     # RAG schemas (emails, contacts, embeddings)
│
├── 🔧 External Services
│   ├── services/ai/             # AI and ML services
│   │   ├── ai_service.ex        # Core AI API interactions
│   │   ├── ai_tools.ex          # Tool calling system
│   │   ├── ai_agent.ex          # Intelligent agent orchestration
│   │   └── chat_service.ex      # RAG-powered chat
│   │
│   ├── services/google/         # Google API integrations
│   │   ├── gmail_service.ex     # Gmail API interactions
│   │   └── calendar_service.ex  # Google Calendar API
│   │
│   └── services/hubspot/        # HubSpot CRM integration
│       ├── hubspot_service.ex   # HubSpot API interactions
│       └── hubspot_service_behaviour.ex  # Service interface
│
├── ⚙️ Background Jobs
│   ├── jobs/email_sync_job.ex           # Gmail synchronization
│   ├── jobs/hubspot_sync_job.ex         # HubSpot data sync
│   ├── jobs/hubspot_token_refresh_job.ex # OAuth token management
│   └── jobs/embedding_job.ex            # Vector embedding generation
│
└── 🏛️ Infrastructure
    ├── application.ex           # Application supervisor
    ├── repo.ex                  # Database repository
    ├── mailer.ex               # Email delivery
    ├── presence.ex             # User presence tracking
    ├── postgrex_types.ex       # Custom PostgreSQL types
    └── ueberauth/              # OAuth strategies
```

## Design Principles

### 1. **Separation of Concerns**
- **Core Business Logic**: Domain-specific logic (accounts, tasks, RAG)
- **External Services**: Third-party API integrations grouped by provider
- **Background Jobs**: Asynchronous processing tasks
- **Infrastructure**: Application plumbing and configuration

### 2. **Service Organization**
Services are grouped by provider/domain:
- **AI Services**: All AI/ML related functionality
- **Google Services**: Gmail, Calendar, and other Google APIs
- **HubSpot Services**: CRM and sales automation

### 3. **Module Naming Convention**
```elixir
# Before reorganization
Agentleguide.HubspotService

# After reorganization  
Agentleguide.Services.Hubspot.HubspotService
```

### 4. **Test Structure**
Tests mirror the lib structure:
```
test/agentleguide/
├── services/ai/ai_tools_test.exs
├── jobs/hubspot_token_refresh_job_test.exs
└── accounts_test.exs
```

## Benefits of This Structure

### ✅ **Improved Maintainability**
- Related functionality is grouped together
- Clear boundaries between different concerns
- Easier to locate and modify specific features

### ✅ **Better Scalability**
- New services can be added without cluttering the main directory
- Service-specific logic is contained within its namespace
- Background jobs are clearly separated from business logic

### ✅ **Enhanced Testing**
- Test structure mirrors code structure
- Service mocking is more organized
- Clear separation of unit vs integration tests

### ✅ **Developer Experience**
- Intuitive file organization
- Reduced cognitive load when navigating codebase
- Clear documentation structure

## Migration Notes

All module references have been updated throughout the codebase:
- Service modules moved to nested namespaces
- Import/alias statements updated
- Test files reorganized to match structure
- Documentation moved to dedicated `docs/` directory

The reorganization maintains full backward compatibility - all existing functionality works exactly as before, just with a cleaner structure. 
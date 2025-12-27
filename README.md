# Aria - Personal AI Assistant

A voice-first iOS personal assistant powered by **Gemini 3 Flash Preview** that consolidates communications, productivity, finances, and shopping into a single intelligent interface.

## Features

- **Voice-First Interface**: Natural voice interaction with <50ms perceived response time
- **Email Management**: Unified inbox across Gmail, Outlook, and iCloud
- **Calendar Intelligence**: Smart scheduling with conflict detection
- **Task Extraction**: Auto-detect action items from emails and conversations
- **Banking Integration**: Account balances, spending insights via Plaid
- **Shopping**: Instacart integration for grocery ordering
- **Attention System**: Shows only what demands immediate attention

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   PRESENTATION                       │
│  SwiftUI Views │ Voice UI │ Haptic │ Notifications  │
├─────────────────────────────────────────────────────┤
│                   COORDINATION                       │
│  ConversationManager │ AttentionEngine │ SyncCoord  │
├─────────────────────────────────────────────────────┤
│                   INTELLIGENCE                       │
│  GeminiLiveClient │ LocalIntentClassifier │ Vector  │
├─────────────────────────────────────────────────────┤
│                    SERVICES                          │
│  Email │ Calendar │ Contacts │ Banking │ Shopping   │
├─────────────────────────────────────────────────────┤
│                   DATA LAYER                         │
│  SQLite + GRDB │ sqlite-vec │ Keychain              │
└─────────────────────────────────────────────────────┘
```

## Requirements

- iOS 17.0+
- Xcode 15.0+
- Swift 5.9+

## Setup

1. Clone the repository:
```bash
git clone https://github.com/nimag/aria-assistant.git
cd aria-assistant
```

2. Open in Xcode:
```bash
open Package.swift
```

3. Configure API keys (required):
   - **Gemini API Key**: Get from [Google AI Studio](https://ai.google.dev/)
   - **Plaid API Keys**: Get from [Plaid Dashboard](https://dashboard.plaid.com/)
   - **Instacart API**: Apply at [Instacart Developer Platform](https://www.instacart.com/company/business/developers)

4. Add keys to your environment or Keychain:
```swift
// In Configuration.swift or via environment
GEMINI_API_KEY=your_key_here
```

5. Build and run

## Project Structure

```
Aria/
├── App/
│   └── AriaApp.swift           # App entry point
├── Core/
│   ├── AI/
│   │   ├── GeminiLiveClient.swift    # Gemini 3 Flash Preview client
│   │   ├── EmbeddingService.swift    # Vector embeddings
│   │   ├── LocalIntentClassifier.swift
│   │   └── ConversationManager.swift
│   ├── Database/
│   │   ├── DatabaseManager.swift     # SQLite + GRDB
│   │   └── VectorSearch.swift        # Semantic search
│   ├── Models/
│   │   ├── AttentionItem.swift
│   │   ├── Task.swift
│   │   ├── Email.swift
│   │   ├── CalendarEvent.swift
│   │   ├── Contact.swift
│   │   ├── Transaction.swift
│   │   └── ShoppingOrder.swift
│   ├── Services/
│   │   ├── EmailService.swift
│   │   ├── CalendarService.swift
│   │   ├── ContactsService.swift
│   │   ├── BankingService.swift
│   │   └── ShoppingService.swift
│   └── Voice/
│       ├── AudioCaptureManager.swift
│       ├── WakeWordDetector.swift
│       └── HapticFeedback.swift
├── Features/
│   └── Attention/
│       └── AttentionEngine.swift
└── UI/
    ├── Screens/
    │   ├── MainView.swift
    │   ├── AttentionItemsView.swift
    │   └── SettingsView.swift
    └── Components/
```

## Key Technologies

- **Gemini 3 Flash Preview**: Native audio processing with streaming responses
- **GRDB**: SQLite wrapper for Swift with excellent performance
- **sqlite-vec**: Vector search for semantic queries
- **Starscream**: WebSocket client for Gemini Live API
- **Plaid Link SDK**: Secure banking integration
- **EventKit/Contacts/CallKit**: iOS system integration

## Voice Commands

```
COMMUNICATION
├── "Read my important emails"
├── "Reply to [person]: [message]"
├── "Call [contact]"
└── "Text [contact]: [message]"

CALENDAR
├── "What's my day look like?"
├── "Schedule [event] for [time]"
└── "When am I free this week?"

TASKS
├── "Add [task] to my list"
├── "What should I focus on?"
└── "What's overdue?"

SHOPPING
├── "Order groceries for the week"
├── "Add [items] to my cart"
└── "What's the status of my order?"

BANKING
├── "How much did I spend this week?"
├── "What's my account balance?"
└── "Any unusual transactions?"
```

## Privacy

- **Local-first**: All data stored on-device using encrypted SQLite
- **No cloud sync** by default (optional Vertex AI for multi-device)
- **Biometric authentication** for sensitive queries
- **Voice processing**: Audio streamed to Gemini for processing only

## License

MIT License - see LICENSE file for details

## Contributing

Contributions welcome! Please read CONTRIBUTING.md before submitting PRs.

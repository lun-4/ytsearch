# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

YtSearch is a Phoenix backend service that powers a VRChat world providing YouTube search and video functionality. It acts as a proxy between VRChat clients and YouTube/Piped, with specialized optimizations for VRChat's constraints.

## Common Commands

### Development
- `mix setup` - Install dependencies and setup databases
- `mix phx.server` - Start development server
- `iex -S mix phx.server` - Start server with interactive shell

### Testing
- `mix test` - Run standard tests
- `mix testall` - Run all tests including slow/slower tagged tests
- `mix test --include slow` - Run tests with slow tag
- `mix test test/path/to/specific_test.exs` - Run specific test file

### Code Quality
- `mix lint` - Run formatter check, unused deps check, and Credo
- `mix format` - Format code
- `mix credo --all --strict` - Run strict linting

### Database
- `mix ecto.migrate` - Run database migrations
- `mix ecto.reset` - Drop and recreate databases
- `mix ecto.create` - Create databases

## Architecture

### Core Concept: Slot-Based Resource Management
The application revolves around "slots" - fixed-size resource pools with TTL expiration designed for VRChat's URL constraints (~150,000 video ID limit). Each slot type has its own SQLite database and repository:

- **VideoSlots** (`SlotRepo`) - Video metadata and links
- **SearchSlots** (`SearchSlotRepo`) - Search results with pagination
- **ChannelSlots** (`ChannelSlotRepo`) - Channel information
- **PlaylistSlots** (`PlaylistSlotRepo`) - Playlist data
- **Thumbnails** (`ThumbnailRepo`) - Image storage and atlas generation

### Key Components

**Controllers & Routes:**
- `SearchController` - Main search API (`/api/search`, `/api/trending`)
- `SlotController` - Video metadata serving (`/api/video/:id`)
- `ThumbnailAtlasController` - Image serving (`/api/thumbnail_atlas/:id`)
- Short URL routes (`/a/6/*`) for VRChat's URL constraints

**Core Services:**
- `Youtube` module - Piped API integration and error handling
- `MetadataExtractor.Worker` - GenServer workers for metadata extraction
- `Slot` utilities - Resource management and TTL handling
- `ThumbnailAtlas` - Image processing and combination

**Background Services:**
- `RepoJanitor` - Cleanup expired slots
- `SlotUsageMeter` - Prometheus metrics collection
- `RepoFreelistMeter` - Monitor available slot capacity

### VRChat-Specific Adaptations

**Unity Client Restrictions:**
- Search endpoints only accept Unity user agents
- JSON responses use VRCJson format (strips braces due to parser limitations)
- Error handling serves pre-rendered MP4 error videos

**URL Constraints:**
- Bounded slot IDs to fit VRChat world limits
- Short `/a/6/*` routes for reduced URL length
- ID recycling when slots expire

**Error Handling:**
YouTube content unavailability is mapped to specific error videos covering age restrictions, geo-blocking, DMCA, private content, etc.

## Database Architecture

Multiple SQLite databases with read replicas:
- Each slot type has dedicated database files
- Migrations in `priv/{repo_name}/migrations/`
- Database paths configured in `config/` files
- Uses Ecto with SQLite adapter

## External Dependencies

**Piped Integration:**
- Primary data source instead of YouTube API
- Implements comprehensive error handling and rate limiting
- Configured Piped instance URLs in application config

**Image Processing:**
- ImageMagick via Mogrify for thumbnail manipulation
- Custom atlas generation for combining multiple images

**Monitoring:**
- Prometheus metrics for all major operations
- Phoenix LiveDashboard for development monitoring
- Custom metrics for slot usage, API latencies, error rates

## Development Notes

- Run `mix ecto.create` for each repo when setting up locally
- Tests use ExMachina factories for data generation
- Mock server scripts in `test/scripts/` for Piped API simulation
- Thumbnail test data in `test/support/files/` and `test/support/piped_outputs/`
- Application designed for high read loads with read replica support
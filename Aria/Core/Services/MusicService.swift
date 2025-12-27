import Foundation
import MusicKit
import MediaPlayer

/// Music service using MusicKit
actor MusicService {
    // MARK: - Player

    private let player = ApplicationMusicPlayer.shared

    // MARK: - State

    private var currentQueue: [Song] = []
    private var recentlyPlayed: [Song] = []
    private var searchResults: MusicItemCollection<Song>?

    // MARK: - Authorization

    func requestAuthorization() async -> Bool {
        let status = await MusicAuthorization.request()
        return status == .authorized
    }

    var isAuthorized: Bool {
        MusicAuthorization.currentStatus == .authorized
    }

    // MARK: - Playback Control

    func play() async throws {
        try await player.play()
    }

    func pause() {
        player.pause()
    }

    func stop() {
        player.stop()
    }

    func skipToNext() async throws {
        try await player.skipToNextEntry()
    }

    func skipToPrevious() async throws {
        try await player.skipToPreviousEntry()
    }

    func seek(to time: TimeInterval) async {
        player.playbackTime = time
    }

    func setVolume(_ volume: Float) {
        MPVolumeView.setVolume(volume)
    }

    // MARK: - Queue Management

    func setQueue(songs: [Song]) async throws {
        player.queue = ApplicationMusicPlayer.Queue(for: songs)
        currentQueue = songs
        try await player.play()
    }

    func addToQueue(song: Song) async throws {
        try await player.queue.insert(song, position: .tail)
        currentQueue.append(song)
    }

    func addToQueue(songs: [Song]) async throws {
        for song in songs {
            try await player.queue.insert(song, position: .tail)
        }
        currentQueue.append(contentsOf: songs)
    }

    func playNext(song: Song) async throws {
        try await player.queue.insert(song, position: .afterCurrentEntry)
    }

    func clearQueue() {
        player.queue = ApplicationMusicPlayer.Queue(for: [] as [Song])
        currentQueue = []
    }

    // MARK: - Now Playing

    func getNowPlaying() async -> NowPlayingInfo? {
        guard let entry = player.queue.currentEntry else { return nil }

        let state: PlaybackState = switch player.state.playbackStatus {
        case .playing: .playing
        case .paused: .paused
        case .stopped: .stopped
        default: .stopped
        }

        if case let .song(song) = entry.item {
            return NowPlayingInfo(
                title: song.title,
                artist: song.artistName,
                album: song.albumTitle ?? "",
                duration: song.duration ?? 0,
                currentTime: player.playbackTime,
                artworkUrl: song.artwork?.url(width: 300, height: 300),
                isPlaying: player.state.playbackStatus == .playing,
                state: state
            )
        }

        return nil
    }

    var playbackState: PlaybackState {
        switch player.state.playbackStatus {
        case .playing: return .playing
        case .paused: return .paused
        case .stopped: return .stopped
        default: return .stopped
        }
    }

    // MARK: - Search

    func search(query: String) async throws -> [MusicSearchResult] {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self, Album.self, Artist.self, Playlist.self])
        request.limit = 25

        let response = try await request.response()

        var results: [MusicSearchResult] = []

        for song in response.songs {
            results.append(MusicSearchResult(
                id: song.id.rawValue,
                type: .song,
                title: song.title,
                subtitle: song.artistName,
                artworkUrl: song.artwork?.url(width: 100, height: 100),
                musicKitId: song.id.rawValue
            ))
        }

        for album in response.albums {
            results.append(MusicSearchResult(
                id: album.id.rawValue,
                type: .album,
                title: album.title,
                subtitle: album.artistName,
                artworkUrl: album.artwork?.url(width: 100, height: 100),
                musicKitId: album.id.rawValue
            ))
        }

        for artist in response.artists {
            results.append(MusicSearchResult(
                id: artist.id.rawValue,
                type: .artist,
                title: artist.name,
                subtitle: nil,
                artworkUrl: artist.artwork?.url(width: 100, height: 100),
                musicKitId: artist.id.rawValue
            ))
        }

        for playlist in response.playlists {
            results.append(MusicSearchResult(
                id: playlist.id.rawValue,
                type: .playlist,
                title: playlist.name,
                subtitle: playlist.curatorName,
                artworkUrl: playlist.artwork?.url(width: 100, height: 100),
                musicKitId: playlist.id.rawValue
            ))
        }

        return results
    }

    func searchSongs(query: String) async throws -> [Song] {
        var request = MusicCatalogSearchRequest(term: query, types: [Song.self])
        request.limit = 25

        let response = try await request.response()
        searchResults = response.songs
        return Array(response.songs)
    }

    // MARK: - Play by Name

    func playSong(named name: String) async throws {
        let songs = try await searchSongs(query: name)
        guard let song = songs.first else {
            throw MusicServiceError.notFound
        }
        try await setQueue(songs: [song])
    }

    func playArtist(named name: String, shuffle: Bool = true) async throws {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 1

        let response = try await request.response()
        guard let artist = response.artists.first else {
            throw MusicServiceError.notFound
        }

        // Get top songs
        let detailedArtist = try await artist.with([.topSongs])
        guard let songs = detailedArtist.topSongs else {
            throw MusicServiceError.notFound
        }

        var songArray = Array(songs)
        if shuffle {
            songArray.shuffle()
        }

        try await setQueue(songs: songArray)
    }

    func playAlbum(named name: String) async throws {
        var request = MusicCatalogSearchRequest(term: name, types: [Album.self])
        request.limit = 1

        let response = try await request.response()
        guard let album = response.albums.first else {
            throw MusicServiceError.notFound
        }

        let detailedAlbum = try await album.with([.tracks])
        guard let tracks = detailedAlbum.tracks else {
            throw MusicServiceError.notFound
        }

        let songs = tracks.compactMap { track -> Song? in
            if case let .song(song) = track {
                return song
            }
            return nil
        }

        try await setQueue(songs: songs)
    }

    func playPlaylist(named name: String, shuffle: Bool = false) async throws {
        var request = MusicCatalogSearchRequest(term: name, types: [Playlist.self])
        request.limit = 1

        let response = try await request.response()
        guard let playlist = response.playlists.first else {
            throw MusicServiceError.notFound
        }

        let detailedPlaylist = try await playlist.with([.tracks])
        guard let tracks = detailedPlaylist.tracks else {
            throw MusicServiceError.notFound
        }

        var songs = tracks.compactMap { track -> Song? in
            if case let .song(song) = track {
                return song
            }
            return nil
        }

        if shuffle {
            songs.shuffle()
        }

        try await setQueue(songs: songs)
    }

    // MARK: - Library

    func getLibrarySongs(limit: Int = 100) async throws -> [Song] {
        var request = MusicLibraryRequest<Song>()
        request.limit = limit

        let response = try await request.response()
        return Array(response.items)
    }

    func getLibraryAlbums(limit: Int = 50) async throws -> [Album] {
        var request = MusicLibraryRequest<Album>()
        request.limit = limit

        let response = try await request.response()
        return Array(response.items)
    }

    func getLibraryPlaylists() async throws -> [Playlist] {
        var request = MusicLibraryRequest<Playlist>()

        let response = try await request.response()
        return Array(response.items)
    }

    func getLibraryArtists(limit: Int = 50) async throws -> [Artist] {
        var request = MusicLibraryRequest<Artist>()
        request.limit = limit

        let response = try await request.response()
        return Array(response.items)
    }

    func getRecentlyPlayed(limit: Int = 20) async throws -> [Song] {
        var request = MusicRecentlyPlayedRequest<Song>()
        request.limit = limit

        let response = try await request.response()
        let songs = Array(response.items)
        recentlyPlayed = songs
        return songs
    }

    // MARK: - Recommendations

    func getRecommendations() async throws -> [MusicSearchResult] {
        let request = MusicPersonalRecommendationsRequest()
        let response = try await request.response()

        var results: [MusicSearchResult] = []

        for recommendation in response.recommendations {
            for item in recommendation.items {
                if case let .playlist(playlist) = item {
                    results.append(MusicSearchResult(
                        id: playlist.id.rawValue,
                        type: .playlist,
                        title: playlist.name,
                        subtitle: playlist.curatorName,
                        artworkUrl: playlist.artwork?.url(width: 100, height: 100),
                        musicKitId: playlist.id.rawValue
                    ))
                } else if case let .album(album) = item {
                    results.append(MusicSearchResult(
                        id: album.id.rawValue,
                        type: .album,
                        title: album.title,
                        subtitle: album.artistName,
                        artworkUrl: album.artwork?.url(width: 100, height: 100),
                        musicKitId: album.id.rawValue
                    ))
                }
            }
        }

        return results
    }

    // MARK: - Genre/Mood Playback

    func playGenre(_ genre: String, shuffle: Bool = true) async throws {
        var request = MusicCatalogSearchRequest(term: "\(genre) music", types: [Playlist.self])
        request.limit = 5

        let response = try await request.response()
        guard let playlist = response.playlists.first else {
            throw MusicServiceError.notFound
        }

        try await playPlaylist(named: playlist.name, shuffle: shuffle)
    }

    func playMood(_ mood: String) async throws {
        // Map common moods to search terms
        let searchTerm: String
        switch mood.lowercased() {
        case "happy", "upbeat": searchTerm = "happy hits"
        case "sad", "melancholy": searchTerm = "sad songs"
        case "relaxed", "calm", "chill": searchTerm = "chill vibes"
        case "energetic", "workout": searchTerm = "workout motivation"
        case "focus", "concentration": searchTerm = "focus music"
        case "party": searchTerm = "party hits"
        case "romantic", "love": searchTerm = "love songs"
        case "sleep", "bedtime": searchTerm = "sleep sounds"
        default: searchTerm = mood
        }

        try await playPlaylist(named: searchTerm, shuffle: true)
    }

    // MARK: - Radio

    func playRadio(basedOn song: Song) async throws {
        let station = try await Station(startingWith: song)
        player.queue = ApplicationMusicPlayer.Queue(for: [station])
        try await player.play()
    }

    func playRadio(basedOnArtist name: String) async throws {
        var request = MusicCatalogSearchRequest(term: name, types: [Artist.self])
        request.limit = 1

        let response = try await request.response()
        guard let artist = response.artists.first else {
            throw MusicServiceError.notFound
        }

        let station = try await Station(startingWith: artist)
        player.queue = ApplicationMusicPlayer.Queue(for: [station])
        try await player.play()
    }

    // MARK: - Shuffle & Repeat

    func setShuffle(_ enabled: Bool) {
        player.state.shuffleMode = enabled ? .songs : .off
    }

    func setRepeat(_ mode: RepeatMode) {
        player.state.repeatMode = switch mode {
        case .off: .none
        case .one: .one
        case .all: .all
        }
    }

    var shuffleEnabled: Bool {
        player.state.shuffleMode == .songs
    }

    var repeatMode: RepeatMode {
        switch player.state.repeatMode {
        case .one: return .one
        case .all: return .all
        default: return .off
        }
    }

    // MARK: - Favorites

    func addToLibrary(_ song: Song) async throws {
        try await MusicLibrary.shared.add(song)
    }

    func addToLibrary(_ album: Album) async throws {
        try await MusicLibrary.shared.add(album)
    }

    func addToLibrary(_ playlist: Playlist) async throws {
        try await MusicLibrary.shared.add(playlist)
    }

    // MARK: - Voice Commands

    func handleVoiceCommand(_ command: String) async throws -> String {
        let lower = command.lowercased()

        if lower.contains("play") {
            if lower.contains("pause") || lower.contains("stop") {
                pause()
                return "Paused"
            }

            // Extract what to play
            let playIndex = lower.range(of: "play")!.upperBound
            let query = String(lower[playIndex...]).trimmingCharacters(in: .whitespaces)

            if query.isEmpty {
                try await play()
                return "Playing"
            }

            if lower.contains("album") {
                let albumName = query.replacingOccurrences(of: "album", with: "").trimmingCharacters(in: .whitespaces)
                try await playAlbum(named: albumName)
                return "Playing album: \(albumName)"
            } else if lower.contains("artist") || lower.contains("by") {
                var artistName = query
                if let range = artistName.range(of: "by ") {
                    artistName = String(artistName[range.upperBound...])
                } else {
                    artistName = artistName.replacingOccurrences(of: "artist", with: "").trimmingCharacters(in: .whitespaces)
                }
                try await playArtist(named: artistName)
                return "Playing music by \(artistName)"
            } else if lower.contains("playlist") {
                let playlistName = query.replacingOccurrences(of: "playlist", with: "").trimmingCharacters(in: .whitespaces)
                try await playPlaylist(named: playlistName)
                return "Playing playlist: \(playlistName)"
            } else {
                try await playSong(named: query)
                return "Playing: \(query)"
            }
        }

        if lower.contains("skip") || lower.contains("next") {
            try await skipToNext()
            return "Skipped to next song"
        }

        if lower.contains("previous") || lower.contains("back") {
            try await skipToPrevious()
            return "Playing previous song"
        }

        if lower.contains("shuffle") {
            let enable = !lower.contains("off")
            setShuffle(enable)
            return "Shuffle \(enable ? "on" : "off")"
        }

        if lower.contains("repeat") {
            if lower.contains("off") {
                setRepeat(.off)
                return "Repeat off"
            } else if lower.contains("one") || lower.contains("song") {
                setRepeat(.one)
                return "Repeating current song"
            } else {
                setRepeat(.all)
                return "Repeating all"
            }
        }

        if lower.contains("what") && (lower.contains("playing") || lower.contains("song")) {
            if let nowPlaying = await getNowPlaying() {
                return "\(nowPlaying.title) by \(nowPlaying.artist)"
            }
            return "Nothing is playing"
        }

        throw MusicServiceError.unknownCommand
    }
}

// MARK: - Supporting Types

struct NowPlayingInfo {
    let title: String
    let artist: String
    let album: String
    let duration: TimeInterval
    let currentTime: TimeInterval
    let artworkUrl: URL?
    let isPlaying: Bool
    let state: PlaybackState

    var progress: Double {
        guard duration > 0 else { return 0 }
        return currentTime / duration
    }

    var remainingTime: TimeInterval {
        duration - currentTime
    }
}

struct MusicSearchResult: Identifiable {
    let id: String
    let type: MusicItemType
    let title: String
    let subtitle: String?
    let artworkUrl: URL?
    let musicKitId: String
}

enum MusicItemType {
    case song
    case album
    case artist
    case playlist
    case station
}

enum PlaybackState {
    case playing
    case paused
    case stopped
}

enum RepeatMode {
    case off
    case one
    case all
}

// MARK: - MPVolumeView Extension

extension MPVolumeView {
    static func setVolume(_ volume: Float) {
        let volumeView = MPVolumeView()
        let slider = volumeView.subviews.first(where: { $0 is UISlider }) as? UISlider
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
            slider?.value = volume
        }
    }
}

// MARK: - Errors

enum MusicServiceError: Error, LocalizedError {
    case notAuthorized
    case notFound
    case playbackFailed
    case unknownCommand

    var errorDescription: String? {
        switch self {
        case .notAuthorized: return "Music access not authorized"
        case .notFound: return "Music not found"
        case .playbackFailed: return "Playback failed"
        case .unknownCommand: return "Unknown music command"
        }
    }
}

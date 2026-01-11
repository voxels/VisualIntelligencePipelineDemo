import Foundation
import MusicKit
import DiverShared

public struct AppleMusicEnrichmentService: LinkEnrichmentService {
    
    public init() {}
    
    public func enrich(url: URL) async throws -> EnrichmentData? {
        // Quick check for Apple Music domain
        guard let host = url.host, host.contains("music.apple.com") else { return nil }
        
        // 1. Attempt to extract IDs
        let (songID, albumID, playlistID) = extractIDs(from: url)
        
        do {
            // 2. Prioritize Song, then Album, then Playlist
            if let sID = songID {
                return try await fetchSong(id: sID)
            }
            if let aID = albumID {
                return try await fetchAlbum(id: aID)
            }
            if let pID = playlistID {
                return try await fetchPlaylist(id: pID)
            }
        } catch {
            print("🎵 Apple Music Link Enrichment Failed: \(error)")
            // Fallback to nil to let WebView service handle it
            return nil
        }
        
        return nil
    }
    
    // MARK: - ID Extraction
    
    private func extractIDs(from url: URL) -> (song: MusicItemID?, album: MusicItemID?, playlist: MusicItemID?) {
        var songID: MusicItemID?
        var albumID: MusicItemID?
        var playlistID: MusicItemID?
        
        // 1. Check query param 'i' for Song ID (e.g. ?i=123456)
        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let songItem = components.queryItems?.first(where: { $0.name == "i" })?.value {
            songID = MusicItemID(songItem)
        }
        
        // 2. URL Path Parsing
        let pathComponents = url.pathComponents
        // Paths usually: /<storefront>/<type>/<name>/<id>
        // e.g. /us/album/sucker/1447543209
        
        if let last = pathComponents.last,
           // Basic check: usually numeric, but verify context
           !last.isEmpty {
             
             // Check the component before the ID for type
             let count = pathComponents.count
             if count >= 2 {
                 let type = pathComponents[count - 2]
                 let id = MusicItemID(last)
                 
                 if type == "album" {
                     albumID = id
                 } else if type == "playlist" {
                     playlistID = id
                 } else if type == "station" {
                     // Not handling stations yet
                 }
             }
        }
        
        return (songID, albumID, playlistID)
    }
    
    // MARK: - Fetchers
    
    private func fetchSong(id: MusicItemID) async throws -> EnrichmentData? {
        let request = MusicCatalogResourceRequest<Song>(matching: \.id, equalTo: id)
        let response = try await request.response()
        
        guard let song = response.items.first else { return nil }
        
        return EnrichmentData(
            title: song.title,
            descriptionText: "Song • \(song.artistName) • \(song.albumTitle ?? "")",
            image: song.artwork?.url(width: 512, height: 512)?.absoluteString,
            categories: song.genreNames,
            styleTags: ["Music", "Apple Music", "Song"],
            webContext: WebContext(
                siteName: "Apple Music",
                snapshotURL: song.url?.absoluteString
            )
        )
    }
    
    private func fetchAlbum(id: MusicItemID) async throws -> EnrichmentData? {
        let request = MusicCatalogResourceRequest<Album>(matching: \.id, equalTo: id)
        let response = try await request.response()
        
        guard let album = response.items.first else { return nil }
        
        return EnrichmentData(
            title: album.title,
            descriptionText: "Album • \(album.artistName) • \(album.trackCount) Songs",
            image: album.artwork?.url(width: 512, height: 512)?.absoluteString,
            categories: album.genreNames,
            styleTags: ["Music", "Apple Music", "Album"],
            webContext: WebContext(
                siteName: "Apple Music",
                snapshotURL: album.url?.absoluteString
            )
        )
    }
    
    private func fetchPlaylist(id: MusicItemID) async throws -> EnrichmentData? {
        let request = MusicCatalogResourceRequest<MusicKit.Playlist>(matching: \.id, equalTo: id)
        let response = try await request.response()
        
        guard let playlist = response.items.first else { return nil }
        
        let desc = playlist.shortDescription ?? "\(playlist.description)"
        
        return EnrichmentData(
            title: playlist.name,
            descriptionText: desc,
            image: playlist.artwork?.url(width: 512, height: 512)?.absoluteString,
            categories: [], // Playlists might not have genres directly
            styleTags: ["Music", "Apple Music", "Playlist"],
            webContext: WebContext(
                siteName: "Apple Music",
                snapshotURL: playlist.url?.absoluteString,
                textContent: playlist.curatorName.map { "Playlist by \($0)" }
            )
        )
    }
}

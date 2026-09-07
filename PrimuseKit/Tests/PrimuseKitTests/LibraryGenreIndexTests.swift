import Foundation
import Testing
@testable import PrimuseKit

@Suite("Library genre index")
struct LibraryGenreIndexTests {
    @Test("Equivalent labels share a category")
    func normalizesEquivalentLabels() {
        let index = LibraryGenreIndexBuilder.build(from: [
            song("a", genre: "  Pop  ", albumID: "one"),
            song("b", genre: "pop", albumID: "two"),
            song("c", genre: "ＰＯＰ", albumID: "two"),
        ])

        #expect(index.genres.count == 1)
        #expect(index.genres.first?.name == "Pop")
        #expect(index.genres.first?.songCount == 3)
        #expect(index.genres.first?.albumCount == 2)
    }

    @Test("Punctuation remains part of the label")
    func preservesCompoundLabels() {
        let index = LibraryGenreIndexBuilder.build(from: [
            song("a", genre: "R&B/Soul"),
            song("b", genre: "Rock, Live"),
        ])

        #expect(Set(index.genres.map(\.name)) == ["R&B/Soul", "Rock, Live"])
        #expect(index.genres.count == 2)
    }

    @Test("Missing labels are ignored")
    func ignoresMissingLabels() {
        let index = LibraryGenreIndexBuilder.build(from: [
            song("a", genre: nil),
            song("b", genre: "  \n "),
        ])

        #expect(index.genres.isEmpty)
        #expect(index.songIDsByGenreID.isEmpty)
    }

    @Test("Representative songs prefer artwork and distinct albums")
    func selectsRepresentativeSongs() {
        let index = LibraryGenreIndexBuilder.build(from: [
            song("blank", genre: "Jazz", albumID: "a", year: 2026),
            song("older", genre: "Jazz", albumID: "b", year: 2020, artwork: "b.jpg"),
            song("newer", genre: "Jazz", albumID: "c", year: 2025, artwork: "c.jpg"),
            song("same-album", genre: "Jazz", albumID: "c", year: 2026, artwork: "d.jpg"),
        ])

        let genre = index.genres.first
        #expect(genre?.albumCount == 3)
        #expect(genre?.representativeSongIDs == ["same-album", "older", "blank"])
    }

    @Test("Large categories preserve song order and first-seen albums")
    func indexesLargeCategory() {
        let songs = (0..<18_810).map { index in
            song(
                String(format: "%05d", index),
                genre: index.isMultiple(of: 2) ? " Pop " : "ＰＯＰ",
                albumID: "album-\(index % 240)",
                year: 2000 + index % 25,
                artwork: index.isMultiple(of: 10) ? "cover.jpg" : nil
            )
        }
        let started = ContinuousClock.now
        let index = LibraryGenreIndexBuilder.build(from: songs)
        print("Large genre index: \(started.duration(to: .now))")

        #expect(index.genres.count == 1)
        #expect(index.genres.first?.name == "Pop")
        #expect(index.genres.first?.songCount == songs.count)
        #expect(index.genres.first?.albumCount == 240)
        #expect(index.songIDsByGenreID["pop"] == songs.map(\.id))
        #expect(index.albumIDsByGenreID["pop"] == (0..<240).map { "album-\($0)" })
        #expect(index.genres.first?.representativeSongIDs == ["00020", "00070", "00120"])
    }

    private func song(
        _ id: String,
        genre: String?,
        albumID: String? = nil,
        year: Int? = nil,
        artwork: String? = nil
    ) -> Song {
        Song(
            id: id,
            title: id,
            albumID: albumID,
            duration: 180,
            fileFormat: .mp3,
            filePath: "\(id).mp3",
            sourceID: "source",
            genre: genre,
            year: year,
            coverArtFileName: artwork
        )
    }
}

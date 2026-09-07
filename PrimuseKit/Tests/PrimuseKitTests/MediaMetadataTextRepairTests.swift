import Foundation
import Testing
@testable import PrimuseKit

@Suite struct AlbumMetadataTextRepairTests {
    @Test func partiallyRestoresTruncatedAlbumWithoutGuessingItsLastCharacter() throws {
        let payload = Data("大人的情".utf8) + Data([0xE6, 0xAD]) + Data("?ARTIST=张宇".utf8)
        let decoded = try #require(TextEncodingRepair.decodeID3Text(payload, encodingByte: 3))
        #expect(decoded == "澶т汉鐨勬儏姝?ARTIST=寮犲畤")
        let album = MediaMetadataTextRepair.repairedAlbumTitle(decoded, artist: "张宇")
        #expect(album == "大人的情\u{FFFD}")
        #expect(TextEncodingRepair.hasUnrecoverableReplacement(in: try #require(album)))
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(album, artist: "张宇") == album)
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(decoded, artist: "另一位歌手") == decoded)
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(decoded, artist: nil) == decoded)
    }

    @Test func partiallyRestoresAlbumAfterAParserHasAlreadySplitItsFields() {
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "澶т汉鐨勬儏姝", artist: "张宇"
        ) == "大人的情\u{FFFD}")
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "澶т汉鐨勬儏姝\0ARTIST=寮犲畤", artist: "张宇"
        ) == "大人的情\u{FFFD}")
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "大人的情\u{FFFD}\u{FFFD}?ARTIST=张宇", artist: "张宇"
        ) == "大人的情\u{FFFD}\u{FFFD}")
    }

    @Test func partialRereadImprovesDamagedAlbumsAndPreservesCompleteAlbums() {
        for current in ["大人的情歌", "龘歌", "Björk", "大人的情歌?ARTIST=张宇"] {
            #expect(MediaMetadataTextRepair.preferredAlbumTitle(
                current: current, incoming: "大人的情\u{FFFD}", artist: "张宇"
            ) == (current == "大人的情歌?ARTIST=张宇" ? "大人的情歌" : current))
        }
        for current in [nil, "", "澶т汉鐨勬儏姝?ARTIST=寮犲畤", "大人的情\u{FFFD}"] {
            #expect(MediaMetadataTextRepair.preferredAlbumTitle(
                current: current, incoming: "大人的情\u{FFFD}", artist: "张宇"
            ) == "大人的情\u{FFFD}")
        }
        #expect(MediaMetadataTextRepair.preferredAlbumTitle(
            current: "大人的情\u{FFFD}", incoming: "大人的情歌", artist: "张宇"
        ) == "大人的情歌")
        #expect(MediaMetadataTextRepair.preferredAlbumTitle(
            current: "已知专辑", incoming: nil, artist: "张宇"
        ) == "已知专辑")
    }

    @Test(arguments: ["?", "\0", "\u{FFFD}", "\n"])
    func separatesAlbumFromAnIndependentlyVerifiedArtist(separator: String) {
        let album = "闆ㄤ竴鐩翠笅\(separator)ARTIST=寮犲畤"
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(album, artist: "张宇") == "雨一直下")
    }

    @Test func repairsNullDelimitedValueBeforeRemovingPadding() {
        #expect(MediaMetadataTextRepair.repairedTagValue("闆ㄤ竴鐩翠笅\0ARTIST=寮犲") == "雨一直下")
        #expect(MediaMetadataTextRepair.repairedTagValue("\0Björk\0") == "Björk")
    }

    @Test func usesAlbumArtistOnlyForAnAlbumArtistField() {
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "合集?ALBUMARTIST=群星", artist: "张宇", albumArtist: "群星"
        ) == "合集")
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "合集?ARTIST=群星", artist: "张宇", albumArtist: "群星"
        ) == "合集?ARTIST=群星")
    }

    @Test func preservesLiteralOrUnverifiableArtistText() {
        for album in ["Who?", "ARTIST=张宇", "Who? ARTIST=张宇",
                      "Album ARTIST=张宇", "Album?ARTIST=另一位歌手",
                      "?ARTIST=张宇", "Album?ARTIST=", "雨一直下?ARTIST=寮犲"] {
            #expect(MediaMetadataTextRepair.repairedAlbumTitle(album, artist: "张宇") == album)
        }
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "雨一直下?ARTIST=张宇", artist: nil
        ) == "雨一直下?ARTIST=张宇")
        #expect(MediaMetadataTextRepair.repairedAlbumTitle(
            "雨\u{FFFD}?ARTIST=张宇", artist: "张宇"
        ) == "雨\u{FFFD}")
    }

    @Test func prefersIndependentRawAlbumOverTruncatedOrAppendedText() {
        for current in ["闆ㄤ竴鐩翠笅?ARTIST=寮犲",
                        "雨一直下?ARTIST=寮犲", "雨一直下?ARTIST=张宇"] {
            #expect(MediaMetadataTextRepair.preferredTagValue(
                current: current, raw: "雨一直下"
            ) == "雨一直下")
        }
    }

    @Test func preservesCleanTagAndDamagedEvidenceWithoutACleanAlternative() {
        for current in ["Björk", "告白氣球", "龘歌", "Who?ARTIST=Someone"] {
            #expect(MediaMetadataTextRepair.preferredTagValue(
                current: current, raw: "另一张专辑"
            ) == current)
        }
        let damaged = "闆ㄤ竴鐩翠笅?ARTIST=寮犲"
        for raw in [nil, "", " \0", "雨\u{FFFD}", "雨一直下?ARTIST=张宇"] {
            #expect(MediaMetadataTextRepair.preferredTagValue(current: damaged, raw: raw) == damaged)
        }
        #expect(MediaMetadataTextRepair.preferredTagValue(
            current: nil, raw: "雨一直下?ARTIST=张宇"
        ) == "雨一直下?ARTIST=张宇")
    }
}

@Test func rejectsPlexQuestionMarkReplacementInChineseTitle() {
    #expect(MediaMetadataTextRepair.repaired("对面??") == nil)
    #expect(MediaMetadataTextRepair.isSuspicious("对面??"))
    #expect(
        MediaMetadataTextRepair.fileNameTitle(
            from: "/mnt/docker/TestMedia/PrimuseMusic/对面的女孩看过来.mp3"
        ) == "对面的女孩看过来"
    )
}

@Test func preservesIntentionalWesternQuestionMarks() {
    #expect(MediaMetadataTextRepair.repaired("What??") == "What??")
    #expect(MediaMetadataTextRepair.isSuspicious("What??") == false)
}

@Test func rejectsHanToHanCatalogMojibakeWithoutGuessingAReplacement() {
    for title in ["涓€璺", "憭抵"] {
        #expect(TextEncodingRepair.requiresRawByteVerification(title))
        #expect(TextEncodingRepair.repaired(title) == nil)
        #expect(!ServerCatalogMetadataInspectionPolicy.hasUsableTitle(title))
    }
}

@Test func extractsPlexFilenameArtistFallback() {
    let path = "/mnt/docker/TestMedia/PrimuseMusic/等什么君 - 慕夏.mp3"
    #expect(MediaMetadataTextRepair.fileNameArtist(from: path) == "等什么君")
    #expect(MediaMetadataTextRepair.fileNameTitle(from: path) == "慕夏")
}

@Test func extractsSpacedUnderscoreNASFilenameFields() {
    let path = "/music/谭艳 _ 伤了心的女人怎么了 _ 20140101 _ 【贝壳音乐 环绕5.1声道】 _ PeY.dts"
    #expect(MediaMetadataTextRepair.fileNameArtist(from: path) == "谭艳")
    #expect(MediaMetadataTextRepair.fileNameTitle(from: path) == "伤了心的女人怎么了")
}

@Test func extractsScrapeIdentityFromInconsistentlySpacedNASFilename() {
    let baseName = "陈果 _想和你去吹吹风_ 20170721 _【贝壳音乐现场】"
    let identity = MediaMetadataTextRepair.fileNameIdentity(fromBaseName: baseName)

    #expect(identity?.artist == "陈果")
    #expect(identity?.title == "想和你去吹吹风")
}

@Test func preservesBareUnderscoresInScrapeIdentity() {
    #expect(MediaMetadataTextRepair.fileNameIdentity(fromBaseName: "AC_DC_Live") == nil)
}

@Test func preservesBareUnderscoresInsideFilename() {
    let path = "/music/AC_DC_Live.flac"
    #expect(MediaMetadataTextRepair.fileNameArtist(from: path) == nil)
    #expect(MediaMetadataTextRepair.fileNameTitle(from: path) == "AC_DC_Live")
}

@Test func preservesNumericTrackPrefixBehavior() {
    #expect(MediaMetadataTextRepair.fileNameArtist(from: "/music/01 - Opening.flac") == nil)
    #expect(MediaMetadataTextRepair.fileNameTitle(from: "/music/01 - Opening.flac") == "Opening")
    #expect(MediaMetadataTextRepair.fileNameTitle(from: "/music/02. Finale.flac") == "Finale")
}

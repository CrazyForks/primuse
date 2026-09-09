import Foundation
import PrimuseKit

/// 检测 library 内可能属于同首歌的多个版本 (NAS 上同时存放 mp3 + flac,
/// 或者不同目录里相同文件)。按标准化标题、艺术家和 2 秒时长桶进行元数据
/// 分组；这里不计算 AcoustID/音频内容指纹，因此结果仍需要用户复核。
///
/// 用法:
/// ```
/// let groups = DuplicateDetector.detect(in: library.songs)
/// for group in groups {
///     // group.bestSong 按质量排序的第一名 (推荐保留)
///     // group.redundantSongs 推荐删除的其他版本
/// }
/// ```
/// 纯算法, 不依赖 MainActor — 10k+ 歌的 Dictionary(grouping:) + folding
/// 在主线程跑会卡 1-3s 让 UI 冻住。改成 nonisolated 后调用方用
/// `Task.detached` 丢到后台跑, 主线程只负责 ProgressView 显示。
enum DuplicateDetector {
    /// 同一首歌不同 encoder 的时长可能相差几百毫秒，用 2 秒桶降低轻微差异
    /// 带来的漏报。桶边界仍可能产生漏报，但不会扩大单个桶的匹配跨度。
    static let durationBucketSec: Int = 2

    /// 扫描 library 找重复歌曲分组。
    /// - Parameter songs: 整个 library 的 songs
    /// - Returns: 重复分组数组 (每组 size >= 2), 按标题字母序。
    static func detect(in songs: [Song]) -> [DuplicateGroup] {
        let grouped = Dictionary(grouping: songs) { song -> DuplicateKey in
            DuplicateKey(song)
        }

        return grouped
            .compactMap { (key, members) -> DuplicateGroup? in
                guard members.count > 1 else { return nil }
                // 标题是空的 group 没意义 (会把所有 "未知" 归为一组)
                guard !key.title.isEmpty else { return nil }
                let sorted = members.sorted { qualityScore(of: $0) > qualityScore(of: $1) }
                guard let displaySong = sorted.first else { return nil }
                return DuplicateGroup(
                    id: key.groupID,
                    title: displaySong.title,
                    artist: displaySong.artistName ?? "",
                    duration: displaySong.duration,
                    bestSong: displaySong,
                    songs: sorted
                )
            }
            .sorted { lhs, rhs in
                lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
            }
    }

    /// 质量评分 — 高 = 推荐保留。维度优先级:
    /// 1. lossless > lossy (无损上 +10000)
    /// 2. bitDepth (24bit > 16bit) (×500)
    /// 3. sampleRate (96k > 44.1k) (×0.01 转 kHz)
    /// 4. bitRate (有损歌的关键, kbps)
    /// 5. fileSize 作为最后 tiebreaker (MB)
    static func qualityScore(of song: Song) -> Int {
        var score = 0
        if isLossless(song.fileFormat) { score += 10000 }
        if let bd = song.bitDepth { score += bd * 500 }
        if let sr = song.sampleRate { score += sr / 1000 }
        if let br = song.bitRate { score += br }
        score += Int(song.fileSize / (1024 * 1024))
        return score
    }

    private static func isLossless(_ format: AudioFormat) -> Bool {
        format.isLossless
    }

    /// 标题 / 艺术家 normalize: 去 diacritic + 大小写 + 首尾空白, 但保留
    /// 内部空白 + 标点 (太激进 normalize 会把"Hello (Live)"和"Hello"
    /// 误归到同组, 这种其实是不同版本要保留, 不是重复)。
    static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
    }
}

/// 重复分组 — 多个 Song 共享 title+artist+duration 桶。
struct DuplicateGroup: Identifiable, Sendable {
    let id: String
    let title: String
    let artist: String
    let duration: TimeInterval
    let bestSong: Song
    /// 按质量评分降序排列, 第一个是推荐保留的。
    let songs: [Song]

    var redundantSongs: [Song] { Array(songs.dropFirst()) }
    var count: Int { songs.count }
}

/// 分组键。远程来源刚扫描完、标签尚未回填的歌曲没有艺术家、专辑和时长，
/// 只剩文件名推断出的标题；这类歌曲不能仅凭标题合并 (不同专辑的 "01. Intro"
/// 并不是同一首歌)。因此:
/// - 艺术家缺失时退回专辑艺术家，再退回专辑名作为区分维度；
/// - 时长未知时不参与 2 秒桶，改用文件大小区分；
/// - 艺术家、专辑都缺失时，已知的文件大小也参与区分，只有字节数相同的
///   副本才视为重复；时长和文件大小都未知的歌曲不会与任何歌曲合并。
struct DuplicateKey: Hashable {
    let title: String
    let artist: String
    let album: String
    let durationBucket: Int
    let fileSize: Int64
    /// 缺乏任何可比较依据时，用歌曲自身 id 隔离，避免误合并。
    let isolation: String

    init(_ song: Song) {
        title = DuplicateDetector.normalize(song.title)
        let trackArtist = DuplicateDetector.normalize(song.artistName ?? "")
        artist = trackArtist.isEmpty ? DuplicateDetector.normalize(song.albumArtistName ?? "") : trackArtist
        let albumKey = DuplicateDetector.normalize(song.albumTitle ?? "")
        album = artist.isEmpty ? albumKey : ""
        let hasDuration = song.duration.isFinite && song.duration > 0
        durationBucket = hasDuration ? song.duration.finiteInt() / DuplicateDetector.durationBucketSec : -1
        let requiresByteIdentity = (artist.isEmpty && album.isEmpty) || !hasDuration
        fileSize = requiresByteIdentity ? max(0, song.fileSize) : 0
        isolation = (!hasDuration && song.fileSize <= 0) ? song.id : ""
    }

    var groupID: String {
        "\(title)|\(artist)|\(album)|\(durationBucket)|\(fileSize)|\(isolation)"
    }
}

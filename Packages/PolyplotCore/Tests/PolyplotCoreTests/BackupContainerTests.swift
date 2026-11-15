import Foundation
import Testing
@testable import PolyplotCore

@Suite struct BackupContainerTests {
    let payload = Data((0..<500).map { UInt8($0 % 251) })

    @Test func wrapsAndUnwraps() throws {
        let file = BackupContainer.wrap(payload)
        #expect(file.prefix(8) == Data("POLYPLOT".utf8))
        #expect(file.count == payload.count + 17)
        #expect(try BackupContainer.unwrap(file) == payload)
        #expect(try BackupContainer.unwrap(BackupContainer.wrap(Data())) == Data())
    }

    @Test func theChecksumIsStandardCRC32() {
        #expect(BackupContainer.crc32(Data("123456789".utf8)) == 0xCBF4_3926)
        #expect(BackupContainer.crc32(Data()) == 0)
    }

    @Test func anyChangedByteIsCaught() {
        let file = BackupContainer.wrap(payload)
        for index in stride(from: 9, to: file.count, by: 7) {
            var edited = file
            edited[edited.startIndex + index] ^= 0x01
            #expect(throws: BackupContainer.Failure.self) { try BackupContainer.unwrap(edited) }
        }
        var flipped = file
        flipped[flipped.startIndex + 200] ^= 0x40
        #expect(throws: BackupContainer.Failure.damaged) { try BackupContainer.unwrap(flipped) }
    }

    @Test func cutShortOrPaddedFilesAreDamaged() {
        let file = BackupContainer.wrap(payload)
        #expect(throws: BackupContainer.Failure.damaged) { try BackupContainer.unwrap(file.dropLast()) }
        #expect(throws: BackupContainer.Failure.damaged) { try BackupContainer.unwrap(file + Data([0])) }
        #expect(throws: BackupContainer.Failure.damaged) { try BackupContainer.unwrap(file.prefix(11)) }
    }

    @Test func oldJSONBackupsAndOtherFilesAreNotBackups() {
        let oldBackup = Data(#"{"version": 2, "profile": {"displayName": "Rahn"}}"#.utf8)
        #expect(throws: BackupContainer.Failure.notABackup) { try BackupContainer.unwrap(oldBackup) }
        #expect(throws: BackupContainer.Failure.notABackup) { try BackupContainer.unwrap(Data()) }
        #expect(throws: BackupContainer.Failure.notABackup) { try BackupContainer.unwrap(Data("POLY".utf8)) }
    }

    @Test func aNewerFormatIsRecognised() {
        var file = BackupContainer.wrap(payload)
        file[file.startIndex + 8] = BackupContainer.formatVersion + 1
        #expect(throws: BackupContainer.Failure.newerFormat) { try BackupContainer.unwrap(file) }
    }

    /// Backups from before the rename (a 5-byte marker, same layout) still restore, once.
    @Test func backupsFromBeforeTheRenameStillRestore() throws {
        var old = BackupContainer.legacyMagic
        old.append(1)
        let count = UInt32(payload.count), crc = BackupContainer.crc32(payload)
        old.append(contentsOf: [UInt8(count >> 24 & 0xFF), UInt8(count >> 16 & 0xFF), UInt8(count >> 8 & 0xFF), UInt8(count & 0xFF)])
        old.append(contentsOf: [UInt8(crc >> 24 & 0xFF), UInt8(crc >> 16 & 0xFF), UInt8(crc >> 8 & 0xFF), UInt8(crc & 0xFF)])
        old.append(payload)
        #expect(try BackupContainer.unwrap(old) == payload)
        old[old.startIndex + 30] ^= 0x01
        #expect(throws: BackupContainer.Failure.damaged) { try BackupContainer.unwrap(old) }
    }
}

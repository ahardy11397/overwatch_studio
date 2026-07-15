#include "ShowfileManager.h"
#include <fstream>
#include <vector>
#include <filesystem>
#include <sqlite3.h>

bool ShowfileManager::loadShowfile(const std::string& path) {
    int err = 0;
    zip_t* archive = zip_open(path.c_str(), 0, &err);
    if (!archive) {
        return false;
    }

    // Search for manifest.json
    zip_stat_t sb;
    if (zip_stat(archive, "manifest.json", 0, &sb) == 0) {
        zip_file_t* zf = zip_fopen(archive, "manifest.json", 0);
        if (zf) {
            std::vector<char> buffer(sb.size);
            zip_fread(zf, buffer.data(), sb.size);
            zip_fclose(zf);

            // Parse manifest.json with simdjson
            simdjson::dom::parser parser;
            simdjson::dom::element doc;
            auto error = parser.parse(buffer.data(), buffer.size()).get(doc);
            if (!error) {
                std::cout << "Loaded manifest successfully.\n";
            }
        }
    }

    zip_close(archive);
    return true;
}

bool ShowfileManager::createDefaultShowfile(const std::string& path) {
    int err = 0;
    zip_t* archive = zip_open(path.c_str(), ZIP_CREATE | ZIP_TRUNCATE, &err);
    if (!archive) {
        return false;
    }

    // 1. Create manifest.json with full beta schema
    std::string manifest = R"({
  "version": "1.0",
  "name": "Default Show",
  "channels": 8,
  "buses": 2,
  "auxes": 0,
  "dcas": 8,
  "sampleRate": 48000,
  "videoResolution": "1920x1080",
  "videoFps": 60,
  "cues": [
    {"index": 0, "label": "Intro", "transition": {"type": "CROSSFADE", "duration_ms": 1000}},
    {"index": 1, "label": "Main", "transition": {"type": "CROSSFADE", "duration_ms": 500}},
    {"index": 2, "label": "Outro", "transition": {"type": "CROSSFADE", "duration_ms": 1000}}
  ],
  "channelNames": [
    "Mic 1", "Mic 2", "Mic 3", "Mic 4",
    "Mic 5", "Mic 6", "Mic 7", "Mic 8"
  ],
  "busNames": ["Bus 1", "Bus 2"],
  "dcaNames": ["DCA 1", "DCA 2", "DCA 3", "DCA 4", "DCA 5", "DCA 6", "DCA 7", "DCA 8"]
})";

    zip_source_t* s_manifest = zip_source_buffer(archive, manifest.data(), manifest.size(), 0);
    if (s_manifest) {
        zip_file_add(archive, "manifest.json", s_manifest, ZIP_FL_OVERWRITE | ZIP_FL_ENC_UTF_8);
    }

    // 2. Create a proper SQLite database with schema
    std::string tempDbPath = path + ".tmp.db";
    {
        sqlite3* db = nullptr;
        if (sqlite3_open_v2(tempDbPath.c_str(), &db,
                            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_FULLMUTEX,
                            nullptr) == SQLITE_OK) {
            // Enable WAL mode for concurrent access
            sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nullptr, nullptr, nullptr);

            // Create tables
            sqlite3_exec(db, R"(
                CREATE TABLE IF NOT EXISTS Channels (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    volume REAL DEFAULT 1.0,
                    mute INTEGER DEFAULT 0,
                    solo INTEGER DEFAULT 0,
                    pan REAL DEFAULT 0.0,
                    dca_group INTEGER DEFAULT -1,
                    bus_assignments TEXT DEFAULT '[]'
                );

                CREATE TABLE IF NOT EXISTS Buses (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    volume REAL DEFAULT 1.0,
                    mute INTEGER DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS DCAs (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    volume REAL DEFAULT 1.0,
                    mute INTEGER DEFAULT 0
                );

                CREATE TABLE IF NOT EXISTS Cues (
                    id INTEGER PRIMARY KEY,
                    name TEXT NOT NULL,
                    "index" INTEGER NOT NULL,
                    transition_type TEXT DEFAULT 'CROSSFADE',
                    transition_duration_ms INTEGER DEFAULT 500
                );

                CREATE TABLE IF NOT EXISTS Routing (
                    id INTEGER PRIMARY KEY AUTOINCREMENT,
                    source_type TEXT NOT NULL,
                    source_index INTEGER NOT NULL,
                    dest_type TEXT NOT NULL,
                    dest_index INTEGER NOT NULL,
                    gain REAL DEFAULT 1.0,
                    tap_point TEXT DEFAULT 'PostFader'
                );

                CREATE TABLE IF NOT EXISTS GlobalState (
                    key TEXT PRIMARY KEY,
                    value TEXT NOT NULL
                );
            )", nullptr, nullptr, nullptr);

            // Populate default channels
            for (int i = 0; i < 8; ++i) {
                std::string cmd = "INSERT INTO Channels (id, name) VALUES (" +
                                  std::to_string(i) + ", 'Mic " + std::to_string(i + 1) + "');";
                sqlite3_exec(db, cmd.c_str(), nullptr, nullptr, nullptr);
            }

            // Populate default buses
            for (int i = 0; i < 2; ++i) {
                std::string cmd = "INSERT INTO Buses (id, name) VALUES (" +
                                  std::to_string(i) + ", 'Bus " + std::to_string(i + 1) + "');";
                sqlite3_exec(db, cmd.c_str(), nullptr, nullptr, nullptr);
            }

            // Populate default DCAs
            for (int i = 0; i < 8; ++i) {
                std::string cmd = "INSERT INTO DCAs (id, name) VALUES (" +
                                  std::to_string(i) + ", 'DCA " + std::to_string(i + 1) + "');";
                sqlite3_exec(db, cmd.c_str(), nullptr, nullptr, nullptr);
            }

            // Populate default cues
            sqlite3_exec(db, "INSERT INTO Cues (name, \"index\", transition_type, transition_duration_ms) VALUES ('Intro', 0, 'CROSSFADE', 1000);", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "INSERT INTO Cues (name, \"index\", transition_type, transition_duration_ms) VALUES ('Main', 1, 'CROSSFADE', 500);", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "INSERT INTO Cues (name, \"index\", transition_type, transition_duration_ms) VALUES ('Outro', 2, 'CROSSFADE', 1000);", nullptr, nullptr, nullptr);

            // Set global state defaults
            sqlite3_exec(db, "INSERT INTO GlobalState (key, value) VALUES ('masterVolume', '1.0');", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "INSERT INTO GlobalState (key, value) VALUES ('masterMute', '0');", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "INSERT INTO GlobalState (key, value) VALUES ('programCamera', '0');", nullptr, nullptr, nullptr);
            sqlite3_exec(db, "INSERT INTO GlobalState (key, value) VALUES ('previewCamera', '1');", nullptr, nullptr, nullptr);

            sqlite3_close(db);
        }
    }

    // Add database to archive
    zip_source_t* s_db = zip_source_file(archive, tempDbPath.c_str(), 0, 0);
    if (s_db) {
        zip_file_add(archive, "show.db", s_db, ZIP_FL_OVERWRITE);
    }

    zip_close(archive);

    // Clean up temp file
    std::filesystem::remove(tempDbPath);

    return true;
}

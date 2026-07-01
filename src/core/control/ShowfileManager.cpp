#include "ShowfileManager.h"
#include <fstream>
#include <vector>
#include <filesystem>

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
                // Valid manifest parsed
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

    // 1. Create a basic manifest.json
    std::string manifest = R"({
  "version": "1.0",
  "name": "Default Show",
  "channels": 8,
  "buses": 2,
  "dcas": 8,
  "cues": [
    { "name": "Intro", "id": 1 },
    { "name": "Main", "id": 2 },
    { "name": "Outro", "id": 3 }
  ]
})";

    zip_source_t* s_manifest = zip_source_buffer(archive, manifest.data(), manifest.size(), 0);
    if (s_manifest) {
        zip_file_add(archive, "manifest.json", s_manifest, ZIP_FL_OVERWRITE | ZIP_FL_ENC_UTF_8);
    }

    // 2. Create an empty SQLite database file inside
    // We'll create it locally and then add it to the zip
    std::string tempDbPath = path + ".tmp.db";
    {
        // Try to create an empty file
        std::ofstream dbFile(tempDbPath, std::ios::binary);
    }

    zip_source_t* s_db = zip_source_file(archive, tempDbPath.c_str(), 0, 0);
    if (s_db) {
        zip_file_add(archive, "show.db", s_db, ZIP_FL_OVERWRITE);
    }

    zip_close(archive);

    // Clean up temp file
    std::filesystem::remove(tempDbPath);

    return true;
}

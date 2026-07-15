#pragma once

#include <sqlite3.h>
#include <string>
#include <stdexcept>

/**
 * @class DatabaseManager
 * @brief Manages SQLite connections and ensures WAL mode is enabled.
 */
class DatabaseManager {
public:
    DatabaseManager() = default;

    ~DatabaseManager() {
        close();
    }

    bool open(const std::string& dbPath) {
        if (db) {
            close();
        }
        
        int rc = sqlite3_open(dbPath.c_str(), &db);
        if (rc != SQLITE_OK) {
            return false;
        }

        // Enable WAL mode for high concurrency (UI vs Background processing)
        char* errMsg = nullptr;
        rc = sqlite3_exec(db, "PRAGMA journal_mode=WAL;", nullptr, nullptr, &errMsg);
        if (rc != SQLITE_OK) {
            if (errMsg) sqlite3_free(errMsg);
            close();
            return false;
        }

        // Additional optimizations
        sqlite3_exec(db, "PRAGMA synchronous=NORMAL;", nullptr, nullptr, nullptr);
        sqlite3_exec(db, "PRAGMA temp_store=MEMORY;", nullptr, nullptr, nullptr);

        return true;
    }

    void close() {
        if (db) {
            sqlite3_close(db);
            db = nullptr;
        }
    }

    bool execute(const std::string& sql) {
        if (!db) return false;
        
        char* errMsg = nullptr;
        int rc = sqlite3_exec(db, sql.c_str(), nullptr, nullptr, &errMsg);
        if (rc != SQLITE_OK) {
            if (errMsg) sqlite3_free(errMsg);
            return false;
        }
        return true;
    }

    sqlite3* getHandle() const {
        return db;
    }

private:
    sqlite3* db = nullptr;
};

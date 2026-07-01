#pragma once

#include <string>
#include <vector>
#include <zip.h>
#include <simdjson.h>
#include <iostream>

/**
 * @class ShowfileManager
 * @brief Handles reading and writing .sds (Software-Defined Show) archives.
 */
class ShowfileManager {
public:
    ShowfileManager() = default;

    /**
     * @brief Loads a showfile archive and extracts its manifest.
     */
    bool loadShowfile(const std::string& path);

    /**
     * @brief Creates a default showfile at the specified path.
     */
    bool createDefaultShowfile(const std::string& path);
};

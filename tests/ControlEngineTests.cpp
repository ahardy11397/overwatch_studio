#include <gtest/gtest.h>
#include <filesystem>
#include <fstream>
#include "../src/core/control/SPSCQueue.h"
#include "../src/core/control/DatabaseManager.h"
#include "../src/core/control/ShowfileManager.h"

TEST(ControlEngineTests, SPSCQueuePushPop) {
    SPSCQueue<int> queue(10);
    EXPECT_TRUE(queue.push(42));

    auto result = queue.pop();
    EXPECT_TRUE(result.has_value());
    EXPECT_EQ(result.value(), 42);

    // Test empty
    auto empty_result = queue.pop();
    EXPECT_FALSE(empty_result.has_value());
}

TEST(ControlEngineTests, DatabaseManagerWALMode) {
    DatabaseManager db;
    EXPECT_TRUE(db.open(":memory:"));
    EXPECT_TRUE(db.execute("CREATE TABLE test (id INTEGER PRIMARY KEY, name TEXT);"));
    EXPECT_TRUE(db.execute("INSERT INTO test (name) VALUES ('Overwatch');"));
    db.close();
}

TEST(ControlEngineTests, ShowfileManagerInit) {
    ShowfileManager sfm;
    EXPECT_FALSE(sfm.loadShowfile("non_existent_archive.sds"));
}

TEST(ControlEngineTests, ShowfileManagerDefaultGeneration) {
    ShowfileManager sfm;
    std::string testPath = "test_default.sds";

    // Cleanup if exists
    if (std::filesystem::exists(testPath)) {
        std::filesystem::remove(testPath);
    }

    EXPECT_TRUE(sfm.createDefaultShowfile(testPath));
    EXPECT_TRUE(std::filesystem::exists(testPath));

    // Verify it can be loaded
    EXPECT_TRUE(sfm.loadShowfile(testPath));

    // Cleanup
    std::filesystem::remove(testPath);
}

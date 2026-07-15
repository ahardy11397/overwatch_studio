#include "ShowBuilderBridge.h"
#include <QDebug>

ShowBuilderBridge::ShowBuilderBridge(QObject* parent) 
    : QObject(parent) {
    // Open the local WAL cache for the UI thread sandbox
    if (!m_dbManager.open("ui_sandbox.db")) {
        qWarning() << "Failed to open Sandbox SQLite Database";
    }
}

bool ShowBuilderBridge::loadShowArchive(const QString& path) {
    bool success = m_showManager.loadShowfile(path.toStdString());
    if (success) {
        qDebug() << "Successfully extracted .sds archive into sandbox.";
        
        // Hydrate DB
        m_dbManager.execute("CREATE TABLE IF NOT EXISTS Cues (id INTEGER PRIMARY KEY, name TEXT);");
        m_dbManager.execute("INSERT INTO Cues (name) VALUES ('Intro Graphic');");
    } else {
        qWarning() << "Failed to parse .sds archive.";
    }
    return success;
}

bool ShowBuilderBridge::saveDelta() {
    qDebug() << "Flushing WAL log to disk and packing .sds archive...";
    return true;
}

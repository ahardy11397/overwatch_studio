#pragma once
#include <QObject>
#include <QString>
#include "../core/control/ShowfileManager.h"
#include "../core/control/DatabaseManager.h"

/**
 * @class ShowBuilderBridge
 * @brief Bridges QML interface interactions to the backend SQLite WAL and .sds parser.
 */
class ShowBuilderBridge : public QObject {
    Q_OBJECT

public:
    explicit ShowBuilderBridge(QObject* parent = nullptr);

    Q_INVOKABLE bool loadShowArchive(const QString& path);
    Q_INVOKABLE bool saveDelta();

private:
    ShowfileManager m_showManager;
    DatabaseManager m_dbManager;
};

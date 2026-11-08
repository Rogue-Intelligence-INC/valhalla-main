#pragma once
// Shared local store for desktop editions (qt/education/student):
// workspaces/projects (workspaces.json), local enterprise accounts (accounts.json,
// SHA-256 + per-user salt, never plaintext), and qt conversation->project mapping
// (projects.json). Same field names in all three editions. No cloud sync.
#include <QCoreApplication>
#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRandomGenerator>
#include <QString>
#include <QVariantList>
#include <QVariantMap>

namespace vallocal {

inline QJsonObject readJson(const QString& path) {
    QFile f(path);
    if (!f.open(QIODevice::ReadOnly)) return {};
    QJsonParseError e;
    const QJsonDocument d = QJsonDocument::fromJson(f.readAll(), &e);
    return e.error == QJsonParseError::NoError && d.isObject() ? d.object() : QJsonObject{};
}
inline bool writeJson(const QString& path, const QJsonObject& obj) {
    QDir().mkpath(QFileInfo(path).absolutePath());
    QFile f(path);
    if (!f.open(QIODevice::WriteOnly | QIODevice::Truncate)) return false;
    f.write(QJsonDocument(obj).toJson(QJsonDocument::Indented));
    return true;
}
inline QString hashPassword(const QString& salt, const QString& password) {
    return QString::fromLatin1(QCryptographicHash::hash((salt + ":" + password).toUtf8(), QCryptographicHash::Sha256).toHex());
}
inline QString newSalt() { return QString::number(QRandomGenerator::global()->generate64(), 16); }

// ---------- accounts.json ----------
inline QJsonObject loadAccounts(const QString& dir) {
    QJsonObject root = readJson(dir + "/accounts.json");
    if (!root.contains("accounts")) {
        const QString salt = newSalt();
        QJsonObject local;
        local["name"] = QStringLiteral("本机用户");
        local["salt"] = salt;
        local["hash"] = hashPassword(salt, QString());
        local["role"] = QStringLiteral("admin");
        local["enabled"] = true;
        root["accounts"] = QJsonArray{local};
        root["currentUser"] = QStringLiteral("本机用户");
        root["accountsEnabled"] = false;
        root["enterpriseActive"] = false;
        writeJson(dir + "/accounts.json", root);
    }
    return root;
}
inline QVariantList accountsList(const QString& dir) {
    QVariantList out;
    for (const QJsonValue& v : loadAccounts(dir).value("accounts").toArray()) {
        const QJsonObject a = v.toObject();
        QVariantMap m;
        m["name"] = a.value("name").toString();
        m["role"] = a.value("role").toString();
        m["enabled"] = a.value("enabled").toBool(true);
        out.push_back(m);
    }
    return out;
}
inline QString accountRole(const QString& dir) {
    const QJsonObject root = loadAccounts(dir);
    const QString cur = root.value("currentUser").toString();
    for (const QJsonValue& v : root.value("accounts").toArray())
        if (v.toObject().value("name").toString() == cur) return v.toObject().value("role").toString();
    return QStringLiteral("admin");
}
inline QString addAccount(const QString& dir, const QString& name, const QString& password, const QString& role) {
    if (name.trimmed().isEmpty() || password.isEmpty()) return QStringLiteral("name/password empty");
    QJsonObject root = loadAccounts(dir);
    QJsonArray arr = root.value("accounts").toArray();
    if (!root.value("enterpriseActive").toBool(false) && arr.size() >= 3)
        return QStringLiteral("limit: 3 local accounts (Enterprise unlocks more)");
    for (const QJsonValue& v : arr)
        if (v.toObject().value("name").toString() == name) return QStringLiteral("exists");
    const QString salt = newSalt();
    QJsonObject a;
    a["name"] = name; a["salt"] = salt; a["hash"] = hashPassword(salt, password);
    a["role"] = role.isEmpty() ? QStringLiteral("member") : role; a["enabled"] = true;
    arr.append(a);
    root["accounts"] = arr;
    return writeJson(dir + "/accounts.json", root) ? QString() : QStringLiteral("write failed");
}
inline bool removeAccount(const QString& dir, const QString& name) {
    QJsonObject root = loadAccounts(dir);
    QJsonArray arr = root.value("accounts").toArray(), kept;
    bool hit = false;
    for (const QJsonValue& v : arr) {
        if (v.toObject().value("name").toString() == name) { hit = true; continue; }
        kept.append(v);
    }
    if (!hit) return false;
    root["accounts"] = kept;
    if (root.value("currentUser").toString() == name) root["currentUser"] = kept.isEmpty() ? QString() : kept.first().toObject().value("name").toString();
    return writeJson(dir + "/accounts.json", root);
}
inline bool setAccountEnabled(const QString& dir, const QString& name, bool enabled) {
    QJsonObject root = loadAccounts(dir);
    QJsonArray arr = root.value("accounts").toArray();
    bool hit = false;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject a = arr.at(i).toObject();
        if (a.value("name").toString() == name) { a["enabled"] = enabled; arr[i] = a; hit = true; }
    }
    if (!hit) return false;
    root["accounts"] = arr;
    return writeJson(dir + "/accounts.json", root);
}
inline bool resetAccountPassword(const QString& dir, const QString& name, const QString& password) {
    QJsonObject root = loadAccounts(dir);
    QJsonArray arr = root.value("accounts").toArray();
    bool hit = false;
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject a = arr.at(i).toObject();
        if (a.value("name").toString() == name) {
            const QString salt = newSalt();
            a["salt"] = salt; a["hash"] = hashPassword(salt, password); arr[i] = a; hit = true;
        }
    }
    if (!hit) return false;
    root["accounts"] = arr;
    return writeJson(dir + "/accounts.json", root);
}
inline bool login(const QString& dir, const QString& name, const QString& password) {
    QJsonObject root = loadAccounts(dir);
    for (const QJsonValue& v : root.value("accounts").toArray()) {
        const QJsonObject a = v.toObject();
        if (a.value("name").toString() != name || !a.value("enabled").toBool(true)) continue;
        if (a.value("hash").toString() != hashPassword(a.value("salt").toString(), password)) return false;
        root["currentUser"] = name;
        return writeJson(dir + "/accounts.json", root);
    }
    return false;
}
inline void logout(const QString& dir) {
    QJsonObject root = loadAccounts(dir);
    root["currentUser"] = QStringLiteral("本机用户");
    writeJson(dir + "/accounts.json", root);
}

// ---------- workspaces.json ----------
inline QJsonObject loadWorkspaces(const QString& dir) {
    QJsonObject root = readJson(dir + "/workspaces.json");
    if (!root.contains("workspaces")) {
        QJsonObject ws;
        ws["name"] = QStringLiteral("默认工作区");
        ws["projects"] = QJsonArray{QStringLiteral("默认项目")};
        root["workspaces"] = QJsonArray{ws};
        root["currentWorkspace"] = QStringLiteral("默认工作区");
        root["currentProject"] = QStringLiteral("默认项目");
        writeJson(dir + "/workspaces.json", root);
    }
    return root;
}
inline QVariantList workspaceList(const QString& dir) {
    QVariantList out;
    for (const QJsonValue& v : loadWorkspaces(dir).value("workspaces").toArray()) {
        QVariantMap m;
        m["name"] = v.toObject().value("name").toString();
        out.push_back(m);
    }
    return out;
}
inline QVariantList projectList(const QString& dir) {
    QVariantList out;
    const QJsonObject root = loadWorkspaces(dir);
    for (const QJsonValue& v : root.value("workspaces").toArray()) {
        const QJsonObject ws = v.toObject();
        if (ws.value("name").toString() != root.value("currentWorkspace").toString()) continue;
        for (const QJsonValue& p : ws.value("projects").toArray()) {
            QVariantMap m; m["name"] = p.toString(); out.push_back(m);
        }
    }
    return out;
}
inline bool addWorkspace(const QString& dir, const QString& name) {
    if (name.trimmed().isEmpty()) return false;
    QJsonObject root = loadWorkspaces(dir);
    QJsonArray arr = root.value("workspaces").toArray();
    for (const QJsonValue& v : arr) if (v.toObject().value("name").toString() == name) return false;
    QJsonObject ws; ws["name"] = name; ws["projects"] = QJsonArray{QStringLiteral("默认项目")};
    arr.append(ws); root["workspaces"] = arr; root["currentWorkspace"] = name; root["currentProject"] = QStringLiteral("默认项目");
    return writeJson(dir + "/workspaces.json", root);
}
inline bool switchWorkspace(const QString& dir, const QString& name) {
    QJsonObject root = loadWorkspaces(dir);
    for (const QJsonValue& v : root.value("workspaces").toArray()) {
        const QJsonObject ws = v.toObject();
        if (ws.value("name").toString() != name) continue;
        root["currentWorkspace"] = name;
        const QJsonArray ps = ws.value("projects").toArray();
        root["currentProject"] = ps.isEmpty() ? QStringLiteral("默认项目") : ps.first().toString();
        return writeJson(dir + "/workspaces.json", root);
    }
    return false;
}
inline bool addProject(const QString& dir, const QString& name) {
    if (name.trimmed().isEmpty()) return false;
    QJsonObject root = loadWorkspaces(dir);
    QJsonArray arr = root.value("workspaces").toArray();
    for (int i = 0; i < arr.size(); ++i) {
        QJsonObject ws = arr.at(i).toObject();
        if (ws.value("name").toString() != root.value("currentWorkspace").toString()) continue;
        QJsonArray ps = ws.value("projects").toArray();
        for (const QJsonValue& p : ps) if (p.toString() == name) return false;
        ps.append(name); ws["projects"] = ps; arr[i] = ws;
        root["workspaces"] = arr; root["currentProject"] = name;
        return writeJson(dir + "/workspaces.json", root);
    }
    return false;
}
inline bool switchProject(const QString& dir, const QString& name) {
    QJsonObject root = loadWorkspaces(dir);
    root["currentProject"] = name;
    return writeJson(dir + "/workspaces.json", root);
}

// ---------- projects.json (qt conversation -> project) ----------
inline QString projectFor(const QString& dir, const QString& chatId, const QString& fallback) {
    return readJson(dir + "/projects.json").value("mapping").toObject().value(chatId).toString(fallback);
}
inline void setProjectFor(const QString& dir, const QString& chatId, const QString& project) {
    QJsonObject root = readJson(dir + "/projects.json");
    QJsonObject map = root.value("mapping").toObject();
    map[chatId] = project;
    root["mapping"] = map;
    writeJson(dir + "/projects.json", root);
}

} // namespace vallocal

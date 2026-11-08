#pragma once

#include <QObject>
#include <QString>
#include <QStringList>
#include <QVariantList>
#include <QUrl>

#include <string>
#include <utility>
#include <vector>

#include "desktop.h"
#include "engine.h"
#include "val_local_store.h"
#include "knowledge.h"
#include "sessions.h"
#include "tts.h"

// Qt front-end over the same native engine the Win32 shell used:
// engine.cpp (chat + framework), knowledge.cpp, sessions.cpp, desktop.cpp, ocr.cpp.
class Bridge : public QObject {
    Q_OBJECT
    Q_PROPERTY(QVariantList conversations READ conversations NOTIFY conversationsChanged)
    Q_PROPERTY(QVariantList messages READ messages NOTIFY messagesChanged)
    Q_PROPERTY(QVariantList models READ models NOTIFY modelsChanged)
    Q_PROPERTY(QString pipelineReport READ pipelineReport NOTIFY pipelineChanged)
    Q_PROPERTY(bool pipelineBusy READ pipelineBusy NOTIFY pipelineChanged)
    Q_PROPERTY(QString catalogStatus READ catalogStatus NOTIFY pipelineChanged)
    Q_PROPERTY(QString currentModelName READ currentModelName NOTIFY pipelineChanged)
    Q_PROPERTY(bool modelLoaded READ modelLoaded NOTIFY pipelineChanged)
    Q_PROPERTY(bool enginePresent READ enginePresent NOTIFY pipelineChanged)
    Q_PROPERTY(bool modelInstalled READ modelInstalled NOTIFY pipelineChanged)
    Q_PROPERTY(QString computeDevice READ computeDevice NOTIFY pipelineChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)
    Q_PROPERTY(QString statusText READ statusText NOTIFY statusChanged)
    Q_PROPERTY(QString lang READ lang NOTIFY langChanged)
    Q_PROPERTY(int strategyIndex READ strategyIndex NOTIFY settingsChanged)
    Q_PROPERTY(QString strategyDelta READ strategyDelta NOTIFY settingsChanged)
    Q_PROPERTY(bool keepSession READ keepSession NOTIFY settingsChanged)
    Q_PROPERTY(bool allowControl READ allowControl NOTIFY settingsChanged)
    Q_PROPERTY(bool taskMode READ taskMode NOTIFY settingsChanged)
    Q_PROPERTY(int languageIndex READ languageIndex NOTIFY settingsChanged)
    Q_PROPERTY(QString knowledgeText READ knowledgeText NOTIFY knowledgeChanged)
    Q_PROPERTY(QString knowledgeStats READ knowledgeStats NOTIFY knowledgeChanged)
    Q_PROPERTY(QString runtimeText READ runtimeText NOTIFY runtimeChanged)
    Q_PROPERTY(QString screenText READ screenText NOTIFY screenChanged)
    Q_PROPERTY(QString screenMeta READ screenMeta NOTIFY screenChanged)
    Q_PROPERTY(QString chatTitle READ chatTitle NOTIFY conversationsChanged)
    Q_PROPERTY(QString lastPath READ lastPath NOTIFY turnChanged)
    Q_PROPERTY(QString lastBadge READ lastBadge NOTIFY turnChanged)
    Q_PROPERTY(QString lastElapsed READ lastElapsed NOTIFY turnChanged)
    Q_PROPERTY(int turnCount READ turnCount NOTIFY turnChanged)
    Q_PROPERTY(QString activeChat READ activeChat NOTIFY conversationsChanged)
    Q_PROPERTY(bool envReady READ envReady NOTIFY envChanged)
    Q_PROPERTY(QString envReport READ envReport NOTIFY envChanged)
    Q_PROPERTY(bool envDismissed READ envDismissed NOTIFY envChanged)
    Q_PROPERTY(QVariantList accounts READ accounts NOTIFY accountsChanged)
    Q_PROPERTY(QString currentUser READ currentUser NOTIFY accountsChanged)
    Q_PROPERTY(QString accountRole READ accountRole NOTIFY accountsChanged)
    Q_PROPERTY(bool accountsEnabled READ accountsEnabled NOTIFY accountsChanged)
    Q_PROPERTY(bool enterpriseActive READ enterpriseActive NOTIFY accountsChanged)
    Q_PROPERTY(QString accountMsg READ accountMsg NOTIFY accountsChanged)
    Q_PROPERTY(QVariantList workspaces READ workspaces NOTIFY workspacesChanged)
    Q_PROPERTY(QString currentWorkspace READ currentWorkspace NOTIFY workspacesChanged)
    Q_PROPERTY(QString currentProject READ currentProject NOTIFY workspacesChanged)
    Q_PROPERTY(QVariantList projects READ projects NOTIFY workspacesChanged)
    Q_PROPERTY(bool webBusy READ webBusy NOTIFY busyChanged)
    Q_PROPERTY(QVariantList webSources READ webSources NOTIFY screenChanged)
    Q_PROPERTY(QStringList attachments READ attachments NOTIFY screenChanged)

public:
    explicit Bridge(QObject* parent = nullptr);
    ~Bridge() override;

    QVariantList conversations() const { return conversations_; }
    QVariantList messages() const { return messages_; }
    QVariantList models() const { return models_; }

    QString pipelineReport() const { return pipeline_report_; }
    bool pipelineBusy() const { return pipeline_busy_; }
    QString catalogStatus() const { return catalog_status_; }
    QString currentModelName() const { return QString::fromStdString(settings_.model_repo); }
    bool modelLoaded() const { return warm_weights_resident(); }
    bool enginePresent() const { return !find_binary().empty(); }
    bool modelInstalled() const { return weights_present(model_directory(settings_.model_repo)); }
    QString computeDevice() const { const QString g = QString::fromStdWString(gpu_status()); return g.isEmpty() ? QStringLiteral("—") : g; }
    bool busy() const { return busy_; }
    QString statusText() const { return status_; }
    QString lang() const { return lang_; }
    int strategyIndex() const;
    QString strategyDelta() const;
    bool keepSession() const { return settings_.keep_session; }
    bool allowControl() const { return settings_.allow_control; }
    bool taskMode() const { return task_mode_; }
    int languageIndex() const;
    QString knowledgeText() const { return QString::fromStdString(settings_.knowledge); }
    QString knowledgeStats() const;
    QString runtimeText() const;
    QString screenText() const { const QString s = QString::fromStdWString(reading_.text); return s.isEmpty() ? ocr_import_text_ : s; }
    QString screenMeta() const;
    QString chatTitle() const;
    QString lastPath() const { return last_path_; }
    QString lastBadge() const;
    QString lastElapsed() const;
    int turnCount() const { return static_cast<int>(history_.size()); }
    QString activeChat() const { return QString::fromStdString(library_.active); }
    bool envReady();
    QString envReport();
    bool envDismissed();

    Q_INVOKABLE void setDarkTheme(bool dark);
    Q_INVOKABLE void repairPipeline();
    Q_INVOKABLE void updateModelCatalog();
    Q_INVOKABLE void claimWindow();
    Q_INVOKABLE void send(const QString& text);
    Q_INVOKABLE void newChat();
    Q_INVOKABLE void openChat(const QString& id);
    Q_INVOKABLE void deleteChat(const QString& id);
    Q_INVOKABLE void setSearch(const QString& text);
    Q_INVOKABLE void saveKnowledge(const QString& text);
    Q_INVOKABLE void importFiles(const QString& domain, const QVariantList& urls);
    Q_INVOKABLE void useOrDownloadModel(int index);
    Q_INVOKABLE void setStrategy(int index);
    Q_INVOKABLE void setKeepSession(bool value);
    Q_INVOKABLE void setAllowControl(bool value);
    Q_INVOKABLE void setTaskMode(bool value);
    Q_INVOKABLE void setLanguage(int index);
    Q_INVOKABLE void recognize();
    Q_INVOKABLE void ocrImport(const QVariantList& urls);
    Q_INVOKABLE void retryLast();
    Q_INVOKABLE void probe();
    Q_INVOKABLE void speakText(const QString& text);
    Q_INVOKABLE void stopSpeak();
    Q_INVOKABLE void askSelection(const QString& action, const QString& text);
    Q_INVOKABLE void setupEnvironment();
    Q_INVOKABLE void installCudaOfficial();
    Q_INVOKABLE void dismissEnvSetup();
    Q_INVOKABLE void webSearch(const QString& query, bool thenAsk);
    void fetchWeb(const QString& query, bool thenAsk, int engine);
    Q_INVOKABLE void copyText(const QString& text);
    Q_INVOKABLE bool exportChat(const QUrl& target);
    Q_INVOKABLE void clearContext();
    Q_INVOKABLE void attachFiles(const QVariantList& urls);
    QStringList attachments() const { return attach_names_; }
    bool webBusy() const { return web_busy_; }
    QVariantList webSources() const { return web_sources_; }

    // Local accounts + workspaces/projects (shared val_local_store.h, same API in all editions)
    QVariantList accounts() const { return vallocal::accountsList(valDir()); }
    QString currentUser() const { return vallocal::loadAccounts(valDir()).value("currentUser").toString(QStringLiteral("本机用户")); }
    QString accountRole() const { return vallocal::accountRole(valDir()); }
    bool accountsEnabled() const { return vallocal::loadAccounts(valDir()).value("accountsEnabled").toBool(false); }
    bool enterpriseActive() const { return vallocal::loadAccounts(valDir()).value("enterpriseActive").toBool(false); }
    QString accountMsg() const { return account_msg_; }
    QVariantList workspaces() const { return vallocal::workspaceList(valDir()); }
    QString currentWorkspace() const { return vallocal::loadWorkspaces(valDir()).value("currentWorkspace").toString(); }
    QString currentProject() const { return vallocal::loadWorkspaces(valDir()).value("currentProject").toString(); }
    QVariantList projects() const { return vallocal::projectList(valDir()); }
    Q_INVOKABLE void addAccount(const QString& name, const QString& password, const QString& role) {
        const QString err = vallocal::addAccount(valDir(), name, password, role);
        account_msg_ = err.isEmpty() ? L("账号已创建。", "Account created.") : (err.startsWith("limit") ? L("本地账号上限 3 个，企业版可解锁更多。", "3 local accounts max; Enterprise unlocks more.") : err);
        emit accountsChanged();
    }
    Q_INVOKABLE void removeAccount(const QString& name) { vallocal::removeAccount(valDir(), name); emit accountsChanged(); }
    Q_INVOKABLE void setAccountEnabled(const QString& name, bool enabled) { vallocal::setAccountEnabled(valDir(), name, enabled); emit accountsChanged(); }
    Q_INVOKABLE void resetAccountPassword(const QString& name, const QString& password) { vallocal::resetAccountPassword(valDir(), name, password); account_msg_ = L("密码已重置。", "Password reset."); emit accountsChanged(); }
    Q_INVOKABLE bool login(const QString& name, const QString& password) {
        const bool ok = vallocal::login(valDir(), name, password);
        account_msg_ = ok ? L("已登录。", "Signed in.") : L("账号或密码不正确，或账号已停用。", "Wrong credentials or disabled account.");
        emit accountsChanged();
        return ok;
    }
    Q_INVOKABLE void logout() { vallocal::logout(valDir()); emit accountsChanged(); }
    Q_INVOKABLE void setAccountsEnabled(bool enabled) {
        auto r = vallocal::loadAccounts(valDir()); r["accountsEnabled"] = enabled; vallocal::writeJson(valDir() + "/accounts.json", r); emit accountsChanged();
    }
    Q_INVOKABLE void setEnterpriseActive(bool active) {
        auto r = vallocal::loadAccounts(valDir()); r["enterpriseActive"] = active; vallocal::writeJson(valDir() + "/accounts.json", r); emit accountsChanged();
    }
    Q_INVOKABLE void addWorkspace(const QString& name) { vallocal::addWorkspace(valDir(), name); emit workspacesChanged(); }
    Q_INVOKABLE void switchWorkspace(const QString& name) { vallocal::switchWorkspace(valDir(), name); emit workspacesChanged(); }
    Q_INVOKABLE void addProject(const QString& name) { vallocal::addProject(valDir(), name); emit workspacesChanged(); }
    Q_INVOKABLE void switchProject(const QString& name) { vallocal::switchProject(valDir(), name); emit workspacesChanged(); }

signals:
    void accountsChanged();
    void workspacesChanged();
    void conversationsChanged();
    void messagesChanged();
    void modelsChanged();
    void pipelineChanged();
    void busyChanged();
    void statusChanged();
    void langChanged();
    void settingsChanged();
    void knowledgeChanged();
    void runtimeChanged();
    void screenChanged();
    void turnChanged();
    void envChanged();

private:
    struct Line {
        bool user = false;
        QString text;
        QString path;
        bool error = false;
        QString time;
        QStringList tools;
    };

    QString L(const char* zh, const char* en) const { return lang_ == "zh" ? QString::fromUtf8(zh) : QString::fromUtf8(en); }
    void setBusy(bool value);
    void setStatus(const QString& text);
    void refreshConversations();
    void refreshMessages();
    void refreshModels();
    void loadActive();
    void storeTranscript();
    void pullKnowledge(const QString& text);
    void saveSettings();
    std::wstring dataFile(const wchar_t* name) const;

    QString pipeline_report_;
    QString catalog_status_;
    bool pipeline_busy_ = false;
    std::wstring data_dir_;
    std::wstring settings_path_;
    std::wstring kb_path_;
    std::wstring transcript_path_;
    Settings settings_;
    KnowledgeBase kb_;
    ConversationLibrary library_;
    std::vector<Line> lines_;
    std::vector<std::pair<std::string, std::string>> history_;
    std::string session_json_;
    std::string screen_context_;
    ScreenReading reading_;
    QVariantList conversations_;
    QVariantList messages_;
    QVariantList models_;
    QString status_;
    QString display_override_;
    Tts tts_;
    QString framework_note_;
    QString probe_text_;
    QString last_path_;
    QString last_question_;
    QString ocr_import_text_;
    QString search_;
    QString lang_ = "zh";
    double last_seconds_ = -1;
    bool busy_ = false;
    bool task_mode_ = false;
    bool web_busy_ = false;
    QVariantList web_sources_;
    QString web_context_;
    QString attach_context_;
    QStringList attach_names_;
    QStringList turn_tools_;
    void* window_ = nullptr;
    QString account_msg_;
    QString valDir() const { return QString::fromStdWString(data_dir_); }
};

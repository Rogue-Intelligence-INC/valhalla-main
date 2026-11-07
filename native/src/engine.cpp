#include "engine.h"

#include "utf.h"
#include "valkey.h"

#include <nlohmann/json.hpp>

#include <windows.h>
#include <winhttp.h>
#include <bcrypt.h>

#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <cwctype>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {

constexpr wchar_t kDefaultBinary[] = L"c:\\Ai\\Valhalla-main\\target\\release\\valhalla_base.exe";
constexpr wchar_t kModelsRoot[] = L"c:\\Ai\\models";

std::wstring leaf_name(const std::string& repo) {
    auto slash = repo.find_last_of('/');
    std::string leaf = slash == std::string::npos ? repo : repo.substr(slash + 1);
    return utf8_to_wide(leaf);
}

std::vector<std::string> knowledge_lines(const std::string& knowledge) {
    std::vector<std::string> lines;
    std::string current;
    for (char ch : knowledge) {
        if (ch == '\n') {
            current = trim_utf8(current);
            if (!current.empty()) lines.push_back(current);
            current.clear();
        } else if (ch != '\r') {
            current.push_back(ch);
        }
    }
    current = trim_utf8(current);
    if (!current.empty()) lines.push_back(current);
    return lines;
}

std::string citation_body(const std::string& answer) {
    size_t index = 0;
    while (index < answer.size() && answer[index] == '[') {
        auto end = answer.find(']', index);
        if (end == std::string::npos) break;
        index = end + 1;
        while (index < answer.size() && (answer[index] == ' ' || answer[index] == '\n')) ++index;
    }
    return index < answer.size() ? answer.substr(index) : answer;
}

bool shares_focus(const std::wstring& question, const std::wstring& evidence) {
    std::wstring folded;
    folded.reserve(evidence.size());
    for (wchar_t ch : evidence) folded.push_back(towlower(ch));
    std::wstring token;
    std::wstring cjk;
    auto token_hit = [&]() {
        bool hit = token.size() >= 3 && folded.find(token) != std::wstring::npos;
        token.clear();
        return hit;
    };
    auto cjk_hit = [&]() {
        bool hit = false;
        if (cjk.size() >= 2) {
            for (size_t index = 0; index + 1 < cjk.size() && !hit; ++index) {
                hit = folded.find(cjk.substr(index, 2)) != std::wstring::npos;
            }
        }
        cjk.clear();
        return hit;
    };
    for (wchar_t ch : question) {
        bool han = (ch >= 0x4E00 && ch <= 0x9FFF) || (ch >= 0x3400 && ch <= 0x4DBF);
        if (han) {
            if (token_hit()) return true;
            cjk.push_back(ch);
            continue;
        }
        if (cjk_hit()) return true;
        if (iswalnum(ch)) token.push_back(towlower(ch));
        else if (token_hit()) return true;
    }
    return token_hit() || cjk_hit();
}

bool retrieval_binds(const std::string& mode, const std::string& question, const nlohmann::json& row) {
    std::string answer = row.value("answer", "");
    std::string path = row.value("decode_path", "");
    if (answer.rfind("No confident match", 0) == 0) return false;
    if (path.find("open_reject") != std::string::npos || path.find("abstain") != std::string::npos) return false;
    bool cited = !answer.empty() && answer.front() == '[';
    bool native = path.find("native") != std::string::npos || path.find("retrieval") != std::string::npos ||
                  path.find("multihop") != std::string::npos;
    if (!cited && !native) return false;
    std::string body = citation_body(answer);
    if (trim_utf8(body).empty()) return false;
    if (mode == "multihop") return true;
    if (path.find("_span") != std::string::npos || path.find("_short") != std::string::npos) return true;
    bool ready = false;
    if (row.contains("fog_decision") && row["fog_decision"].is_object()) {
        ready = row["fog_decision"].value("evidence_ready", false);
    }
    bool overlap = shares_focus(utf8_to_wide(question), utf8_to_wide(body));
    return overlap || (ready && overlap);
}

std::string chat_prompt(
    const std::string& knowledge,
    const std::string& question,
    const std::vector<std::pair<std::string, std::string>>& history,
    const std::string& screen,
    bool allow_control,
    const std::string& evidence) {
    auto lines = knowledge_lines(knowledge);
    std::string corpus;
    for (size_t i = 0; i < lines.size(); ++i) {
        if (i) corpus.push_back('\n');
        corpus += lines[i];
    }
    // Keep a long tail of the conversation. Drop the oldest turns only when the prompt
    // would crowd out the latest question.
    constexpr size_t kHistoryBudget = 16000;
    size_t begin = history.size();
    size_t used = 0;
    while (begin > 0) {
        const auto& turn = history[begin - 1];
        size_t cost = turn.first.size() + turn.second.size() + 24;
        if (begin < history.size() && used + cost > kHistoryBudget) break;
        used += cost;
        --begin;
    }
    std::string prior;
    for (size_t i = begin; i < history.size(); ++i) {
        prior += "User: " + history[i].first + "\nAssistant: " + history[i].second + "\n\n";
    }
    std::string knowledge_block = corpus.empty() ? std::string() : "Knowledge:\n" + corpus + "\n\n";
    std::string evidence_block = evidence.empty() ? std::string()
                                                   : "Retrieved evidence:\n" + evidence +
                                                         "\nBase the answer on this evidence when it addresses the user. "
                                                         "Do not replace it with a different fact.\n\n";
    std::string screen_block = screen.empty() ? std::string() : "Current screen:\n" + screen + "\n\n";
    std::string tools;
    if (allow_control) {
        tools = "When the user wants the screen or this computer operated, end the reply with lines after [[action]]. "
                "Allowed lines only: read_screen ; click X Y ; click_text LABEL ; move X Y ; type TEXT ; key enter|tab|esc|up|down|left|right ; scroll N. "
                "Coordinates in the screen reading are screen pixels. Prefer click_text when a control or OCR line names the target. "
                "Do not invent other commands.\n\n";
    }
    return "You are Valhalla in an ongoing conversation. "
           "Use the knowledge when it answers the user, and use the earlier turns as memory. "
           "Answer the latest message completely, in the user's language. "
           "Do not stop after a fragment or a single short sentence when the user is still talking.\n\n" +
           tools + evidence_block + knowledge_block + screen_block + prior + "User: " + question;
}

bool parse_cuda_version(const std::wstring& text, int& major, int& minor, std::wstring& pretty) {
    size_t index = 0;
    while (index < text.size() && !iswdigit(text[index])) ++index;
    if (index >= text.size()) return false;
    major = 0;
    while (index < text.size() && iswdigit(text[index])) {
        major = major * 10 + (text[index] - L'0');
        ++index;
    }
    minor = 0;
    if (index < text.size() && text[index] == L'.') {
        ++index;
        while (index < text.size() && iswdigit(text[index])) {
            minor = minor * 10 + (text[index] - L'0');
            ++index;
        }
    }
    wchar_t buffer[32];
    swprintf_s(buffer, L"%d.%d", major, minor);
    pretty = buffer;
    return major > 0;
}

std::wstring find_cudart_dll(const std::wstring& directory) {
    WIN32_FIND_DATAW data{};
    HANDLE found = FindFirstFileW((directory + L"\\cudart64_*.dll").c_str(), &data);
    if (found == INVALID_HANDLE_VALUE) return L"";
    std::wstring name = data.cFileName;
    FindClose(found);
    return directory + L"\\" + name;
}

struct CudaCandidate {
    std::wstring version;
    std::wstring root;
    std::wstring bin;
    std::wstring dll;
    int major = 0;
    int minor = 0;
};

void consider_cuda_root(const std::wstring& root_in, std::vector<CudaCandidate>& found) {
    std::wstring root = root_in;
    while (!root.empty() && (root.back() == L'\\' || root.back() == L'/')) root.pop_back();
    if (root.empty()) return;
    int major = 0;
    int minor = 0;
    std::wstring version;
    auto slash = root.find_last_of(L"\\/");
    std::wstring leaf = slash == std::wstring::npos ? root : root.substr(slash + 1);
    if (!parse_cuda_version(leaf, major, minor, version)) return;
    const wchar_t* bins[] = {L"\\bin\\x64", L"\\bin"};
    for (const wchar_t* suffix : bins) {
        std::wstring bin = root + suffix;
        std::wstring dll = find_cudart_dll(bin);
        if (dll.empty()) continue;
        for (const auto& item : found) {
            if (_wcsicmp(item.dll.c_str(), dll.c_str()) == 0) return;
        }
        found.push_back(CudaCandidate{version, root, bin, dll, major, minor});
        return;
    }
}

void scan_cuda_directory(const std::wstring& parent, std::vector<CudaCandidate>& found) {
    WIN32_FIND_DATAW data{};
    HANDLE search = FindFirstFileW((parent + L"\\v*").c_str(), &data);
    if (search == INVALID_HANDLE_VALUE) return;
    do {
        if (!(data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY)) continue;
        if (wcscmp(data.cFileName, L".") == 0 || wcscmp(data.cFileName, L"..") == 0) continue;
        consider_cuda_root(parent + L"\\" + data.cFileName, found);
    } while (FindNextFileW(search, &data));
    FindClose(search);
}

void scan_cuda_registry(HKEY root, const wchar_t* path, std::vector<CudaCandidate>& found) {
    HKEY key = nullptr;
    if (RegOpenKeyExW(root, path, 0, KEY_READ, &key) != ERROR_SUCCESS) return;
    DWORD index = 0;
    wchar_t name[64];
    while (true) {
        DWORD name_size = 64;
        if (RegEnumKeyExW(key, index++, name, &name_size, nullptr, nullptr, nullptr, nullptr) != ERROR_SUCCESS) break;
        HKEY child = nullptr;
        if (RegOpenKeyExW(key, name, 0, KEY_READ, &child) != ERROR_SUCCESS) continue;
        wchar_t install[MAX_PATH];
        DWORD size = sizeof(install);
        DWORD type = 0;
        if (RegQueryValueExW(child, L"InstallDir", nullptr, &type, reinterpret_cast<BYTE*>(install), &size) == ERROR_SUCCESS && type == REG_SZ) {
            consider_cuda_root(install, found);
        }
        RegCloseKey(child);
    }
    RegCloseKey(key);
}

std::wstring read_driver_version() {
    const wchar_t* candidates[] = {
        L"C:\\Windows\\System32\\nvidia-smi.exe",
        L"C:\\Program Files\\NVIDIA Corporation\\NVSMI\\nvidia-smi.exe",
    };
    std::wstring binary;
    for (const wchar_t* path : candidates) {
        if (GetFileAttributesW(path) != INVALID_FILE_ATTRIBUTES) {
            binary = path;
            break;
        }
    }
    if (binary.empty()) return L"";
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    HANDLE read = nullptr;
    HANDLE write = nullptr;
    if (!CreatePipe(&read, &write, &security, 1 << 16)) return L"";
    SetHandleInformation(read, HANDLE_FLAG_INHERIT, 0);
    std::wstring command = L"\"" + binary + L"\" --query-gpu=driver_version --format=csv,noheader";
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdOutput = write;
    startup.hStdError = write;
    PROCESS_INFORMATION process{};
    if (!CreateProcessW(binary.c_str(), mutable_command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW, nullptr, nullptr, &startup, &process)) {
        CloseHandle(read);
        CloseHandle(write);
        return L"";
    }
    CloseHandle(write);
    std::string output;
    ULONGLONG started = GetTickCount64();
    while (GetTickCount64() - started < 3000) {
        DWORD available = 0;
        if (PeekNamedPipe(read, nullptr, 0, nullptr, &available, nullptr) && available > 0) {
            std::string chunk(available, '\0');
            DWORD got = 0;
            if (ReadFile(read, chunk.data(), available, &got, nullptr)) {
                chunk.resize(got);
                output += chunk;
            }
        }
        if (WaitForSingleObject(process.hProcess, 0) == WAIT_OBJECT_0) break;
        Sleep(20);
    }
    if (WaitForSingleObject(process.hProcess, 0) == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 1);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    CloseHandle(read);
    auto line_end = output.find_first_of("\r\n");
    std::string line = trim_utf8(line_end == std::string::npos ? output : output.substr(0, line_end));
    if (line.empty() || line.find("Failed") != std::string::npos) return L"";
    return utf8_to_wide(line);
}

CudaRuntime detect_cuda_runtime() {
    std::vector<CudaCandidate> found;
    scan_cuda_directory(L"C:\\Program Files\\NVIDIA GPU Computing Toolkit\\CUDA", found);
    scan_cuda_registry(HKEY_LOCAL_MACHINE, L"SOFTWARE\\NVIDIA Corporation\\GPU Computing Toolkit\\CUDA", found);
    scan_cuda_registry(HKEY_LOCAL_MACHINE, L"SOFTWARE\\WOW6432Node\\NVIDIA Corporation\\GPU Computing Toolkit\\CUDA", found);
    std::sort(found.begin(), found.end(), [](const CudaCandidate& a, const CudaCandidate& b) {
        if (a.major != b.major) return a.major > b.major;
        return a.minor > b.minor;
    });
    CudaRuntime runtime;
    runtime.driver = read_driver_version();
    for (const auto& item : found) {
        HMODULE module = LoadLibraryW(item.dll.c_str());
        if (!module) continue;
        FreeLibrary(module);
        runtime.version = item.version;
        runtime.root = item.root;
        runtime.bin = item.bin;
        runtime.dll = item.dll;
        runtime.major = item.major;
        runtime.minor = item.minor;
        runtime.loaded = true;
        break;
    }
    if (!runtime.loaded && !found.empty()) {
        runtime.version = found.front().version;
        runtime.root = found.front().root;
        runtime.bin = found.front().bin;
        runtime.dll = found.front().dll;
        runtime.major = found.front().major;
        runtime.minor = found.front().minor;
    }
    for (const auto& item : found) {
        if (_wcsicmp(item.version.c_str(), runtime.version.c_str()) == 0 && _wcsicmp(item.root.c_str(), runtime.root.c_str()) == 0) continue;
        bool seen = false;
        for (const auto& other : runtime.others) {
            if (_wcsicmp(other.c_str(), item.version.c_str()) == 0) seen = true;
        }
        if (!seen) runtime.others.push_back(item.version);
    }
    return runtime;
}

const CudaRuntime& cached_cuda() {
    static CudaRuntime runtime = detect_cuda_runtime();
    return runtime;
}

std::wstring env_block(const std::wstring& model) {
    std::wstring path_value;
    std::vector<std::pair<std::wstring, std::wstring>> vars;
    LPWCH raw = GetEnvironmentStringsW();
    if (raw) {
        for (LPWCH cursor = raw; *cursor;) {
            std::wstring line = cursor;
            cursor += line.size() + 1;
            if (line.empty() || line[0] == L'=') continue;
            auto eq = line.find(L'=');
            if (eq == std::wstring::npos) continue;
            auto key = line.substr(0, eq);
            auto value = line.substr(eq + 1);
            if (_wcsicmp(key.c_str(), L"PATH") == 0) path_value = value;
            else if (_wcsicmp(key.c_str(), L"CUDA_PATH") == 0 || _wcsnicmp(key.c_str(), L"CUDA_PATH_V", 11) == 0 ||
                     _wcsicmp(key.c_str(), L"VALHALLA_QWEN_MODEL_DIR") == 0 || _wcsicmp(key.c_str(), L"VALHALLA_LM_MODEL") == 0 ||
                     _wcsicmp(key.c_str(), L"VALHALLA_LM_F16") == 0) {
                continue;
            } else vars.emplace_back(std::move(key), std::move(value));
        }
        FreeEnvironmentStringsW(raw);
    }
    const CudaRuntime& cuda = cached_cuda();
    if (!cuda.bin.empty() && GetFileAttributesW(cuda.bin.c_str()) != INVALID_FILE_ATTRIBUTES) {
        std::wstring prefix = cuda.bin;
        std::wstring tools = cuda.root + L"\\bin";
        if (_wcsicmp(tools.c_str(), cuda.bin.c_str()) != 0 && GetFileAttributesW(tools.c_str()) != INVALID_FILE_ATTRIBUTES) {
            prefix += L";" + tools;
        }
        path_value = prefix + L";" + path_value;
    }
    vars.emplace_back(L"PATH", path_value);
    if (!cuda.root.empty()) {
        vars.emplace_back(L"CUDA_PATH", cuda.root);
        if (cuda.major > 0) {
            wchar_t key[32];
            swprintf_s(key, L"CUDA_PATH_V%d_%d", cuda.major, cuda.minor);
            vars.emplace_back(key, cuda.root);
        }
    }
    vars.emplace_back(L"VALHALLA_QWEN_MODEL_DIR", model);
    vars.emplace_back(L"VALHALLA_LM_MODEL", model);
    vars.emplace_back(L"VALHALLA_LM_F16", L"1");
    std::wstring block;
    for (const auto& item : vars) {
        block += item.first;
        block.push_back(L'=');
        block += item.second;
        block.push_back(L'\0');
    }
    block.push_back(L'\0');
    return block;
}

bool drain_pipe(HANDLE pipe, std::string& out) {
    for (;;) {
        DWORD available = 0;
        if (!PeekNamedPipe(pipe, nullptr, 0, nullptr, &available, nullptr)) return false;
        if (available == 0) return true;
        std::string chunk(available, '\0');
        DWORD read = 0;
        if (!ReadFile(pipe, chunk.data(), available, &read, nullptr)) return false;
        chunk.resize(read);
        out += chunk;
        if (read == 0) return true;
    }
}

struct ChildPipes {
    HANDLE in_read = nullptr;
    HANDLE in_write = nullptr;
    HANDLE out_read = nullptr;
    HANDLE out_write = nullptr;
    HANDLE err_read = nullptr;
    HANDLE err_write = nullptr;
    ~ChildPipes() { close(); }
    void close() {
        HANDLE* all[] = {&in_read, &in_write, &out_read, &out_write, &err_read, &err_write};
        for (HANDLE* handle : all) {
            if (*handle) {
                CloseHandle(*handle);
                *handle = nullptr;
            }
        }
    }
};

bool make_pipe(HANDLE& read, HANDLE& write) {
    SECURITY_ATTRIBUTES security{sizeof(security), nullptr, TRUE};
    if (!CreatePipe(&read, &write, &security, 8 << 20)) return false;
    return true;
}

nlohmann::json parse_payload(const std::string& stdout_text, std::string& error) {
    auto start = stdout_text.find('{');
    auto end = stdout_text.rfind('}');
    if (start == std::string::npos || end == std::string::npos || end < start) {
        error = "输出里没有 JSON。\n" + stdout_text.substr(stdout_text.size() > 800 ? stdout_text.size() - 800 : 0);
        return nullptr;
    }
    try {
        return nlohmann::json::parse(stdout_text.substr(start, end - start + 1));
    } catch (const std::exception& ex) {
        error = ex.what();
        return nullptr;
    }
}

std::wstring url_encode(const std::string& value) {
    std::wstring out;
    static const char* hex = "0123456789ABCDEF";
    for (unsigned char ch : value) {
        if ((ch >= 'a' && ch <= 'z') || (ch >= 'A' && ch <= 'Z') || (ch >= '0' && ch <= '9') ||
            ch == '-' || ch == '_' || ch == '.' || ch == '~' || ch == '/') {
            out.push_back(static_cast<wchar_t>(ch));
        } else {
            out.push_back(L'%');
            out.push_back(static_cast<wchar_t>(hex[ch >> 4]));
            out.push_back(static_cast<wchar_t>(hex[ch & 15]));
        }
    }
    return out;
}

bool wanted_file(const std::string& path) {
    auto ends = [&](const char* suffix) {
        size_t n = strlen(suffix);
        return path.size() >= n && path.compare(path.size() - n, n, suffix) == 0;
    };
    if (ends(".safetensors") || ends(".json") || ends(".jinja")) return true;
    auto slash = path.find_last_of('/');
    std::string base = slash == std::string::npos ? path : path.substr(slash + 1);
    return base.rfind("tokenizer", 0) == 0;
}

struct HttpSession {
    HINTERNET session = nullptr;
    HttpSession() {
        session = WinHttpOpen(L"Valhalla/1.0", WINHTTP_ACCESS_TYPE_DEFAULT_PROXY, WINHTTP_NO_PROXY_NAME,
                               WINHTTP_NO_PROXY_BYPASS, 0);
        if (session) {
            WinHttpSetTimeouts(session, 15000, 15000, 30000, 1800000);
        }
    }
    ~HttpSession() {
        if (session) WinHttpCloseHandle(session);
    }
};

bool query_status(HINTERNET request, DWORD& status) {
    DWORD size = sizeof(status);
    return WinHttpQueryHeaders(request, WINHTTP_QUERY_STATUS_CODE | WINHTTP_QUERY_FLAG_NUMBER,
                               WINHTTP_HEADER_NAME_BY_INDEX, &status, &size, WINHTTP_NO_HEADER_INDEX) == TRUE;
}

struct GetRequest {
    HINTERNET connect = nullptr;
    HINTERNET request = nullptr;
    GetRequest() = default;
    GetRequest(const GetRequest&) = delete;
    GetRequest& operator=(const GetRequest&) = delete;
    GetRequest(GetRequest&& other) noexcept {
        connect = other.connect;
        request = other.request;
        other.connect = nullptr;
        other.request = nullptr;
    }
    GetRequest& operator=(GetRequest&& other) noexcept {
        if (this != &other) {
            if (request) WinHttpCloseHandle(request);
            if (connect) WinHttpCloseHandle(connect);
            connect = other.connect;
            request = other.request;
            other.connect = nullptr;
            other.request = nullptr;
        }
        return *this;
    }
    ~GetRequest() {
        if (request) WinHttpCloseHandle(request);
        if (connect) WinHttpCloseHandle(connect);
    }
};

GetRequest open_get(HINTERNET session, const std::wstring& path) {
    GetRequest out;
    out.connect = WinHttpConnect(session, L"huggingface.co", INTERNET_DEFAULT_HTTPS_PORT, 0);
    if (!out.connect) return out;
    out.request = WinHttpOpenRequest(out.connect, L"GET", path.c_str(), nullptr, WINHTTP_NO_REFERER,
                                      WINHTTP_DEFAULT_ACCEPT_TYPES, WINHTTP_FLAG_SECURE);
    return out;
}

void ensure_parent(const std::wstring& file) {
    auto slash = file.find_last_of(L"\\/");
    if (slash == std::wstring::npos) return;
    std::wstring dir = file.substr(0, slash);
    std::wstring partial;
    for (size_t i = 0; i < dir.size(); ++i) {
        partial.push_back(dir[i]);
        if (dir[i] == L'\\' || dir[i] == L'/') CreateDirectoryW(partial.c_str(), nullptr);
    }
    CreateDirectoryW(dir.c_str(), nullptr);
}

// ---- VALENC1 decryption (AES-256-GCM via Windows BCrypt) ----
bool file_exists_w(const std::wstring& path) {
    return !path.empty() && GetFileAttributesW(path.c_str()) != INVALID_FILE_ATTRIBUTES;
}

std::wstring dir_of_w(const std::wstring& path) {
    auto slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? std::wstring() : path.substr(0, slash);
}

std::wstring leaf_of_w(const std::wstring& path) {
    auto slash = path.find_last_of(L"\\/");
    return slash == std::wstring::npos ? path : path.substr(slash + 1);
}

bool read_exact(HANDLE file, void* buffer, DWORD size) {
    BYTE* out = static_cast<BYTE*>(buffer);
    DWORD done = 0;
    while (done < size) {
        DWORD got = 0;
        if (!ReadFile(file, out + done, size - done, &got, nullptr) || got == 0) return false;
        done += got;
    }
    return true;
}

bool write_exact(HANDLE file, const void* buffer, DWORD size) {
    const BYTE* in = static_cast<const BYTE*>(buffer);
    DWORD done = 0;
    while (done < size) {
        DWORD wrote = 0;
        if (!WriteFile(file, in + done, size - done, &wrote, nullptr) || wrote == 0) return false;
        done += wrote;
    }
    return true;
}

uint32_t load_le32(const BYTE* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

// Decrypts a VALENC1 file to dst (streaming, one 1MiB chunk at a time).
// On failure returns false, sets a Chinese error, and removes dst.
bool decrypt_valenc1(const std::wstring& src, const std::wstring& dst, std::wstring& error) {
    static constexpr BYTE kMagic[8] = {'V', 'A', 'L', 'E', 'N', 'C', '1', '\0'};
    auto fail = [&](const std::wstring& why) {
        error = why;
        DeleteFileW(dst.c_str());
        return false;
    };
    HANDLE in = CreateFileW(src.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (in == INVALID_HANDLE_VALUE) {
        error = L"无法打开加密文件。";
        return false;
    }
    BYTE header[12];
    if (!read_exact(in, header, sizeof(header)) || memcmp(header, kMagic, 8) != 0) {
        CloseHandle(in);
        error = L"不是 VALENC1 加密文件，文件头校验失败。";
        return false;
    }
    uint32_t chunk_size = load_le32(header + 8);
    if (chunk_size == 0 || chunk_size > (16u << 20)) {
        CloseHandle(in);
        error = L"VALENC1 分块大小异常。";
        return false;
    }
    BCRYPT_ALG_HANDLE alg = nullptr;
    BCRYPT_KEY_HANDLE key = nullptr;
    NTSTATUS status = BCryptOpenAlgorithmProvider(&alg, BCRYPT_AES_ALGORITHM, nullptr, 0);
    if (status >= 0) {
        status = BCryptSetProperty(alg, BCRYPT_CHAINING_MODE, reinterpret_cast<PUCHAR>(const_cast<wchar_t*>(BCRYPT_CHAIN_MODE_GCM)),
                                   static_cast<ULONG>(sizeof(BCRYPT_CHAIN_MODE_GCM)), 0);
    }
    if (status >= 0) {
        auto key_bytes = valkey::key();
        status = BCryptGenerateSymmetricKey(alg, &key, nullptr, 0, key_bytes.data(),
                                            static_cast<ULONG>(key_bytes.size()), 0);
    }
    if (status < 0) {
        if (alg) BCryptCloseAlgorithmProvider(alg, 0);
        CloseHandle(in);
        error = L"无法初始化 AES-256-GCM 解密（BCrypt）。";
        return false;
    }
    HANDLE out = CreateFileW(dst.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (out == INVALID_HANDLE_VALUE) {
        BCryptDestroyKey(key);
        BCryptCloseAlgorithmProvider(alg, 0);
        CloseHandle(in);
        error = L"无法写入解密后的文件（目录不可写？）。";
        return false;
    }
    bool ok = true;
    std::wstring why;
    std::vector<BYTE> cipher;
    std::vector<BYTE> plain;
    for (;;) {
        BYTE len_buf[4];
        DWORD got = 0;
        if (!ReadFile(in, len_buf, 4, &got, nullptr)) { ok = false; why = L"读取加密文件失败。"; break; }
        if (got == 0) break;
        if (got != 4) { ok = false; why = L"加密文件不完整（分块长度）。"; break; }
        uint32_t clen = load_le32(len_buf);
        if (clen <= 16 || clen - 16 > chunk_size) { ok = false; why = L"加密文件分块长度异常。"; break; }
        BYTE nonce[12];
        if (!read_exact(in, nonce, sizeof(nonce))) { ok = false; why = L"加密文件不完整（nonce）。"; break; }
        cipher.resize(clen);
        if (!read_exact(in, cipher.data(), clen)) { ok = false; why = L"加密文件不完整（密文）。"; break; }
        uint32_t plain_len = clen - 16;
        plain.resize(plain_len == 0 ? 1 : plain_len);
        BCRYPT_AUTHENTICATED_CIPHER_MODE_INFO info;
        BCRYPT_INIT_AUTH_MODE_INFO(info);
        info.pbNonce = nonce;
        info.cbNonce = sizeof(nonce);
        info.pbAuthData = const_cast<BYTE*>(kMagic);
        info.cbAuthData = sizeof(kMagic);
        info.pbTag = cipher.data() + plain_len;
        info.cbTag = 16;
        ULONG produced = 0;
        status = BCryptDecrypt(key, cipher.data(), plain_len, &info, nullptr, 0,
                               plain_len ? plain.data() : nullptr, plain_len, &produced, 0);
        if (status < 0) { ok = false; why = L"解密校验失败（密钥不匹配或文件损坏）。"; break; }
        if (produced != plain_len || (plain_len && !write_exact(out, plain.data(), produced))) {
            ok = false; why = L"写入解密文件失败。"; break;
        }
    }
    CloseHandle(out);
    BCryptDestroyKey(key);
    BCryptCloseAlgorithmProvider(alg, 0);
    CloseHandle(in);
    if (!ok) return fail(why);
    return true;
}

std::wstring g_temp_binary;
std::wstring g_last_binary_error;
bool g_atexit_registered = false;
void (*g_exit_cleanup_hook)() = nullptr;  // Set to stop_warm_locked once a warm process runs.

void cleanup_temp_binary_at_exit() {
    if (g_exit_cleanup_hook) g_exit_cleanup_hook();
    for (int i = 0; i < 30 && !g_temp_binary.empty(); ++i) {
        if (DeleteFileW(g_temp_binary.c_str()) || !file_exists_w(g_temp_binary)) {
            g_temp_binary.clear();
            break;
        }
        Sleep(100);
    }
}

void try_delete_temp_binary() {
    if (g_temp_binary.empty()) return;
    for (int i = 0; i < 20; ++i) {
        if (DeleteFileW(g_temp_binary.c_str()) || !file_exists_w(g_temp_binary)) {
            g_temp_binary.clear();
            return;
        }
        Sleep(50);
    }
    // If deletion still fails the file is in use; keep the path so it is reused / retried at exit.
}

void cleanup_orphan_temp_exes(const std::wstring& dir) {
    if (dir.empty()) return;
    WIN32_FIND_DATAW data{};
    HANDLE search = FindFirstFileW((dir + L"\\valhalla_base_*.exe").c_str(), &data);
    if (search == INVALID_HANDLE_VALUE) return;
    do {
        if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
        std::wstring full = dir + L"\\" + data.cFileName;
        if (!g_temp_binary.empty() && _wcsicmp(full.c_str(), g_temp_binary.c_str()) == 0) continue;
        DeleteFileW(full.c_str());  // Running exes refuse deletion; those are skipped silently.
    } while (FindNextFileW(search, &data));
    FindClose(search);
}

// Decrypts an .enc engine binary next to it into a random temp exe in the same
// directory (CUDA DLLs and the child working directory live there).
std::wstring materialize_enc_binary(const std::wstring& enc_path) {
    std::wstring dir = dir_of_w(enc_path);
    if (!g_temp_binary.empty() && file_exists_w(g_temp_binary) &&
        _wcsicmp(dir_of_w(g_temp_binary).c_str(), dir.c_str()) == 0) {
        return g_temp_binary;
    }
    cleanup_orphan_temp_exes(dir);
    BYTE random_bytes[8] = {};
    BCryptGenRandom(nullptr, random_bytes, sizeof(random_bytes), BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    uint32_t r0 = load_le32(random_bytes);
    uint32_t r1 = load_le32(random_bytes + 4);
    wchar_t name[96];
    swprintf_s(name, L"valhalla_base_%lu_%08X%08X.exe", GetCurrentProcessId(), r0, r1);
    std::wstring temp = dir + L"\\" + name;
    std::wstring error;
    if (!decrypt_valenc1(enc_path, temp, error)) {
        g_last_binary_error = L"引擎解密失败：" + error;
        DeleteFileW(temp.c_str());
        return L"";
    }
    g_temp_binary = temp;
    if (!g_atexit_registered) {
        std::atexit(cleanup_temp_binary_at_exit);
        g_atexit_registered = true;
    }
    return temp;
}

std::wstring resolve_binary() {
    wchar_t buffer[32768];
    DWORD count = GetEnvironmentVariableW(L"VALHALLA_BASE_EXE", buffer, 32768);
    if (count > 0 && count < 32768 && file_exists_w(buffer)) return buffer;
    // Installed layout: engine next to this app's exe.
    wchar_t module_path[32768];
    DWORD module_len = GetModuleFileNameW(nullptr, module_path, 32768);
    if (module_len > 0 && module_len < 32768) {
        std::wstring dir = dir_of_w(module_path);
        cleanup_orphan_temp_exes(dir);
        std::wstring plain = dir + L"\\valhalla_base.exe";
        if (file_exists_w(plain)) return plain;
        std::wstring enc = plain + L".enc";
        if (file_exists_w(enc)) return materialize_enc_binary(enc);
    }
    if (file_exists_w(kDefaultBinary)) return kDefaultBinary;
    std::wstring dev_enc = std::wstring(kDefaultBinary) + L".enc";
    if (file_exists_w(dev_enc)) return materialize_enc_binary(dev_enc);
    return L"";
}

bool file_size_mtime(const std::wstring& path, ULONGLONG& size, ULONGLONG& mtime) {
    WIN32_FILE_ATTRIBUTE_DATA data{};
    if (!GetFileAttributesExW(path.c_str(), GetFileExInfoStandard, &data)) return false;
    size = (static_cast<ULONGLONG>(data.nFileSizeHigh) << 32) | data.nFileSizeLow;
    mtime = (static_cast<ULONGLONG>(data.ftLastWriteTime.dwHighDateTime) << 32) | data.ftLastWriteTime.dwLowDateTime;
    return true;
}

// If source holds *.enc files, decrypt them into <parent>\.cache\<leaf> and
// return that directory; otherwise return source unchanged.
bool resolve_model_dir(const std::wstring& source, std::wstring& resolved, std::wstring& error) {
    resolved = source;
    struct EncItem { std::wstring enc; std::wstring plain_name; ULONGLONG enc_size = 0; ULONGLONG mtime = 0; };
    std::vector<EncItem> items;
    WIN32_FIND_DATAW data{};
    HANDLE search = FindFirstFileW((source + L"\\*.enc").c_str(), &data);
    if (search != INVALID_HANDLE_VALUE) {
        do {
            if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            std::wstring name = data.cFileName;
            if (name.size() <= 4) continue;
            EncItem item;
            item.enc = source + L"\\" + name;
            item.plain_name = name.substr(0, name.size() - 4);
            file_size_mtime(item.enc, item.enc_size, item.mtime);
            items.push_back(item);
        } while (FindNextFileW(search, &data));
        FindClose(search);
    }
    if (items.empty()) return true;
    std::wstring parent = dir_of_w(source);
    std::wstring cache_root = parent + L"\\.cache";
    std::wstring cache = cache_root + L"\\" + leaf_of_w(source);
    CreateDirectoryW(cache_root.c_str(), nullptr);
    CreateDirectoryW(cache.c_str(), nullptr);
    // Cache hit: .done records name|enc_size|mtime|plain_size for every source .enc.
    std::wstring done_path = cache + L"\\.done";
    std::string done_text;
    {
        HANDLE f = CreateFileW(done_path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (f != INVALID_HANDLE_VALUE) {
            DWORD sz = GetFileSize(f, nullptr);
            if (sz != INVALID_FILE_SIZE && sz < (1 << 20)) {
                done_text.resize(sz);
                DWORD got = 0;
                ReadFile(f, done_text.data(), sz, &got, nullptr);
                done_text.resize(got);
            }
            CloseHandle(f);
        }
    }
    bool hit = !done_text.empty();
    if (hit) {
        size_t lines = 0;
        for (const auto& item : items) {
            ULONGLONG sz = 0, mt = 0;
            if (!file_size_mtime(cache + L"\\" + item.plain_name, sz, mt)) { hit = false; break; }
            std::string want = wide_to_utf8(item.plain_name) + "|" + std::to_string(item.enc_size) + "|" +
                               std::to_string(item.mtime) + "|" + std::to_string(sz);
            if (done_text.find(want) == std::string::npos) { hit = false; break; }
            ++lines;
        }
        (void)lines;
    }
    if (hit) {
        resolved = cache;
        return true;
    }
    for (const auto& item : items) {
        std::wstring target = cache + L"\\" + item.plain_name;
        std::wstring tmp = target + L".tmp";
        std::wstring dec_error;
        if (!decrypt_valenc1(item.enc, tmp, dec_error)) {
            DeleteFileW(tmp.c_str());
            error = L"模型解密失败：无法解密 " + item.plain_name + L".enc：" + dec_error;
            return false;
        }
        if (!MoveFileExW(tmp.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
            DeleteFileW(tmp.c_str());
            error = L"模型解密失败：无法写入缓存文件 " + item.plain_name + L"。";
            return false;
        }
    }
    // Copy any plaintext companions (mixed directories) into the cache too.
    HANDLE plain_search = FindFirstFileW((source + L"\\*").c_str(), &data);
    if (plain_search != INVALID_HANDLE_VALUE) {
        do {
            if (data.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) continue;
            std::wstring name = data.cFileName;
            if (name.size() > 4 && _wcsicmp(name.c_str() + name.size() - 4, L".enc") == 0) continue;
            CopyFileW((source + L"\\" + name).c_str(), (cache + L"\\" + name).c_str(), FALSE);
        } while (FindNextFileW(plain_search, &data));
        FindClose(plain_search);
    }
    std::string done_out;
    for (const auto& item : items) {
        ULONGLONG sz = 0, mt = 0;
        file_size_mtime(cache + L"\\" + item.plain_name, sz, mt);
        done_out += wide_to_utf8(item.plain_name) + "|" + std::to_string(item.enc_size) + "|" +
                    std::to_string(item.mtime) + "|" + std::to_string(sz) + "\n";
    }
    HANDLE f = CreateFileW(done_path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f != INVALID_HANDLE_VALUE) {
        DWORD wrote = 0;
        WriteFile(f, done_out.data(), static_cast<DWORD>(done_out.size()), &wrote, nullptr);
        CloseHandle(f);
    }
    resolved = cache;
    return true;
}

}  // namespace

void save_settings(const std::wstring& path, const Settings& settings);

Settings load_settings(const std::wstring& path) {
    Settings settings;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) {
        save_settings(path, settings);
        return settings;
    }
    DWORD size = GetFileSize(file, nullptr);
    std::string raw(size, '\0');
    DWORD read = 0;
    ReadFile(file, raw.data(), size, &read, nullptr);
    CloseHandle(file);
    raw.resize(read);
    try {
        auto json = nlohmann::json::parse(raw);
        if (json.contains("language")) settings.language = json.value("language", settings.language);
        if (json.contains("strategy")) settings.strategy = json.value("strategy", settings.strategy);
        if (json.contains("model_repo")) settings.model_repo = json.value("model_repo", settings.model_repo);
        if (json.contains("knowledge") && json["knowledge"].is_string()) settings.knowledge = json["knowledge"].get<std::string>();
        if (json.contains("keep_session")) settings.keep_session = json.value("keep_session", true);
        if (json.contains("allow_control")) settings.allow_control = json.value("allow_control", false);
    } catch (const std::exception&) {
    }
    return settings;
}

void save_settings(const std::wstring& path, const Settings& settings) {
    nlohmann::json json = {
        {"language", settings.language},
        {"strategy", settings.strategy},
        {"model_repo", settings.model_repo},
        {"knowledge", settings.knowledge},
        {"keep_session", settings.keep_session},
        {"allow_control", settings.allow_control},
    };
    std::string raw = json.dump(2);
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD wrote = 0;
    WriteFile(file, raw.data(), static_cast<DWORD>(raw.size()), &wrote, nullptr);
    CloseHandle(file);
}

Transcript load_transcript(const std::wstring& path) {
    Transcript transcript;
    HANDLE file = CreateFileW(path.c_str(), GENERIC_READ, FILE_SHARE_READ, nullptr, OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return transcript;
    DWORD size = GetFileSize(file, nullptr);
    std::string raw(size, '\0');
    DWORD read = 0;
    ReadFile(file, raw.data(), size, &read, nullptr);
    CloseHandle(file);
    raw.resize(read);
    try {
        auto json = nlohmann::json::parse(raw);
        if (json.contains("lines") && json["lines"].is_array()) {
            for (const auto& item : json["lines"]) {
                TranscriptLine line;
                line.user = item.value("user", false);
                line.text = item.value("text", "");
                line.path = item.value("path", "");
                transcript.lines.push_back(std::move(line));
            }
        }
        if (json.contains("history") && json["history"].is_array()) {
            for (const auto& item : json["history"]) {
                transcript.history.emplace_back(item.value("user", ""), item.value("assistant", ""));
            }
        }
        if (json.contains("session") && json["session"].is_object()) transcript.session_json = json["session"].dump();
    } catch (const std::exception&) {
    }
    return transcript;
}

void save_transcript(const std::wstring& path, const Transcript& transcript) {
    nlohmann::json lines = nlohmann::json::array();
    for (const auto& line : transcript.lines) {
        lines.push_back({{"user", line.user}, {"text", line.text}, {"path", line.path}});
    }
    nlohmann::json history = nlohmann::json::array();
    for (const auto& turn : transcript.history) {
        history.push_back({{"user", turn.first}, {"assistant", turn.second}});
    }
    nlohmann::json session = nullptr;
    if (!transcript.session_json.empty()) {
        try {
            session = nlohmann::json::parse(transcript.session_json);
        } catch (const std::exception&) {
            session = nullptr;
        }
    }
    nlohmann::json json = {{"lines", lines}, {"history", history}, {"session", session}};
    std::string raw = json.dump();
    HANDLE file = CreateFileW(path.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD wrote = 0;
    WriteFile(file, raw.data(), static_cast<DWORD>(raw.size()), &wrote, nullptr);
    CloseHandle(file);
}

std::wstring find_binary() {
    return resolve_binary();
}

std::wstring models_root() {
    wchar_t buffer[32768];
    DWORD count = GetEnvironmentVariableW(L"VALHALLA_MODELS_ROOT", buffer, 32768);
    if (count > 0 && count < 32768) return buffer;
    const std::wstring exe = find_binary();
    const auto slash = exe.find_last_of(L"\\/");
    if (slash != std::wstring::npos) {
        const std::wstring beside = exe.substr(0, slash) + L"\\models";
        if (GetFileAttributesW(beside.c_str()) != INVALID_FILE_ATTRIBUTES) return beside;
    }
    return kModelsRoot;
}

std::wstring model_directory(const std::string& repo_id) {
    return models_root() + L"\\" + leaf_name(repo_id);
}

bool weights_present(const std::wstring& directory) {
    auto weights = directory + L"\\model.safetensors";
    auto index = directory + L"\\model.safetensors.index.json";
    return GetFileAttributesW(weights.c_str()) != INVALID_FILE_ATTRIBUTES ||
           GetFileAttributesW(index.c_str()) != INVALID_FILE_ATTRIBUTES ||
           GetFileAttributesW((weights + L".enc").c_str()) != INVALID_FILE_ATTRIBUTES ||
           GetFileAttributesW((index + L".enc").c_str()) != INVALID_FILE_ATTRIBUTES;
}

struct WarmProcess {
    PROCESS_INFORMATION process{};
    HANDLE in_write = nullptr;
    HANDLE out_read = nullptr;
    HANDLE err_read = nullptr;
    std::wstring model;
    bool weights_resident = false;
};

WarmProcess g_warm;
std::mutex g_warm_mu;
std::wstring g_gpu_note;

void close_warm_handles() {
    if (g_warm.in_write) CloseHandle(g_warm.in_write);
    if (g_warm.out_read) CloseHandle(g_warm.out_read);
    if (g_warm.err_read) CloseHandle(g_warm.err_read);
    if (g_warm.process.hThread) CloseHandle(g_warm.process.hThread);
    if (g_warm.process.hProcess) CloseHandle(g_warm.process.hProcess);
    g_warm = {};
}

void stop_warm_locked() {
    if (g_warm.process.hProcess) TerminateProcess(g_warm.process.hProcess, 0);
    close_warm_handles();
    try_delete_temp_binary();
}

bool warm_alive() {
    return g_warm.process.hProcess && WaitForSingleObject(g_warm.process.hProcess, 0) == WAIT_TIMEOUT;
}

bool start_warm(const std::wstring& model, std::string& error) {
    stop_warm_locked();
    std::wstring binary = resolve_binary();
    if (binary.empty()) {
        error = g_last_binary_error.empty() ? "找不到 valhalla_base.exe 或 valhalla_base.exe.enc。" : wide_to_utf8(g_last_binary_error);
        return false;
    }
    ChildPipes pipes;
    if (!make_pipe(pipes.in_read, pipes.in_write) || !make_pipe(pipes.out_read, pipes.out_write) ||
        !make_pipe(pipes.err_read, pipes.err_write)) {
        error = "无法创建管道。";
        return false;
    }
    SetHandleInformation(pipes.in_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(pipes.out_read, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(pipes.err_read, HANDLE_FLAG_INHERIT, 0);
    std::wstring command = L"\"" + binary + L"\" --repl";
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');
    std::wstring directory = binary;
    auto slash = directory.find_last_of(L"\\/");
    if (slash != std::wstring::npos) directory.resize(slash);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdInput = pipes.in_read;
    startup.hStdOutput = pipes.out_write;
    startup.hStdError = pipes.err_write;
    PROCESS_INFORMATION process{};
    std::wstring environment = env_block(model);
    if (!CreateProcessW(binary.c_str(), mutable_command.data(), nullptr, nullptr, TRUE,
                        CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT, environment.data(), directory.c_str(), &startup,
                        &process)) {
        error = "无法启动 valhalla_base.exe。";
        return false;
    }
    CloseHandle(pipes.in_read);
    pipes.in_read = nullptr;
    CloseHandle(pipes.out_write);
    pipes.out_write = nullptr;
    CloseHandle(pipes.err_write);
    pipes.err_write = nullptr;
    g_warm.process = process;
    g_exit_cleanup_hook = &stop_warm_locked;
    g_warm.in_write = pipes.in_write;
    g_warm.out_read = pipes.out_read;
    g_warm.err_read = pipes.err_read;
    g_warm.model = model;
    pipes.in_write = nullptr;
    pipes.out_read = nullptr;
    pipes.err_read = nullptr;
    return true;
}

void note_gpu(const std::string& stderr_text) {
    if (stderr_text.find("loading weights") != std::string::npos || stderr_text.find("resident workspace") != std::string::npos) {
        g_warm.weights_resident = true;
    }
    if (!g_gpu_note.empty()) return;
    if (stderr_text.find("CUDA device") != std::string::npos) g_gpu_note = L"CUDA";
    else if (stderr_text.find("cpu=true") != std::string::npos) g_gpu_note = L"CPU";
}

bool warm_exchange(const nlohmann::json& request, nlohmann::json& row, std::string& session_out, std::string& error) {
    std::string payload = request.dump();
    payload.push_back('\n');
    size_t sent = 0;
    while (sent < payload.size()) {
        DWORD chunk = 0;
        DWORD ask = static_cast<DWORD>(std::min<size_t>(payload.size() - sent, 1 << 20));
        if (!WriteFile(g_warm.in_write, payload.data() + sent, ask, &chunk, nullptr) || chunk == 0) {
            stop_warm_locked();
            error = "无法把问题送进解码进程。";
            return false;
        }
        sent += chunk;
    }
    std::string stdout_text;
    std::string stderr_text;
    ULONGLONG started = GetTickCount64();
    while (stdout_text.find('\n') == std::string::npos) {
        drain_pipe(g_warm.err_read, stderr_text);
        drain_pipe(g_warm.out_read, stdout_text);
        note_gpu(stderr_text);
        if (!warm_alive()) break;
        if (GetTickCount64() - started > 300000) {
            stop_warm_locked();
            error = "回答超时。";
            return false;
        }
        Sleep(15);
    }
    note_gpu(stderr_text);
    auto newline = stdout_text.find('\n');
    if (newline == std::string::npos) {
        std::string detail = trim_utf8(stderr_text.empty() ? stdout_text : stderr_text);
        if (detail.size() > 1200) detail = detail.substr(detail.size() - 1200);
        stop_warm_locked();
        error = detail.empty() ? "解码进程已退出。" : detail;
        return false;
    }
    std::string parse_error;
    nlohmann::json body = parse_payload(stdout_text.substr(0, newline), parse_error);
    if (!parse_error.empty()) {
        error = parse_error;
        return false;
    }
    if (body.contains("error") && (!body.contains("rows") || !body["rows"].is_array())) {
        error = body.value("error", "error");
        return false;
    }
    if (!body.contains("rows") || !body["rows"].is_array() || body["rows"].empty()) {
        error = "valhalla_base 没有返回答案行。";
        return false;
    }
    row = body["rows"][0];
    if (body.contains("session") && body["session"].is_object()) session_out = body["session"].dump();
    return true;
}

bool ensure_framework_locked(const std::wstring& model, std::string& error) {
    if (!warm_alive() || g_warm.model != model) {
        if (!start_warm(model, error)) return false;
    }
    if (g_warm.weights_resident) return true;
    nlohmann::json config = {
        {"decode", "lm_patch"},
        {"lm_model", wide_to_utf8(model)},
        {"mcq_decode", "lm_patch"},
        {"follow_up_decode", "lm_patch_on_follow_up"},
        {"fate_ingress_routing", "quad_cycle"},
        {"fate_qa_feedback", false},
        {"open_fate", false},
        {"use_cpu", false},
        {"proactive_enabled", false},
        {"multihop_fate", false},
        {"multihop_v2", false},
        {"max_new", 1},
    };
    nlohmann::json request = {
        {"context", nlohmann::json::array({"Valhalla stays resident."})},
        {"questions", nlohmann::json::array({{{"id", "q0"}, {"text", "ok"}, {"score_type", "open"}}})},
        {"config", config},
    };
    nlohmann::json row;
    std::string session;
    if (!warm_exchange(request, row, session, error)) return false;
    g_warm.weights_resident = true;
    return true;
}

std::wstring ensure_framework(const std::wstring& model_dir) {
    std::lock_guard<std::mutex> lock(g_warm_mu);
    if (!weights_present(model_dir)) return L"模型权重不在。";
    std::wstring resolved;
    std::wstring dec_error;
    if (!resolve_model_dir(model_dir, resolved, dec_error)) return dec_error;
    std::string error;
    if (!ensure_framework_locked(resolved, error)) return utf8_to_wide(error);
    return L"";
}

void stop_warm_process() {
    std::lock_guard<std::mutex> lock(g_warm_mu);
    stop_warm_locked();
}

std::wstring gpu_status() {
    std::lock_guard<std::mutex> lock(g_warm_mu);
    return g_gpu_note;
}

CudaRuntime cuda_runtime() { return cached_cuda(); }

std::wstring format_cuda(bool zh) {
    const CudaRuntime& cuda = cached_cuda();
    std::wstring line;
    if (cuda.version.empty()) {
        line = zh ? L"未发现 CUDA 运行库" : L"No CUDA runtime found";
    } else if (cuda.loaded) {
        line = zh ? L"CUDA " + cuda.version + L" 运行库已加载" : L"CUDA " + cuda.version + L" runtime loaded";
    } else {
        line = zh ? L"CUDA " + cuda.version + L" 已发现，运行库没有加载" : L"CUDA " + cuda.version + L" found, runtime did not load";
    }
    if (!cuda.others.empty()) {
        line += zh ? L"，另有 " : L", also ";
        for (size_t i = 0; i < cuda.others.size(); ++i) {
            if (i) line += L", ";
            line += cuda.others[i];
        }
    }
    if (!cuda.driver.empty()) line += (zh ? L"，驱动 " : L", driver ") + cuda.driver;
    return line;
}

FeatureReport run_feature_probe(bool zh) {
    FeatureReport report;
    std::wstring binary = resolve_binary();
    auto add = [&](const std::wstring& line) {
        if (!report.text.empty()) report.text += L"\n";
        report.text += line;
    };
    add(format_cuda(zh));
    if (binary.empty()) {
        add(zh ? L"特性检查未通过：找不到 valhalla_base.exe。" : L"Feature check failed: valhalla_base.exe was not found.");
        return report;
    }
    ChildPipes pipes;
    if (!make_pipe(pipes.in_read, pipes.in_write) || !make_pipe(pipes.out_read, pipes.out_write) || !make_pipe(pipes.err_read, pipes.err_write)) {
        add(zh ? L"特性检查未通过：无法创建管道。" : L"Feature check failed: could not create pipes.");
        return report;
    }
    SetHandleInformation(pipes.in_write, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(pipes.out_read, HANDLE_FLAG_INHERIT, 0);
    SetHandleInformation(pipes.err_read, HANDLE_FLAG_INHERIT, 0);
    std::wstring command = L"\"" + binary + L"\" --repl";
    std::vector<wchar_t> mutable_command(command.begin(), command.end());
    mutable_command.push_back(L'\0');
    std::wstring directory = binary;
    auto slash = directory.find_last_of(L"\\/");
    if (slash != std::wstring::npos) directory.resize(slash);
    STARTUPINFOW startup{};
    startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES | STARTF_USESHOWWINDOW;
    startup.wShowWindow = SW_HIDE;
    startup.hStdInput = pipes.in_read;
    startup.hStdOutput = pipes.out_write;
    startup.hStdError = pipes.err_write;
    PROCESS_INFORMATION process{};
    std::wstring environment = env_block(L"");
    if (!CreateProcessW(binary.c_str(), mutable_command.data(), nullptr, nullptr, TRUE, CREATE_NO_WINDOW | CREATE_UNICODE_ENVIRONMENT,
                        environment.data(), directory.c_str(), &startup, &process)) {
        add(zh ? L"特性检查未通过：无法启动解码进程。" : L"Feature check failed: the decoder process did not start.");
        return report;
    }
    CloseHandle(pipes.in_read);
    pipes.in_read = nullptr;
    CloseHandle(pipes.out_write);
    pipes.out_write = nullptr;
    CloseHandle(pipes.err_write);
    pipes.err_write = nullptr;

    auto ask = [&](const nlohmann::json& request, nlohmann::json& body, std::string& error) -> bool {
        std::string payload = request.dump();
        payload.push_back('\n');
        DWORD written = 0;
        if (!WriteFile(pipes.in_write, payload.data(), static_cast<DWORD>(payload.size()), &written, nullptr) || written != payload.size()) {
            error = "write";
            return false;
        }
        std::string stdout_text;
        std::string stderr_text;
        ULONGLONG started = GetTickCount64();
        while (stdout_text.find('\n') == std::string::npos) {
            drain_pipe(pipes.err_read, stderr_text);
            drain_pipe(pipes.out_read, stdout_text);
            if (WaitForSingleObject(process.hProcess, 0) != WAIT_TIMEOUT) break;
            if (GetTickCount64() - started > 30000) {
                error = "timeout";
                return false;
            }
            Sleep(10);
        }
        auto newline = stdout_text.find('\n');
        if (newline == std::string::npos) {
            error = stderr_text.empty() ? "exit" : stderr_text;
            return false;
        }
        body = parse_payload(stdout_text.substr(0, newline), error);
        return error.empty() && body.is_object() && body.contains("rows");
    };

    nlohmann::json config = {
        {"decode", "hybrid"},
        {"lm_model", "c:\\Ai\\models\\Qwen2.5-3B-Instruct"},
        {"mcq_decode", "lm_patch"},
        {"follow_up_decode", "native_follow_up_aware"},
        {"fate_ingress_routing", "quad_cycle"},
        {"fate_qa_feedback", true},
        {"open_fate", true},
        {"use_cpu", true},
        {"proactive_enabled", false},
        {"multihop_fate", false},
        {"multihop_v2", false},
        {"max_new", 8},
    };
    nlohmann::json first_request = {
        {"context", nlohmann::json::array({"ValhallaBase decode mode is hybrid: native retrieval, then a full sentence.", "The passphrase is Qingniao."})},
        {"questions", nlohmann::json::array({{{"id", "q0"}, {"text", "What is the decode mode?"}, {"score_type", "open"}}})},
        {"config", config},
    };
    nlohmann::json first;
    std::string error;
    bool native_ok = false;
    bool fate_ok = false;
    bool memory_ok = false;
    bool single_load = false;
    std::string stderr_text;
    if (!ask(first_request, first, error)) {
        add(zh ? L"特性检查未通过：第一轮没有返回。" : L"Feature check failed: the first turn returned nothing.");
        if (!error.empty()) add(utf8_to_wide(error).substr(0, 240));
    } else if (!first.contains("rows") || !first["rows"].is_array() || first["rows"].empty() || !first.contains("session")) {
        add(zh ? L"特性检查未通过：第一轮没有会话。" : L"Feature check failed: the first turn had no session.");
    } else {
        std::string path = first["rows"][0].value("decode_path", "");
        native_ok = path.find("native") != std::string::npos && path.find("open_fate") != std::string::npos &&
                    !first["rows"][0].value("answer", "").empty();
        nlohmann::json second_request = {
            {"context", nlohmann::json::array()},
            {"questions", nlohmann::json::array({{{"id", "q0"}, {"text", "What is the passphrase?"}, {"score_type", "open"}}})},
            {"config", config},
            {"session", first["session"]},
        };
        nlohmann::json second;
        if (!ask(second_request, second, error) || !second.contains("session")) {
            add(zh ? L"特性检查未通过：第二轮没有沿用会话。" : L"Feature check failed: the second turn did not keep the session.");
        } else {
            std::string second_path = second["rows"][0].value("decode_path", "");
            fate_ok = second_path.find("native") != std::string::npos && second_path.find("open_fate") != std::string::npos;
            int rounds = second["session"]["fate_algebra_meta"].value("fusion_rounds", 0);
            int stack = second["session"].contains("fate_rollback_stack") && second["session"]["fate_rollback_stack"].is_array()
                            ? static_cast<int>(second["session"]["fate_rollback_stack"].size())
                            : 0;
            int history = second["session"].contains("question_history") && second["session"]["question_history"].is_array()
                              ? static_cast<int>(second["session"]["question_history"].size())
                              : 0;
            memory_ok = rounds >= 1 && stack >= 1 && history >= 2;
            drain_pipe(pipes.err_read, stderr_text);
            int loads = 0;
            for (size_t at = 0; (at = stderr_text.find("loading weights", at)) != std::string::npos; at += 15) ++loads;
            single_load = loads == 0;
            wchar_t detail[160];
            swprintf_s(detail, zh ? L"融合轮次 %d，回滚点 %d，问题历史 %d。" : L"Fusion rounds %d, rollback points %d, question history %d.",
                       rounds, stack, history);
            add(std::wstring(zh ? L"原生检索与 open fate：" : L"Native retrieval and open fate: ") + (native_ok && fate_ok ? (zh ? L"通过" : L"pass") : (zh ? L"未通过" : L"fail")));
            add(std::wstring(zh ? L"长期会话：" : L"Long-run session: ") + (memory_ok ? (zh ? L"通过。 " : L"pass. ") : (zh ? L"未通过。 " : L"fail. ")) + detail);
            add(std::wstring(zh ? L"特性检查没有重新加载模型：" : L"Feature check did not reload the model: ") + (single_load ? (zh ? L"通过" : L"pass") : (zh ? L"未通过" : L"fail")));
        }
    }
    CloseHandle(pipes.in_write);
    pipes.in_write = nullptr;
    if (WaitForSingleObject(process.hProcess, 2000) == WAIT_TIMEOUT) TerminateProcess(process.hProcess, 0);
    CloseHandle(process.hThread);
    CloseHandle(process.hProcess);
    try_delete_temp_binary();
    report.ok = native_ok && fate_ok && memory_ok && single_load;
    add(report.ok ? (zh ? L"Valhalla 特性运行正常。" : L"Valhalla features are running.") : (zh ? L"Valhalla 特性检查未通过。" : L"Valhalla feature check did not pass."));
    return report;
}

TurnResult run_chat(
    const std::string& knowledge,
    const std::string& question,
    const std::string& mode,
    const std::wstring& model_dir,
    const std::string& session_json,
    const std::vector<std::pair<std::string, std::string>>& history,
    const std::string& screen,
    bool allow_control) {
    TurnResult result;
    if (trim_utf8(question).empty()) {
        result.error = "empty question";
        return result;
    }
    if (!weights_present(model_dir)) {
        result.error = wide_to_utf8(model_dir);
        return result;
    }
    std::wstring resolved_model;
    std::wstring dec_error;
    if (!resolve_model_dir(model_dir, resolved_model, dec_error)) {
        result.error = wide_to_utf8(dec_error);
        return result;
    }
    std::wstring binary = resolve_binary();
    if (binary.empty()) {
        result.error = g_last_binary_error.empty() ? "找不到 valhalla_base.exe 或 valhalla_base.exe.enc。" : wide_to_utf8(g_last_binary_error);
        return result;
    }

    bool mcq = mode == "mcq";
    bool multihop = mode == "multihop";
    bool has_session = !session_json.empty();
    nlohmann::json session;
    if (has_session) {
        try {
            session = nlohmann::json::parse(session_json);
        } catch (const std::exception& ex) {
            result.error = ex.what();
            return result;
        }
    }
    auto lines = has_session ? std::vector<std::string>{} : knowledge_lines(knowledge);
    if (!has_session && lines.empty()) {
        result.error = "语料至少要有一行。";
        return result;
    }

    nlohmann::json retrieval_config = {
        {"decode", "hybrid"},
        {"lm_model", wide_to_utf8(resolved_model)},
        {"mcq_decode", "lm_patch"},
        {"follow_up_decode", "native_follow_up_aware"},
        {"fate_ingress_routing", "quad_cycle"},
        {"fate_qa_feedback", true},
        {"open_fate", !mcq},
        {"use_cpu", false},
        {"proactive_enabled", false},
        {"multihop_fate", multihop},
        {"multihop_v2", multihop},
        {"max_new", mcq ? 32 : 64},
    };
    nlohmann::json retrieval = {
        {"context", lines},
        {"questions", nlohmann::json::array({{{"id", "q0"}, {"text", question}, {"score_type", mcq ? "mcq" : "open"}}})},
        {"config", retrieval_config},
    };
    if (has_session) retrieval["session"] = session;

    std::lock_guard<std::mutex> lock(g_warm_mu);
    std::string start_error;
    if (!ensure_framework_locked(resolved_model, start_error)) {
        result.error = start_error;
        return result;
    }
    nlohmann::json row;
    std::string kept_session;
    if (!warm_exchange(retrieval, row, kept_session, result.error)) return result;
    // A failed or empty session reply must not wipe the trajectory already on disk.
    result.session_json = kept_session.empty() ? session_json : kept_session;
    result.decode_path = row.value("decode_path", "");
    result.answer = row.value("answer", "");

    if (mcq) {
        const std::string prefix = "ANSWER:";
        if (result.answer.rfind(prefix, 0) == 0) {
            result.answer = trim_utf8(result.answer.substr(prefix.size()));
        }
        if (result.answer.empty()) result.answer = "(empty)";
        return result;
    }

    bool bind = retrieval_binds(mode, question, row);
    std::string evidence = bind ? citation_body(result.answer) : std::string();
    nlohmann::json spoken_session;
    if (!kept_session.empty()) {
        try {
            spoken_session = nlohmann::json::parse(kept_session);
        } catch (const std::exception&) {
            spoken_session = nullptr;
        }
    }
    nlohmann::json spoken_config = {
        {"decode", "lm_patch"},
        {"lm_model", wide_to_utf8(resolved_model)},
        {"mcq_decode", "lm_patch"},
        {"follow_up_decode", "lm_patch_on_follow_up"},
        {"fate_ingress_routing", "quad_cycle"},
        {"fate_qa_feedback", false},
        {"open_fate", false},
        {"use_cpu", false},
        {"proactive_enabled", false},
        {"multihop_fate", false},
        {"multihop_v2", false},
        {"max_new", 320},
    };
    std::string spoken_text = chat_prompt(knowledge, question, history, screen, allow_control, evidence);
    nlohmann::json spoken = {
        {"context", spoken_session.is_object() ? nlohmann::json::array() : nlohmann::json(lines)},
        {"questions", nlohmann::json::array({{{"id", "q0"}, {"text", spoken_text}, {"score_type", "open"}}})},
        {"config", spoken_config},
    };
    if (spoken_session.is_object()) spoken["session"] = spoken_session;
    nlohmann::json spoken_row;
    std::string discarded_session;
    std::string spoken_error;
    if (!warm_exchange(spoken, spoken_row, discarded_session, spoken_error)) {
        if (result.answer.empty()) {
            result.error = spoken_error;
            return result;
        }
        result.answer = evidence.empty() ? result.answer : evidence;
        return result;
    }
    result.answer = spoken_row.value("answer", "");
    if (result.answer.empty()) result.answer = evidence.empty() ? "(empty)" : evidence;
    result.decode_path += bind ? " -> phrase" : " -> talk";
    return result;
}

bool download_model(const std::string& repo_id, DownloadStatus status, void* user, std::wstring& error) {
    auto report = [&](const std::wstring& text, bool force) {
        static ULONGLONG last = 0;
        ULONGLONG now = GetTickCount64();
        if (!force && now - last < 200) return;
        last = now;
        if (status) status(text, user);
    };
    std::wstring dest = model_directory(repo_id);
    CreateDirectoryW(models_root().c_str(), nullptr);
    CreateDirectoryW(dest.c_str(), nullptr);
    if (weights_present(dest)) return true;

    HttpSession http;
    if (!http.session) {
        error = L"WinHTTP";
        return false;
    }
    std::wstring tree = L"/api/models/" + utf8_to_wide(repo_id) + L"/tree/main?recursive=true";
    GetRequest request = open_get(http.session, tree);
    if (!request.request ||
        !WinHttpSendRequest(request.request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
        !WinHttpReceiveResponse(request.request, nullptr)) {
        error = L"无法读取模型文件列表。";
        return false;
    }
    DWORD status_code = 0;
    query_status(request.request, status_code);
    std::string listing;
    for (;;) {
        DWORD available = 0;
        if (!WinHttpQueryDataAvailable(request.request, &available)) break;
        if (available == 0) break;
        std::string chunk(available, '\0');
        DWORD read = 0;
        if (!WinHttpReadData(request.request, chunk.data(), available, &read)) break;
        chunk.resize(read);
        listing += chunk;
    }
    if (status_code >= 400 || listing.empty()) {
        error = L"模型列表请求失败。";
        return false;
    }
    nlohmann::json files;
    try {
        files = nlohmann::json::parse(listing);
    } catch (const std::exception&) {
        error = L"模型列表无法解析。";
        return false;
    }
    if (!files.is_array()) {
        error = L"模型列表无法解析。";
        return false;
    }
    for (const auto& item : files) {
        if (!item.is_object() || item.value("type", "") != "file") continue;
        std::string path = item.value("path", "");
        if (!wanted_file(path)) continue;
        std::wstring target = dest + L"\\" + utf8_to_wide(path);
        for (auto& ch : target) {
            if (ch == L'/') ch = L'\\';
        }
        ensure_parent(target);
        report(utf8_to_wide(path), true);
        std::wstring remote = L"/" + utf8_to_wide(repo_id) + L"/resolve/main/" + url_encode(path);
        GetRequest file_request = open_get(http.session, remote);
        if (!file_request.request ||
            !WinHttpSendRequest(file_request.request, WINHTTP_NO_ADDITIONAL_HEADERS, 0, WINHTTP_NO_REQUEST_DATA, 0, 0, 0) ||
            !WinHttpReceiveResponse(file_request.request, nullptr)) {
            error = L"下载失败： " + utf8_to_wide(path);
            return false;
        }
        DWORD file_status = 0;
        query_status(file_request.request, file_status);
        if (file_status >= 400) {
            error = L"下载失败： " + utf8_to_wide(path);
            return false;
        }
        std::wstring partial = target + L".partial";
        HANDLE file = CreateFileW(partial.c_str(), GENERIC_WRITE, 0, nullptr, CREATE_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        if (file == INVALID_HANDLE_VALUE) {
            error = L"无法写入 " + target;
            return false;
        }
        ULONGLONG got = 0;
        for (;;) {
            DWORD available = 0;
            if (!WinHttpQueryDataAvailable(file_request.request, &available)) break;
            if (available == 0) break;
            std::vector<char> chunk(available);
            DWORD read = 0;
            if (!WinHttpReadData(file_request.request, chunk.data(), available, &read) || read == 0) break;
            DWORD wrote = 0;
            WriteFile(file, chunk.data(), read, &wrote, nullptr);
            got += wrote;
            report(utf8_to_wide(path) + L"  " + std::to_wstring(got / (1024 * 1024)) + L" MB", false);
        }
        CloseHandle(file);
        if (got == 0 || !MoveFileExW(partial.c_str(), target.c_str(), MOVEFILE_REPLACE_EXISTING)) {
            DeleteFileW(partial.c_str());
            error = L"下载失败： " + utf8_to_wide(path);
            return false;
        }
    }
    if (!weights_present(dest)) {
        error = L"下载结束，但没有 model.safetensors。";
        return false;
    }
    report(L"", true);
    return true;
}

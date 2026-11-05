#pragma once

#include <QString>

// Offline text-to-speech over WinRT SpeechSynthesis (Windows voices, incl.
// OneCore zh-CN/en-US voices that ship with Chinese Windows installs).
// Picks an en voice for English text and a zh voice otherwise when present,
// then plays through a WinRT MediaPlayer. No downloads, works on any PC.
class Tts {
public:
    Tts();
    ~Tts();

    bool available() const;
    // english: force the English voice; slow: read at a learning pace.
    bool speak(const QString& text, bool english, bool slow);
    void stop();

private:
    struct Impl;
    Impl* impl_ = nullptr;
};

#include "tts.h"

#include <condition_variable>
#include <mutex>

#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Media.Core.h>
#include <winrt/Windows.Media.Playback.h>
#include <winrt/Windows.Media.SpeechSynthesis.h>
#include <winrt/Windows.Storage.Streams.h>
#include <winrt/base.h>

namespace {

template <typename T>
auto waitOperation(winrt::Windows::Foundation::IAsyncOperation<T> operation) {
    std::mutex mutex;
    std::condition_variable ready;
    bool done = false;
    operation.Completed([&](auto const&, winrt::Windows::Foundation::AsyncStatus) {
        std::lock_guard lock(mutex);
        done = true;
        ready.notify_all();
    });
    std::unique_lock lock(mutex);
    ready.wait(lock, [&] { return done; });
    return operation.GetResults();
}

}  // namespace

struct Tts::Impl {
    winrt::Windows::Media::SpeechSynthesis::SpeechSynthesizer synth{nullptr};
    winrt::Windows::Media::Playback::MediaPlayer player{nullptr};
    bool ok = false;

    Impl() {
        try {
            winrt::init_apartment(winrt::apartment_type::single_threaded);
        } catch (const winrt::hresult_error&) {
        }
        try {
            synth = winrt::Windows::Media::SpeechSynthesis::SpeechSynthesizer();
            player = winrt::Windows::Media::Playback::MediaPlayer();
            ok = true;
        } catch (const winrt::hresult_error&) {
            ok = false;
        }
    }
};

Tts::Tts() : impl_(new Impl()) {}

Tts::~Tts() {
    stop();
    delete impl_;
}

bool Tts::available() const { return impl_ && impl_->ok; }

bool Tts::speak(const QString& text, bool english, bool slow) {
    if (!available()) return false;
    const QString body = text.trimmed();
    if (body.isEmpty()) return false;
    using namespace winrt::Windows::Media::SpeechSynthesis;
    try {
        VoiceInformation chosen{nullptr};
        VoiceInformation fallback{nullptr};
        for (const auto& voice : SpeechSynthesizer::AllVoices()) {
            if (!fallback) fallback = voice;
            const std::wstring lang = voice.Language().c_str();
            const bool match = english ? (lang.rfind(L"en", 0) == 0) : (lang.rfind(L"zh", 0) == 0);
            if (match) {
                chosen = voice;
                break;
            }
        }
        if (!chosen) chosen = fallback;
        if (chosen) impl_->synth.Voice(chosen);
        impl_->synth.Options().SpeakingRate(slow ? 0.65 : 1.0);
        auto stream = waitOperation(impl_->synth.SynthesizeTextToStreamAsync(
            winrt::hstring(body.toStdWString())));
        if (!stream) return false;
        impl_->player.Source(winrt::Windows::Media::Core::MediaSource::CreateFromStream(
            stream, stream.ContentType()));
        impl_->player.Play();
        return true;
    } catch (const winrt::hresult_error&) {
        return false;
    }
}

void Tts::stop() {
    if (!available()) return;
    try {
        impl_->player.Pause();
        impl_->player.PlaybackSession().Position(winrt::Windows::Foundation::TimeSpan{0});
    } catch (const winrt::hresult_error&) {
    }
}

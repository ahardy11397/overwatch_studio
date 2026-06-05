#include "WindowsProcessCapture.h"
#include <wrl/client.h>
#include <wrl/implements.h>
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <mmdeviceapi.h>
#include <initguid.h>
#include <chrono>
#include <cmath>
#include <cstring>

#ifndef SPEAKER_FRONT_LEFT
#define SPEAKER_FRONT_LEFT            0x1
#endif
#ifndef SPEAKER_FRONT_RIGHT
#define SPEAKER_FRONT_RIGHT           0x2
#endif
#define KSAUDIO_SPEAKER_STEREO        (SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT)

#ifndef KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
struct __declspec(uuid("00000003-0000-0010-8000-00aa00389b71")) KSDATAFORMAT_SUBTYPE_IEEE_FLOAT_STRUCT;
#define KSDATAFORMAT_SUBTYPE_IEEE_FLOAT __uuidof(KSDATAFORMAT_SUBTYPE_IEEE_FLOAT_STRUCT)
#endif

#ifndef KSDATAFORMAT_SUBTYPE_PCM
struct __declspec(uuid("00000001-0000-0010-8000-00aa00389b71")) KSDATAFORMAT_SUBTYPE_PCM_STRUCT;
#define KSDATAFORMAT_SUBTYPE_PCM __uuidof(KSDATAFORMAT_SUBTYPE_PCM_STRUCT)
#endif

#ifndef VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK
#define VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK L"VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK"
#endif

class AudioInterfaceCompletionHandler : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
    IActivateAudioInterfaceCompletionHandler>
{
public:
    AudioInterfaceCompletionHandler(HANDLE event) : m_event(event), m_hr(E_FAIL) {}

    STDMETHODIMP ActivateCompleted(IActivateAudioInterfaceAsyncOperation* activateOperation) override
    {
        Microsoft::WRL::ComPtr<IUnknown> activatedInterface;
        HRESULT hrActivateResult = E_FAIL;
        m_hr = activateOperation->GetActivateResult(&hrActivateResult, &activatedInterface);
        if (SUCCEEDED(m_hr) && SUCCEEDED(hrActivateResult))
        {
            m_hr = activatedInterface.As(&m_audioClient);
        }
        else if (SUCCEEDED(m_hr))
        {
            m_hr = hrActivateResult;
        }
        SetEvent(m_event);
        return S_OK;
    }

    HRESULT GetResult(Microsoft::WRL::ComPtr<IAudioClient>& audioClient)
    {
        audioClient = m_audioClient;
        return m_hr;
    }

private:
    HANDLE m_event;
    HRESULT m_hr;
    Microsoft::WRL::ComPtr<IAudioClient> m_audioClient;
};

bool WindowsProcessCapture::start(DWORD processId, SPSCQueue<float>& outputQueue) noexcept {
    if (running.load()) {
        return false;
    }
    fallbackActive.store(false, std::memory_order_relaxed);
    running.store(true);
    captureThread = std::thread(&WindowsProcessCapture::captureLoop, this, processId, std::ref(outputQueue));
    return true;
}

void WindowsProcessCapture::stop() noexcept {
    if (running.load()) {
        running.store(false);
        if (captureThread.joinable()) {
            captureThread.join();
        }
    }
}

void WindowsProcessCapture::captureLoop(DWORD pid, SPSCQueue<float>& queue) noexcept {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);

    Microsoft::WRL::ComPtr<IAudioClient> audioClient;
    Microsoft::WRL::ComPtr<IAudioCaptureClient> captureClient;
    WAVEFORMATEXTENSIBLE wfx = {};
    WAVEFORMATEX* mixFormat = nullptr;
    bool formatAllocated = false;
    bool initialized = false;

    // 1. Attempt process-specific loopback (only if target PID is non-zero)
    if (pid != 0) {
        HANDLE hEvent = CreateEvent(nullptr, FALSE, FALSE, nullptr);
        if (hEvent) {
            auto completionHandler = Microsoft::WRL::Make<AudioInterfaceCompletionHandler>(hEvent);

            AUDIOCLIENT_ACTIVATION_PARAMS activationParams = {};
            activationParams.ActivationType = AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
            activationParams.ProcessLoopbackParams.TargetProcessId = pid;
            activationParams.ProcessLoopbackParams.ProcessLoopbackMode = PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;

            PROPVARIANT propVar = {};
            PropVariantInit(&propVar);
            propVar.vt = VT_BLOB;
            propVar.blob.cbSize = sizeof(activationParams);
            propVar.blob.pBlobData = reinterpret_cast<BYTE*>(&activationParams);

            Microsoft::WRL::ComPtr<IActivateAudioInterfaceAsyncOperation> asyncOp;
            HRESULT hr = ActivateAudioInterfaceAsync(
                VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK,
                __uuidof(IAudioClient),
                &propVar,
                completionHandler.Get(),
                &asyncOp
            );

            if (SUCCEEDED(hr)) {
                // Wait for the interface activation to complete or until thread stops
                while (running.load(std::memory_order_relaxed)) {
                    DWORD waitResult = WaitForSingleObject(hEvent, 10);
                    if (waitResult == WAIT_OBJECT_0) {
                        break;
                    }
                }

                hr = completionHandler->GetResult(audioClient);
                if (SUCCEEDED(hr) && audioClient) {
                    // For process loopback, GetMixFormat typically returns E_NOTIMPL.
                    // We define a standard WAVEFORMATEXTENSIBLE stereo 32-bit float 48kHz format.
                    wfx = {};
                    wfx.Format.cbSize = sizeof(WAVEFORMATEXTENSIBLE) - sizeof(WAVEFORMATEX);
                    wfx.Format.wFormatTag = WAVE_FORMAT_EXTENSIBLE;
                    wfx.Format.nChannels = 2;
                    wfx.Format.nSamplesPerSec = 48000;
                    wfx.Format.wBitsPerSample = 32;
                    wfx.Format.nBlockAlign = (wfx.Format.nChannels * wfx.Format.wBitsPerSample) / 8;
                    wfx.Format.nAvgBytesPerSec = wfx.Format.nSamplesPerSec * wfx.Format.nBlockAlign;
                    wfx.Samples.wValidBitsPerSample = 32;
                    wfx.dwChannelMask = SPEAKER_FRONT_LEFT | SPEAKER_FRONT_RIGHT;
                    wfx.SubFormat = KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
                    mixFormat = reinterpret_cast<WAVEFORMATEX*>(&wfx);

                    hr = audioClient->Initialize(
                        AUDCLNT_SHAREMODE_SHARED,
                        0,
                        1000000, // 100ms
                        0,
                        mixFormat,
                        nullptr
                    );
                    if (SUCCEEDED(hr)) {
                        hr = audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);
                        if (SUCCEEDED(hr)) {
                            initialized = true;
                        }
                    }
                }
            }
            CloseHandle(hEvent);
        }
    }

    // 2. Fall back to system-wide loopback capture if process-specific loopback failed or target PID is 0
    if (!initialized) {
        if (audioClient) {
            audioClient.Reset();
        }
        if (captureClient) {
            captureClient.Reset();
        }

        Microsoft::WRL::ComPtr<IMMDeviceEnumerator> enumerator;
        HRESULT hr = CoCreateInstance(
            __uuidof(MMDeviceEnumerator),
            nullptr,
            CLSCTX_ALL,
            __uuidof(IMMDeviceEnumerator),
            (void**)&enumerator
        );

        Microsoft::WRL::ComPtr<IMMDevice> device;
        if (SUCCEEDED(hr)) {
            hr = enumerator->GetDefaultAudioEndpoint(eRender, eConsole, &device);
        }

        if (SUCCEEDED(hr)) {
            hr = device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&audioClient);
        }

        if (SUCCEEDED(hr)) {
            hr = audioClient->GetMixFormat(&mixFormat);
            if (SUCCEEDED(hr) && mixFormat) {
                formatAllocated = true;

                hr = audioClient->Initialize(
                    AUDCLNT_SHAREMODE_SHARED,
                    AUDCLNT_STREAMFLAGS_LOOPBACK,
                    1000000, // 100ms
                    0,
                    mixFormat,
                    nullptr
                );
                if (SUCCEEDED(hr)) {
                    hr = audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&captureClient);
                    if (SUCCEEDED(hr)) {
                        initialized = true;
                    }
                }
            }
        }
    }

    bool useMock = !initialized;
    bool isFloat = false;
    bool isPCM = false;
    int channels = 2;

    if (initialized && mixFormat) {
        isFloat = (mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT);
        isPCM = (mixFormat->wFormatTag == WAVE_FORMAT_PCM);
        if (mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
            WAVEFORMATEXTENSIBLE* pExt = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(mixFormat);
            if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
                isFloat = true;
            } else if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
                isPCM = true;
            }
        }
        channels = mixFormat->nChannels;

        HRESULT hrStart = audioClient->Start();
        if (FAILED(hrStart)) {
            useMock = true;
        } else {
            while (running.load(std::memory_order_relaxed)) {
                UINT32 packetLength = 0;
                HRESULT hr = captureClient->GetNextPacketSize(&packetLength);
                if (FAILED(hr)) {
                    useMock = true;
                    break;
                }
                if (packetLength > 0) {
                    BYTE* data = nullptr;
                    UINT32 framesAvailable = 0;
                    DWORD flags = 0;
                    hr = captureClient->GetBuffer(&data, &framesAvailable, &flags, nullptr, nullptr);
                    if (SUCCEEDED(hr) && data) {
                        for (UINT32 f = 0; f < framesAvailable; ++f) {
                            float val = 0.0f;
                            if (isFloat) {
                                if (mixFormat->wBitsPerSample == 32) {
                                    val = reinterpret_cast<float*>(data)[f * channels];
                                } else if (mixFormat->wBitsPerSample == 64) {
                                    val = static_cast<float>(reinterpret_cast<double*>(data)[f * channels]);
                                }
                            } else if (isPCM) {
                                if (mixFormat->wBitsPerSample == 16) {
                                    val = static_cast<float>(reinterpret_cast<short*>(data)[f * channels]) / 32768.0f;
                                } else if (mixFormat->wBitsPerSample == 24) {
                                    size_t sampleOffset = (f * channels) * 3;
                                    int32_t valInt = (data[sampleOffset]) |
                                                     (data[sampleOffset + 1] << 8) |
                                                     (data[sampleOffset + 2] << 16);
                                    if (valInt & 0x800000) {
                                        valInt |= 0xFF000000;
                                    }
                                    val = static_cast<float>(valInt) / 8388608.0f;
                                } else if (mixFormat->wBitsPerSample == 32) {
                                    val = static_cast<float>(reinterpret_cast<int32_t*>(data)[f * channels]) / 2147483648.0f;
                                }
                            }
                            queue.push(val);
                        }
                        captureClient->ReleaseBuffer(framesAvailable);
                    }
                } else {
                    std::this_thread::sleep_for(std::chrono::milliseconds(5));
                }
            }
            audioClient->Stop();
        }
    }

    if (formatAllocated && mixFormat) {
        CoTaskMemFree(mixFormat);
        mixFormat = nullptr;
    }

    // 3. Fall back to mock loopback generator if capture failed to initialize or stopped prematurely
    fallbackActive.store(useMock, std::memory_order_relaxed);
    if (useMock && running.load(std::memory_order_relaxed)) {
        float phase = 0.0f;
        const float sampleRate = 48000.0f;
        const float frequency = 440.0f;
        const float phaseIncrement = 2.0f * 3.14159265f * frequency / sampleRate;

        const auto interval = std::chrono::milliseconds(10);
        const size_t samplesPerInterval = 480; // 10ms at 48kHz

        while (running.load(std::memory_order_relaxed)) {
            auto startTime = std::chrono::steady_clock::now();

            for (size_t i = 0; i < samplesPerInterval; ++i) {
                float sample = 0.1f * std::sin(phase);
                phase += phaseIncrement;
                if (phase >= 2.0f * 3.14159265f) {
                    phase -= 2.0f * 3.14159265f;
                }
                queue.push(sample);
            }

            auto endTime = std::chrono::steady_clock::now();
            auto elapsed = std::chrono::duration_cast<std::chrono::milliseconds>(endTime - startTime);
            if (elapsed < interval) {
                std::this_thread::sleep_for(interval - elapsed);
            }
        }
    }

    audioClient.Reset();
    captureClient.Reset();
    CoUninitialize();
}

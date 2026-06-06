#include "WASAPIDeviceWorker.h"
#include <functiondiscoverykeys_devpkey.h>
#include <algorithm>
#include <cmath>
#include <mutex>
#include <iostream>

#ifndef KSDATAFORMAT_SUBTYPE_IEEE_FLOAT
struct __declspec(uuid("00000003-0000-0010-8000-00aa00389b71")) KSDATAFORMAT_SUBTYPE_IEEE_FLOAT_STRUCT;
#define KSDATAFORMAT_SUBTYPE_IEEE_FLOAT __uuidof(KSDATAFORMAT_SUBTYPE_IEEE_FLOAT_STRUCT)
#endif

#ifndef KSDATAFORMAT_SUBTYPE_PCM
struct __declspec(uuid("00000001-0000-0010-8000-00aa00389b71")) KSDATAFORMAT_SUBTYPE_PCM_STRUCT;
#define KSDATAFORMAT_SUBTYPE_PCM __uuidof(KSDATAFORMAT_SUBTYPE_PCM_STRUCT)
#endif

WASAPIDeviceWorker::WASAPIDeviceWorker(IMMDevice* device, Mode mode) noexcept
    : m_device(device), m_mode(mode) {
    if (m_device) {
        m_device->AddRef();
        IPropertyStore* propStore = nullptr;
        if (SUCCEEDED(m_device->OpenPropertyStore(STGM_READ, &propStore))) {
            PROPVARIANT varName;
            PropVariantInit(&varName);
            if (SUCCEEDED(propStore->GetValue(PKEY_Device_FriendlyName, &varName))) {
                m_deviceName = varName.pwszVal ? varName.pwszVal : L"Unknown Device";
                PropVariantClear(&varName);
            }
            propStore->Release();
        }
    }
    // Pre-allocate dynamic ring buffers and read positions for 2 default channels
    // to support mock buffer test operations without calling start()
    m_channelRingBuffers.resize(2);
    for (int c = 0; c < 2; ++c) {
        m_channelRingBuffers[c].resize(m_ringBufferSize, 0.0f);
    }
    m_ringReadPos.assign(2, 0);
    m_ringWritePos = 0;
}

int WASAPIDeviceWorker::getChannelCount() const noexcept {
    return m_mixFormat ? static_cast<int>(m_mixFormat->nChannels) : 0;
}

WASAPIDeviceWorker::~WASAPIDeviceWorker() {
    stop();
    if (m_mixFormat) CoTaskMemFree(m_mixFormat);
    if (m_captureClient) m_captureClient->Release();
    if (m_renderClient) m_renderClient->Release();
    if (m_audioClient) m_audioClient->Release();
    if (m_device) m_device->Release();
}

bool WASAPIDeviceWorker::start() noexcept {
    if (m_running.load()) return true;
    if (!m_device) return false;

    HRESULT hr = m_device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr, (void**)&m_audioClient);
    if (FAILED(hr)) return false;

    hr = m_audioClient->GetMixFormat(&m_mixFormat);
    if (FAILED(hr)) return false;

    REFERENCE_TIME duration = 100000; // 10ms
    DWORD flags = 0;

    hr = m_audioClient->Initialize(AUDCLNT_SHAREMODE_SHARED, flags, duration, 0, m_mixFormat, nullptr);
    if (FAILED(hr)) return false;

    int channels = m_mixFormat->nChannels;
    m_channelRingBuffers.resize(channels);
    for (int c = 0; c < channels; ++c) {
        m_channelRingBuffers[c].resize(m_ringBufferSize, 0.0f);
    }
    m_ringReadPos.assign(channels, 0);
    m_ringWritePos = 0;

    hr = m_audioClient->GetBufferSize(&m_bufferFrameCount);
    if (FAILED(hr)) return false;

    if (m_mode == Mode::Capture) {
        hr = m_audioClient->GetService(__uuidof(IAudioCaptureClient), (void**)&m_captureClient);
    } else {
        hr = m_audioClient->GetService(__uuidof(IAudioRenderClient), (void**)&m_renderClient);
    }
    if (FAILED(hr)) return false;

    m_running.store(true);
    m_workerThread = std::thread(&WASAPIDeviceWorker::runLoop, this);
    return true;
}

void WASAPIDeviceWorker::stop() noexcept {
    if (m_running.load()) {
        m_running.store(false);
        if (m_workerThread.joinable()) {
            m_workerThread.join();
        }
    }
}

void WASAPIDeviceWorker::runLoop() noexcept {
    CoInitializeEx(nullptr, COINIT_MULTITHREADED);
    if (m_audioClient) m_audioClient->Start();

    while (m_running.load(std::memory_order_relaxed)) {
        if (m_mode == Mode::Capture && m_captureClient) {
            UINT32 packetLength = 0;
            HRESULT hr = m_captureClient->GetNextPacketSize(&packetLength);
            if (SUCCEEDED(hr) && packetLength > 0) {
                BYTE* data = nullptr;
                UINT32 framesAvailable = 0;
                DWORD flags = 0;
                hr = m_captureClient->GetBuffer(&data, &framesAvailable, &flags, nullptr, nullptr);
                if (SUCCEEDED(hr) && data) {
                    std::lock_guard<std::mutex> lock(m_ringMutex);
                    int channels = m_mixFormat->nChannels;

                    bool isFloat = (m_mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT);
                    bool isPCM = (m_mixFormat->wFormatTag == WAVE_FORMAT_PCM);
                    if (m_mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
                        WAVEFORMATEXTENSIBLE* pExt = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(m_mixFormat);
                        if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
                            isFloat = true;
                        } else if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
                            isPCM = true;
                        }
                    }

                    for (UINT32 f = 0; f < framesAvailable; ++f) {
                        for (int c = 0; c < channels; ++c) {
                            float val = 0.0f;
                            if (isFloat) {
                                if (m_mixFormat->wBitsPerSample == 32) {
                                    val = reinterpret_cast<float*>(data)[f * channels + c];
                                } else if (m_mixFormat->wBitsPerSample == 64) {
                                    val = static_cast<float>(reinterpret_cast<double*>(data)[f * channels + c]);
                                }
                            } else { // PCM
                                if (m_mixFormat->wBitsPerSample == 16) {
                                    val = static_cast<float>(reinterpret_cast<short*>(data)[f * channels + c]) / 32768.0f;
                                } else if (m_mixFormat->wBitsPerSample == 24) {
                                    size_t sampleOffset = (f * channels + c) * 3;
                                    int32_t valInt = (data[sampleOffset]) |
                                                     (data[sampleOffset + 1] << 8) |
                                                     (data[sampleOffset + 2] << 16);
                                    if (valInt & 0x800000) {
                                        valInt |= 0xFF000000;
                                    }
                                    val = static_cast<float>(valInt) / 8388608.0f;
                                } else if (m_mixFormat->wBitsPerSample == 32) {
                                    val = static_cast<float>(reinterpret_cast<int32_t*>(data)[f * channels + c]) / 2147483648.0f;
                                }
                            }
                            m_channelRingBuffers[c][m_ringWritePos] = val;
                        }
                        m_ringWritePos = (m_ringWritePos + 1) % m_ringBufferSize;
                    }
                    m_captureClient->ReleaseBuffer(framesAvailable);
                }
            }
        } else if (m_mode == Mode::Render && m_renderClient) {
            UINT32 padding = 0;
            HRESULT hr = m_audioClient->GetCurrentPadding(&padding);
            if (SUCCEEDED(hr)) {
                UINT32 framesToWrite = m_bufferFrameCount - padding;
                if (framesToWrite > 0) {
                    BYTE* data = nullptr;
                    hr = m_renderClient->GetBuffer(framesToWrite, &data);
                    if (SUCCEEDED(hr) && data) {
                        std::lock_guard<std::mutex> lock(m_ringMutex);
                        
                        int channels = m_mixFormat->nChannels;
                        if (m_ringReadPos.size() != static_cast<size_t>(channels)) {
                            m_ringReadPos.assign(channels, 0);
                        }

                        size_t buffered = (m_ringWritePos >= m_ringReadPos[0]) ? 
                                          (m_ringWritePos - m_ringReadPos[0]) : 
                                          (m_ringBufferSize - m_ringReadPos[0] + m_ringWritePos);
                                          
                        size_t maxAllowed = framesToWrite + 512;
                        if (buffered > maxAllowed) {
                            size_t targetSamples = framesToWrite + 256;
                            m_ringReadPos[0] = (m_ringWritePos + m_ringBufferSize - targetSamples) % m_ringBufferSize;
                        }

                        bool isFloat = (m_mixFormat->wFormatTag == WAVE_FORMAT_IEEE_FLOAT);
                        bool isPCM = (m_mixFormat->wFormatTag == WAVE_FORMAT_PCM);
                        if (m_mixFormat->wFormatTag == WAVE_FORMAT_EXTENSIBLE) {
                            WAVEFORMATEXTENSIBLE* pExt = reinterpret_cast<WAVEFORMATEXTENSIBLE*>(m_mixFormat);
                            if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_IEEE_FLOAT) {
                                  isFloat = true;
                            } else if (pExt->SubFormat == KSDATAFORMAT_SUBTYPE_PCM) {
                                  isPCM = true;
                            }
                        }

                        for (UINT32 f = 0; f < framesToWrite; ++f) {
                            float val = m_channelRingBuffers[0][m_ringReadPos[0]];
                            m_channelRingBuffers[0][m_ringReadPos[0]] = 0.0f; // Clear
                            m_ringReadPos[0] = (m_ringReadPos[0] + 1) % m_ringBufferSize;

                            for (int c = 0; c < channels; ++c) {
                                if (isFloat) {
                                    if (m_mixFormat->wBitsPerSample == 32) {
                                        reinterpret_cast<float*>(data)[f * channels + c] = val;
                                    } else if (m_mixFormat->wBitsPerSample == 64) {
                                        reinterpret_cast<double*>(data)[f * channels + c] = static_cast<double>(val);
                                    }
                                } else { // PCM
                                    if (m_mixFormat->wBitsPerSample == 16) {
                                        reinterpret_cast<short*>(data)[f * channels + c] =
                                            static_cast<short>(std::clamp(val, -1.0f, 1.0f) * 32767.0f);
                                    } else if (m_mixFormat->wBitsPerSample == 24) {
                                        size_t sampleOffset = (f * channels + c) * 3;
                                        int32_t valInt = static_cast<int32_t>(std::clamp(val, -1.0f, 1.0f) * 8388607.0f);
                                        data[sampleOffset] = static_cast<BYTE>(valInt & 0xFF);
                                        data[sampleOffset + 1] = static_cast<BYTE>((valInt >> 8) & 0xFF);
                                        data[sampleOffset + 2] = static_cast<BYTE>((valInt >> 16) & 0xFF);
                                    } else if (m_mixFormat->wBitsPerSample == 32) {
                                        reinterpret_cast<int32_t*>(data)[f * channels + c] =
                                            static_cast<int32_t>(std::clamp(val, -1.0f, 1.0f) * 2147483647.0f);
                                    }
                                }
                            }
                        }
                        m_renderClient->ReleaseBuffer(framesToWrite, 0);
                    }
                }
            }
        }
        std::this_thread::sleep_for(std::chrono::milliseconds(5));
    }

    if (m_audioClient) m_audioClient->Stop();
    CoUninitialize();
}

size_t WASAPIDeviceWorker::getBufferedSampleCount() const noexcept {
    std::lock_guard<std::mutex> lock(m_ringMutex);
    if (m_ringReadPos.empty()) return 0;
    size_t readPos = m_ringReadPos[0];
    return (m_ringWritePos >= readPos) ? 
           (m_ringWritePos - readPos) : 
           (m_ringBufferSize - readPos + m_ringWritePos);
}

void WASAPIDeviceWorker::readCapturedSamples(int deviceChannelIdx, float* destBuffer, size_t numSamples) noexcept {
    std::lock_guard<std::mutex> lock(m_ringMutex);
    
    if (deviceChannelIdx < 0 || deviceChannelIdx >= static_cast<int>(m_channelRingBuffers.size())) {
        std::fill_n(destBuffer, numSamples, 0.0f);
        return;
    }
    
    size_t readPos = m_ringReadPos[deviceChannelIdx];
    size_t buffered = (m_ringWritePos >= readPos) ? 
                      (m_ringWritePos - readPos) : 
                      (m_ringBufferSize - readPos + m_ringWritePos);
                      
    if (buffered > 512) {
        readPos = (m_ringWritePos + m_ringBufferSize - 512) % m_ringBufferSize;
    }

    const auto& chanBuf = m_channelRingBuffers[deviceChannelIdx];
    for (size_t i = 0; i < numSamples; ++i) {
        if (readPos != m_ringWritePos) {
            destBuffer[i] = chanBuf[readPos];
            readPos = (readPos + 1) % m_ringBufferSize;
        } else {
            destBuffer[i] = 0.0f; // Silence fallback
        }
    }
    m_ringReadPos[deviceChannelIdx] = readPos;
}

void WASAPIDeviceWorker::readCapturedSamples(float* destBuffer, size_t numSamples) noexcept {
    readCapturedSamples(0, destBuffer, numSamples);
}

void WASAPIDeviceWorker::writeRenderSamples(const float* srcBuffer, size_t numSamples) noexcept {
    std::lock_guard<std::mutex> lock(m_ringMutex);
    if (m_channelRingBuffers.empty() || m_channelRingBuffers[0].empty()) return;
    for (size_t i = 0; i < numSamples; ++i) {
        m_channelRingBuffers[0][m_ringWritePos] = srcBuffer[i];
        m_ringWritePos = (m_ringWritePos + 1) % m_ringBufferSize;
    }
}

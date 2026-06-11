#pragma once
#include <cstdint>

enum class TapPoint : uint8_t {
    PreEQ,
    PreFader,
    PostFader
};

enum class AudioSourceType : uint8_t {
    None = 0,
    Hardware = 1,
    Generator = 2,
    AppCapture = 3,
    Media = 4
};

struct AudioSourcePatch {
    AudioSourceType type{AudioSourceType::None};
    uint32_t index{0}; // Hardware input port (0-15), generator type (0=Sine, 1=Pink), or capture index
};

struct OutputPatch {
    bool active{false};
    uint32_t busIdx{0}; // Summing bus index (0-7): 0=MST L, 1=MST R, 2=AUX 1, 3=AUX 2, 4=AUX 3, 5=AUX 4, 6=REC L, 7=REC R
};

enum class RoutingCommandType : uint8_t {
    SetInputPatch,
    SetRoute,
    UnpatchRoute,
    SetOutputPatch,
    SetDCAMapping,
    SetDCAVolume,
    SetDCAMute,
    SetChannelVolume,
    SetChannelMute
};

struct RoutingCommand {
    RoutingCommandType type{RoutingCommandType::SetRoute};
    uint32_t channelIdx{0}; // Console Channel (0-23) or Output Port (0-7) or DCA Index (0-7)
    uint32_t targetIdx{0};  // Source/Target index (e.g., HW input index, generator index, bus index)
    float gain{0.0f};       // Gain value / DCA fader volume
    uint32_t flag{0};       // TapPoint (0=PreEQ, 1=PreFader, 2=PostFader), or DCA mask, or mute bool
};

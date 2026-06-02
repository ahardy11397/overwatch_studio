#pragma once

#ifndef REALTIME_SAFE
#if defined(__clang__)
#define REALTIME_SAFE [[clang::nonblocking]]
#else
#define REALTIME_SAFE
#endif
#endif

#include <array>
#include <atomic>
#include <span>
#include <algorithm>
#include <cstddef>
#include <cstdint>
#include "RoutingPatchMap.h"

struct alignas(64) RouteNode {
    uint32_t sourceId{0};
    uint32_t destId{0};
    float gain{0.0f}; // Linear gain coefficient
    TapPoint tap{TapPoint::PostFader};
};

/**
 * @class SparseRoutingMatrix
 * @brief Zero-allocation sparse sum matrix processing routing channels efficiently by skipping empty cross-points.
 */
class SparseRoutingMatrix {
public:
    static constexpr size_t MaxRoutes = 256;

    SparseRoutingMatrix() noexcept {
        activeRoutes.fill(RouteNode{});
        activeRouteCount.store(0, std::memory_order_release);
    }

    /**
     * @brief Set or update a routing cross-point node.
     */
    void setRoute(uint32_t src, uint32_t dest, float linearGain, TapPoint tapType) noexcept {
        size_t count = activeRouteCount.load(std::memory_order_acquire);
        
        // Check if route already exists and update it
        for (size_t r = 0; r < count; ++r) {
            if (activeRoutes[r].sourceId == src && activeRoutes[r].destId == dest) {
                activeRoutes[r].gain = linearGain;
                activeRoutes[r].tap = tapType;
                return;
            }
        }

        // Add a new route node if we have capacity
        if (count < MaxRoutes) {
            activeRoutes[count] = RouteNode{ src, dest, linearGain, tapType };
            activeRouteCount.store(count + 1, std::memory_order_release);
        }
    }

    /**
     * @brief Clear all routing nodes instantly.
     */
    void clear() noexcept {
        activeRouteCount.store(0, std::memory_order_release);
    }

    /**
     * @brief Process and sum the inputs onto the outputs using the routing nodes.
     */
    void process(std::span<const float*> inputs, std::span<float*> outputs, size_t numSamples) noexcept REALTIME_SAFE {
        size_t count = activeRouteCount.load(std::memory_order_acquire);
        for (size_t r = 0; r < count; ++r) {
            const auto& route = activeRoutes[r];
            if (route.gain == 0.0f) continue;
            
            const float* src = inputs[route.sourceId];
            float* dest = outputs[route.destId];
            float g = route.gain;
            
            for (size_t s = 0; s < numSamples; ++s) {
                dest[s] += src[s] * g;
            }
        }
    }

private:
    std::array<RouteNode, MaxRoutes> activeRoutes;
    std::atomic<size_t> activeRouteCount;
};

### The Color Palette

* **Base Surfaces (Deep Matte Charcoal):** Lowers optical fatigue in dim control rooms. Hex values range from Primary Background (`#121314`) to Surface Containers (`#1A1C1E`).
* **Core Accents (Cool Cyan-Blue):** Denotes primary channel focus, routing confirmation highlights, and active operational layers. Hex values feature Active Cyan (`#00BDD6`) and Deep Teal (`#004F58`).
* **Status Highlights (Emerald Green & Warm Amber):** Emerald Green (`#00E676`) is used for optimal metering levels and gate indicators. Warm Amber (`#FFB300`) flags gain reduction thresholds, clipping parameters, and watchdog performance warnings.

### Touch and Desktop Ergonomics

* **Expanded Touch Hitboxes:** All on-screen volume faders feature a wide, invisible touch bounding box (minimum $48\text{ px}$). Faders track movement using relative drag offsets—touching the channel strip tracks finger movement smoothly from any position without causing the volume level to snap violently to the touch point.
* **Vertical-Drag Encoder Mapping:** Rotary encoders (such as EQ frequency bands or compressor thresholds) map parameter changes to linear vertical drag motions rather than rotational movements, ensuring rapid and precise adjustments on crowded touchscreens.
* **Fluid Screen Scaling:** The interface relies on responsive layout anchors. When a small show file (e.g., 8 channels) is loaded, the channel strips expand horizontally to provide deep control surfaces. When a 24-channel file is loaded, the inte
    "osc_listener_port": 8000,
    "osc_transmit_port": 9000,
    "midi_mcu_device_name": "X-TOUCH COMPACT",
    "midi_motor_faders_enabled": true
  },
  "automation_cue_stack": {
    "total_cue_count": 3,
    "sequential_cue_chain": [
      {
        "cue_index": 1,
        "cue_label": "Pre-Show Welcome Loops",
        "transition_profile": {
          "type": "CROSSFADE",
          "duration_ms": 1000
        },
        "target_video_program_source_id": 5,
        "target_video_preview_source_id": 1,
        "audio_follows_video_mappings": [
          {
            "video_source_id": 5,
            "linked_audio_channel_id": 4,
            "transition_curve_profile": "EQUAL_POWER_BLEND",
            "fade_in_time_ms": 250,
            "fade_out_time_ms": 500
          }
        ],
        "snapshot_parameter_updates": [
          {
            "target": "audio.channel_4.fader_gain_db",
            "value": 0.0,
            "interpolation_time_ms": 1000
          },
          {
            "target": "audio.channel_1.fader_gain_db",
            "value": -80.0,
            "interpolation_time_ms": 0
          }
        ]
      }
    ]
  },
  "embedded_presentation_sync": {
    "headless_data_directory": "freeshow_data/",
    "target_sqlite_database_file": "freeshow_state.db",
    "sqlite_pragma_tuning_parameters": {
      "journal_mode": "WAL",
      "synchronous": "NORMAL",
      "cache_size_pages": -2000
    }
  }
}

```

eof

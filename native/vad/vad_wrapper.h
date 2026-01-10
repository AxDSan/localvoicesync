#ifndef VAD_WRAPPER_H
#define VAD_WRAPPER_H

#include <stdint.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct vad_context vad_context;

typedef struct {
    int sample_rate;
    int frame_size;
    float threshold;
    int min_silence_duration_ms;
    int speech_pad_ms;
} vad_config;

vad_context* vad_init(const char* model_path, vad_config config);
void vad_free(vad_context* ctx);

// Process a frame of audio. Returns probability of speech (0.0 to 1.0).
float vad_process(vad_context* ctx, const float* samples, int n_samples);

// Reset the VAD state (RNN hidden states)
void vad_reset(vad_context* ctx);

#ifdef __cplusplus
}
#endif

#endif

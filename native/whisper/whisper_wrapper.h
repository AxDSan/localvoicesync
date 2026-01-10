#ifndef WHISPER_FFI_WRAPPER_H
#define WHISPER_FFI_WRAPPER_H

#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct whisper_context whisper_context;
typedef struct whisper_full_params whisper_full_params;
typedef struct whisper_context_params whisper_context_params;

typedef enum {
    WHISPER_SAMPLING_GREEDY,
    WHISPER_SAMPLING_BEAM_SEARCH,
} whisper_sampling_strategy;

typedef struct whisper_context_params {
    bool  use_gpu;
    bool  flash_attn;
    int   gpu_device;
    bool  dtw_token_timestamps;
    int   dtw_aheads_preset;
    int   dtw_n_top;
    void* dtw_aheads;
    size_t dtw_mem_size;
} whisper_context_params;

typedef void* whisper_ahead_ffi;
typedef struct {
    size_t n_heads;
    const whisper_ahead_ffi * heads;
} whisper_aheads_ffi;

struct whisper_full_params {
    int strategy;
    int n_threads;
    int n_max_text_ctx;
    int offset_ms;
    int duration_ms;
    bool translate;
    bool no_context;
    bool no_timestamps;
    bool single_segment;
    bool print_special;
    bool print_progress;
    bool print_realtime;
    bool print_timestamps;
    bool token_timestamps;
    float thold_pt;
    float thold_ptsum;
    int max_len;
    bool split_on_word;
    int max_tokens;
    bool debug_mode;
    int audio_ctx;
    bool tdrz_enable;
    const char * suppress_regex;
    const char * initial_prompt;
    bool carry_initial_prompt;
    const int * prompt_tokens;
    int prompt_n_tokens;
    const char * language;
    bool detect_language;
    bool suppress_blank;
    bool suppress_nst;
    float temperature;
    float max_initial_ts;
    float length_penalty;
    float temperature_inc;
    float entropy_thold;
    float logprob_thold;
    float no_speech_thold;
    struct {
        int best_of;
    } greedy;
    struct {
        int beam_size;
        float patience;
    } beam_search;
    void * new_segment_callback;
    void * new_segment_callback_user_data;
    void * progress_callback;
    void * progress_callback_user_data;
    void * encoder_begin_callback;
    void * encoder_begin_callback_user_data;
    void * abort_callback;
    void * abort_callback_user_data;
    void * logits_filter_callback;
    void * logits_filter_callback_user_data;
    void ** grammar_rules;
    size_t n_grammar_rules;
    size_t i_start_rule;
    float grammar_penalty;
    bool vad;
    const char * vad_model_path;
    struct {
        float threshold;
        int min_speech_duration_ms;
        int min_silence_duration_ms;
        float max_speech_duration_s;
        int speech_pad_ms;
        float samples_overlap;
    } vad_params;
};

const char * whisper_version(void);

whisper_context * whisper_init_from_file_with_params(const char * path_model, whisper_context_params params);
whisper_context * whisper_init_from_file(const char * path_model);
void whisper_free(whisper_context * ctx);

whisper_full_params whisper_full_default_params(int strategy);
whisper_context_params whisper_context_default_params(void);

int whisper_full(whisper_context * ctx, whisper_full_params params, const float * samples, int n_samples);

int whisper_full_n_segments(whisper_context * ctx);
const char * whisper_full_get_segment_text(whisper_context * ctx, int i_segment);
int64_t whisper_full_get_segment_t0(whisper_context * ctx, int i_segment);
int64_t whisper_full_get_segment_t1(whisper_context * ctx, int i_segment);
int whisper_full_n_tokens(whisper_context * ctx, int i_segment);
const char * whisper_full_get_token_text(whisper_context * ctx, int i_segment, int i_token);
int whisper_full_lang_id(whisper_context * ctx);

int whisper_n_vocab(whisper_context * ctx);
int whisper_n_text_ctx(whisper_context * ctx);
int whisper_n_audio_ctx(whisper_context * ctx);
int whisper_is_multilingual(whisper_context * ctx);

#ifdef __cplusplus
}
#endif

#endif
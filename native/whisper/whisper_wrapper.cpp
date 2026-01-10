#include <iostream>
#include <vector>
#include <cstring>

// Rename everything in the real whisper.h to avoid collision
#define whisper_context real_whisper_context
#define whisper_state real_whisper_state
#define whisper_full_params real_whisper_full_params
#define whisper_context_params real_whisper_context_params
#define whisper_token_data real_whisper_token_data
#define whisper_model_loader real_whisper_model_loader
#define whisper_grammar_element real_whisper_grammar_element
#define whisper_gretype real_whisper_gretype
#define whisper_sampling_strategy real_whisper_sampling_strategy
#define WHISPER_SAMPLING_GREEDY REAL_WHISPER_SAMPLING_GREEDY
#define WHISPER_SAMPLING_BEAM_SEARCH REAL_WHISPER_SAMPLING_BEAM_SEARCH

#define whisper_init_from_file_with_params real_whisper_init_from_file_with_params
#define whisper_init_from_buffer_with_params real_whisper_init_from_buffer_with_params
#define whisper_init_with_params real_whisper_init_with_params
#define whisper_init_from_file_with_params_no_state real_whisper_init_from_file_with_params_no_state
#define whisper_init_from_buffer_with_params_no_state real_whisper_init_from_buffer_with_params_no_state
#define whisper_init_with_params_no_state real_whisper_init_with_params_no_state
#define whisper_init_from_file real_whisper_init_from_file
#define whisper_init_from_buffer real_whisper_init_from_buffer
#define whisper_init real_whisper_init
#define whisper_init_from_file_no_state real_whisper_init_from_file_no_state
#define whisper_init_from_buffer_no_state real_whisper_init_from_buffer_no_state
#define whisper_init_no_state real_whisper_init_no_state
#define whisper_init_state real_whisper_init_state
#define whisper_ctx_init_openvino_encoder real_whisper_ctx_init_openvino_encoder
#define whisper_free real_whisper_free
#define whisper_free_state real_whisper_free_state
#define whisper_free_params real_whisper_free_params
#define whisper_free_context_params real_whisper_free_context_params
#define whisper_pcm_to_mel real_whisper_pcm_to_mel
#define whisper_pcm_to_mel_with_state real_whisper_pcm_to_mel_with_state
#define whisper_pcm_to_mel_phase_vocoder real_whisper_pcm_to_mel_phase_vocoder
#define whisper_pcm_to_mel_phase_vocoder_with_state real_whisper_pcm_to_mel_phase_vocoder_with_state
#define whisper_set_mel real_whisper_set_mel
#define whisper_set_mel_with_state real_whisper_set_mel_with_state
#define whisper_encode real_whisper_encode
#define whisper_encode_with_state real_whisper_encode_with_state
#define whisper_decode real_whisper_decode
#define whisper_decode_with_state real_whisper_decode_with_state
#define whisper_tokenize real_whisper_tokenize
#define whisper_lang_max_id real_whisper_lang_max_id
#define whisper_lang_id real_whisper_lang_id
#define whisper_lang_str real_whisper_lang_str
#define whisper_lang_str_full real_whisper_lang_str_full
#define whisper_lang_auto_detect real_whisper_lang_auto_detect
#define whisper_lang_auto_detect_with_state real_whisper_lang_auto_detect_with_state
#define whisper_n_len real_whisper_n_len
#define whisper_n_len_from_state real_whisper_n_len_from_state
#define whisper_n_vocab real_whisper_n_vocab
#define whisper_n_text_ctx real_whisper_n_text_ctx
#define whisper_n_audio_ctx real_whisper_n_audio_ctx
#define whisper_is_multilingual real_whisper_is_multilingual
#define whisper_get_logits real_whisper_get_logits
#define whisper_get_logits_from_state real_whisper_get_logits_from_state
#define whisper_token_to_str real_whisper_token_to_str
#define whisper_model_type_readable real_whisper_model_type_readable
#define whisper_full_default_params real_whisper_full_default_params
#define whisper_context_default_params real_whisper_context_default_params
#define whisper_full real_whisper_full
#define whisper_full_with_state real_whisper_full_with_state
#define whisper_full_parallel real_whisper_full_parallel
#define whisper_full_n_segments real_whisper_full_n_segments
#define whisper_full_n_segments_from_state real_whisper_full_n_segments_from_state
#define whisper_full_lang_id real_whisper_full_lang_id
#define whisper_full_lang_id_from_state real_whisper_full_lang_id_from_state
#define whisper_full_get_segment_t0 real_whisper_full_get_segment_t0
#define whisper_full_get_segment_t0_from_state real_whisper_full_get_segment_t0_from_state
#define whisper_full_get_segment_t1 real_whisper_full_get_segment_t1
#define whisper_full_get_segment_t1_from_state real_whisper_full_get_segment_t1_from_state
#define whisper_full_get_segment_text real_whisper_full_get_segment_text
#define whisper_full_get_segment_text_from_state real_whisper_full_get_segment_text_from_state
#define whisper_full_n_tokens real_whisper_full_n_tokens
#define whisper_full_n_tokens_from_state real_whisper_full_n_tokens_from_state
#define whisper_full_get_token_text real_whisper_full_get_token_text
#define whisper_full_get_token_text_from_state real_whisper_full_get_token_text_from_state
#define whisper_full_get_token_id real_whisper_full_get_token_id
#define whisper_full_get_token_id_from_state real_whisper_full_get_token_id_from_state
#define whisper_full_get_token_data real_whisper_full_get_token_data
#define whisper_full_get_token_data_from_state real_whisper_full_get_token_data_from_state
#define whisper_full_get_token_p real_whisper_full_get_token_p
#define whisper_full_get_token_p_from_state real_whisper_full_get_token_p_from_state
#define whisper_print_system_info real_whisper_print_system_info

#include "whisper.cpp/include/whisper.h"

// Clean up the macros so we can include the wrapper header
#undef whisper_context
#undef whisper_state
#undef whisper_full_params
#undef whisper_context_params
#undef whisper_token_data
#undef whisper_model_loader
#undef whisper_grammar_element
#undef whisper_gretype
#undef whisper_sampling_strategy
#undef WHISPER_SAMPLING_GREEDY
#undef WHISPER_SAMPLING_BEAM_SEARCH

#undef whisper_init_from_file_with_params
#undef whisper_init_from_buffer_with_params
#undef whisper_init_with_params
#undef whisper_init_from_file_with_params_no_state
#undef whisper_init_from_buffer_with_params_no_state
#undef whisper_init_with_params_no_state
#undef whisper_init_from_file
#undef whisper_init_from_buffer
#undef whisper_init
#undef whisper_init_from_file_no_state
#undef whisper_init_from_buffer_no_state
#undef whisper_init_no_state
#undef whisper_init_state
#undef whisper_ctx_init_openvino_encoder
#undef whisper_free
#undef whisper_free_state
#undef whisper_free_params
#undef whisper_free_context_params
#undef whisper_pcm_to_mel
#undef whisper_pcm_to_mel_with_state
#undef whisper_pcm_to_mel_phase_vocoder
#undef whisper_pcm_to_mel_phase_vocoder_with_state
#undef whisper_set_mel
#undef whisper_set_mel_with_state
#undef whisper_encode
#undef whisper_encode_with_state
#undef whisper_decode
#undef whisper_decode_with_state
#undef whisper_tokenize
#undef whisper_lang_max_id
#undef whisper_lang_id
#undef whisper_lang_str
#undef whisper_lang_str_full
#undef whisper_lang_auto_detect
#undef whisper_lang_auto_detect_with_state
#undef whisper_n_len
#undef whisper_n_len_from_state
#undef whisper_n_vocab
#undef whisper_n_text_ctx
#undef whisper_n_audio_ctx
#undef whisper_is_multilingual
#undef whisper_get_logits
#undef whisper_get_logits_from_state
#undef whisper_token_to_str
#undef whisper_model_type_readable
#undef whisper_full_default_params
#undef whisper_context_default_params
#undef whisper_full
#undef whisper_full_with_state
#undef whisper_full_parallel
#undef whisper_full_n_segments
#undef whisper_full_n_segments_from_state
#undef whisper_full_lang_id
#undef whisper_full_lang_id_from_state
#undef whisper_full_get_segment_t0
#undef whisper_full_get_segment_t0_from_state
#undef whisper_full_get_segment_t1
#undef whisper_full_get_segment_t1_from_state
#undef whisper_full_get_segment_text
#undef whisper_full_get_segment_text_from_state
#undef whisper_full_n_tokens
#undef whisper_full_n_tokens_from_state
#undef whisper_full_get_token_text
#undef whisper_full_get_token_text_from_state
#undef whisper_full_get_token_id
#undef whisper_full_get_token_id_from_state
#undef whisper_full_get_token_data
#undef whisper_full_get_token_data_from_state
#undef whisper_full_get_token_p
#undef whisper_full_get_token_p_from_state
#undef whisper_print_system_info

#include "whisper_wrapper.h"

extern "C" {

const char * whisper_version(void) {
    return "1.5.4-wrapper";
}

whisper_context * whisper_init_from_file_with_params(const char * path_model, whisper_context_params params) {
    real_whisper_context_params cparams = real_whisper_context_default_params();
    cparams.use_gpu = params.use_gpu;
    return (whisper_context *) real_whisper_init_from_file_with_params(path_model, cparams);
}

whisper_context * whisper_init_from_file(const char * path_model) {
    real_whisper_context_params cparams = real_whisper_context_default_params();
    return (whisper_context *) real_whisper_init_from_file_with_params(path_model, cparams);
}

void whisper_free(whisper_context * ctx) {
    real_whisper_free((struct real_whisper_context *) ctx);
}

whisper_full_params whisper_full_default_params(int strategy) {
    real_whisper_full_params rparams = real_whisper_full_default_params((real_whisper_sampling_strategy) strategy);
    whisper_full_params wparams;
    std::memset(&wparams, 0, sizeof(wparams));

    wparams.strategy = (int) rparams.strategy;
    wparams.n_threads = rparams.n_threads;
    wparams.n_max_text_ctx = rparams.n_max_text_ctx;
    wparams.offset_ms = rparams.offset_ms;
    wparams.duration_ms = rparams.duration_ms;
    wparams.translate = rparams.translate;
    wparams.no_context = rparams.no_context;
    wparams.no_timestamps = rparams.no_timestamps;
    wparams.single_segment = rparams.single_segment;
    wparams.print_special = rparams.print_special;
    wparams.print_progress = rparams.print_progress;
    wparams.print_realtime = rparams.print_realtime;
    wparams.print_timestamps = rparams.print_timestamps;
    wparams.token_timestamps = rparams.token_timestamps;
    wparams.thold_pt = rparams.thold_pt;
    wparams.thold_ptsum = rparams.thold_ptsum;
    wparams.max_len = rparams.max_len;
    wparams.split_on_word = rparams.split_on_word;
    wparams.max_tokens = rparams.max_tokens;
    wparams.debug_mode = rparams.debug_mode;
    wparams.audio_ctx = rparams.audio_ctx;
    wparams.tdrz_enable = rparams.tdrz_enable;
    wparams.initial_prompt = rparams.initial_prompt;
    wparams.prompt_tokens = (const int *) rparams.prompt_tokens;
    wparams.prompt_n_tokens = rparams.prompt_n_tokens;
    wparams.language = rparams.language;
    wparams.detect_language = rparams.detect_language;
    wparams.suppress_blank = rparams.suppress_blank;
    wparams.suppress_nst = rparams.suppress_nst;
    wparams.temperature = rparams.temperature;
    wparams.max_initial_ts = rparams.max_initial_ts;
    wparams.length_penalty = rparams.length_penalty;
    wparams.temperature_inc = rparams.temperature_inc;
    wparams.entropy_thold = rparams.entropy_thold;
    wparams.logprob_thold = rparams.logprob_thold;
    wparams.no_speech_thold = rparams.no_speech_thold;
    wparams.greedy.best_of = rparams.greedy.best_of;
    wparams.beam_search.beam_size = rparams.beam_search.beam_size;
    wparams.beam_search.patience = rparams.beam_search.patience;

    return wparams;
}

whisper_context_params whisper_context_default_params(void) {
    real_whisper_context_params rparams = real_whisper_context_default_params();
    whisper_context_params wparams;
    std::memset(&wparams, 0, sizeof(wparams));
    wparams.use_gpu = rparams.use_gpu;
    return wparams;
}

int whisper_full(whisper_context * ctx, whisper_full_params params, const float * samples, int n_samples) {
    real_whisper_full_params rparams = real_whisper_full_default_params((real_whisper_sampling_strategy) params.strategy);
    
    rparams.n_threads = params.n_threads;
    rparams.n_max_text_ctx = params.n_max_text_ctx;
    rparams.offset_ms = params.offset_ms;
    rparams.duration_ms = params.duration_ms;
    rparams.translate = params.translate;
    rparams.no_context = params.no_context;
    rparams.no_timestamps = params.no_timestamps;
    rparams.single_segment = params.single_segment;
    rparams.print_special = params.print_special;
    rparams.print_progress = params.print_progress;
    rparams.print_realtime = params.print_realtime;
    rparams.print_timestamps = params.print_timestamps;
    rparams.token_timestamps = params.token_timestamps;
    rparams.thold_pt = params.thold_pt;
    rparams.thold_ptsum = params.thold_ptsum;
    rparams.max_len = params.max_len;
    rparams.split_on_word = params.split_on_word;
    rparams.max_tokens = params.max_tokens;
    rparams.debug_mode = params.debug_mode;
    rparams.audio_ctx = params.audio_ctx;
    rparams.tdrz_enable = params.tdrz_enable;
    rparams.initial_prompt = params.initial_prompt;
    rparams.prompt_tokens = (const int32_t *) params.prompt_tokens;
    rparams.prompt_n_tokens = params.prompt_n_tokens;
    rparams.language = params.language;
    rparams.detect_language = params.detect_language;
    rparams.suppress_blank = params.suppress_blank;
    rparams.suppress_nst = params.suppress_nst;
    rparams.temperature = params.temperature;
    rparams.max_initial_ts = params.max_initial_ts;
    rparams.length_penalty = params.length_penalty;
    rparams.temperature_inc = params.temperature_inc;
    rparams.entropy_thold = params.entropy_thold;
    rparams.logprob_thold = params.logprob_thold;
    rparams.no_speech_thold = params.no_speech_thold;
    rparams.greedy.best_of = params.greedy.best_of;
    rparams.beam_search.beam_size = params.beam_search.beam_size;
    rparams.beam_search.patience = params.beam_search.patience;

    return real_whisper_full((struct real_whisper_context *) ctx, rparams, samples, n_samples);
}

int whisper_full_n_segments(whisper_context * ctx) {
    return real_whisper_full_n_segments((struct real_whisper_context *) ctx);
}

const char * whisper_full_get_segment_text(whisper_context * ctx, int i_segment) {
    return real_whisper_full_get_segment_text((struct real_whisper_context *) ctx, i_segment);
}

int64_t whisper_full_get_segment_t0(whisper_context * ctx, int i_segment) {
    return real_whisper_full_get_segment_t0((struct real_whisper_context *) ctx, i_segment);
}

int64_t whisper_full_get_segment_t1(whisper_context * ctx, int i_segment) {
    return real_whisper_full_get_segment_t1((struct real_whisper_context *) ctx, i_segment);
}

int whisper_full_n_tokens(whisper_context * ctx, int i_segment) {
    return real_whisper_full_n_tokens((struct real_whisper_context *) ctx, i_segment);
}

const char * whisper_full_get_token_text(whisper_context * ctx, int i_segment, int i_token) {
    return real_whisper_full_get_token_text((struct real_whisper_context *) ctx, i_segment, i_token);
}

int whisper_full_lang_id(whisper_context * ctx) {
    return real_whisper_full_lang_id((struct real_whisper_context *) ctx);
}

int whisper_n_vocab(whisper_context * ctx) {
    return real_whisper_n_vocab((struct real_whisper_context *) ctx);
}

int whisper_n_text_ctx(whisper_context * ctx) {
    return real_whisper_n_text_ctx((struct real_whisper_context *) ctx);
}

int whisper_n_audio_ctx(whisper_context * ctx) {
    return real_whisper_n_audio_ctx((struct real_whisper_context *) ctx);
}

int whisper_is_multilingual(whisper_context * ctx) {
    return real_whisper_is_multilingual((struct real_whisper_context *) ctx);
}

}

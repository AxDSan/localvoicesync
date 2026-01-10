#include "vad_wrapper.h"
#include <onnxruntime/onnxruntime_c_api.h>
#include <vector>
#include <string>
#include <iostream>
#include <cmath>
#include <algorithm>
#include <cstring>

const OrtApi* g_ort = OrtGetApiBase()->GetApi(ORT_API_VERSION);

struct vad_context {
    OrtEnv* env;
    OrtSession* session;
    OrtMemoryInfo* mem_info;
    
    vad_config config;
    std::vector<float> state;
    std::vector<float> context;  // Context buffer (64 samples for 16kHz, 32 for 8kHz)
    
    vad_context() : env(nullptr), session(nullptr), mem_info(nullptr) {}
};

extern "C" {

vad_context* vad_init(const char* model_path, vad_config config) {
    vad_context* ctx = new vad_context();
    ctx->config = config;
    
    OrtStatus* status = g_ort->CreateEnv(ORT_LOGGING_LEVEL_WARNING, "VAD", &ctx->env);
    if (status != nullptr) {
        delete ctx;
        return nullptr;
    }
    
    OrtSessionOptions* session_options;
    g_ort->CreateSessionOptions(&session_options);
    g_ort->SetIntraOpNumThreads(session_options, 1);
    g_ort->SetSessionGraphOptimizationLevel(session_options, ORT_ENABLE_ALL);
    
    status = g_ort->CreateSession(ctx->env, model_path, session_options, &ctx->session);
    g_ort->ReleaseSessionOptions(session_options);
    
    if (status != nullptr) {
        const char* msg = g_ort->GetErrorMessage(status);
        std::cerr << "Failed to create ORT session: " << msg << std::endl;
        g_ort->ReleaseStatus(status);
        g_ort->ReleaseEnv(ctx->env);
        delete ctx;
        return nullptr;
    }
    
    g_ort->CreateMemoryInfo("Cpu", OrtDeviceAllocator, 0, OrtMemTypeDefault, &ctx->mem_info);
    
    // Initialize state (2 x 1 x 128 for Silero VAD)
    ctx->state.assign(2 * 1 * 128, 0.0f);
    
    // Initialize context buffer (64 samples for 16kHz, 32 for 8kHz)
    int context_size = (config.sample_rate == 16000) ? 64 : 32;
    ctx->context.assign(context_size, 0.0f);
    
    return ctx;
}

void vad_free(vad_context* ctx) {
    if (!ctx) return;
    if (ctx->session) g_ort->ReleaseSession(ctx->session);
    if (ctx->mem_info) g_ort->ReleaseMemoryInfo(ctx->mem_info);
    if (ctx->env) g_ort->ReleaseEnv(ctx->env);
    delete ctx;
}

void vad_reset(vad_context* ctx) {
    if (!ctx) return;
    std::fill(ctx->state.begin(), ctx->state.end(), 0.0f);
    std::fill(ctx->context.begin(), ctx->context.end(), 0.0f);
}

static int debug_counter = 0;

float vad_process(vad_context* ctx, const float* samples, int n_samples) {
    if (!ctx || !ctx->session) return 0.0f;
    
    int context_size = (int)ctx->context.size();
    
    // Build input: [context (64 samples) + new samples (512 samples)] = 576 samples total
    std::vector<float> input_with_context(context_size + n_samples);
    std::copy(ctx->context.begin(), ctx->context.end(), input_with_context.begin());
    std::copy(samples, samples + n_samples, input_with_context.begin() + context_size);
    
    int total_samples = (int)input_with_context.size();
    
    // Debug: check sample statistics every 50 calls
    debug_counter++;
    if (debug_counter % 50 == 0) {
        float maxAbs = 0.0f;
        float sum = 0.0f;
        for (int i = 0; i < total_samples; i++) {
            float abs = input_with_context[i] < 0 ? -input_with_context[i] : input_with_context[i];
            if (abs > maxAbs) maxAbs = abs;
            sum += input_with_context[i];
        }
        std::cout << "DEBUG: [VAD Native] n=" << total_samples << " (ctx=" << context_size << " + samples=" << n_samples << ") maxAbs=" << maxAbs << " mean=" << (sum/total_samples) << " sr=" << ctx->config.sample_rate << std::endl;
    }

    const char* input_names[] = {"input", "state", "sr"};
    const char* output_names[] = {"output", "stateN"};
    
    int64_t input_shape[] = {1, (int64_t)total_samples};
    int64_t state_shape[] = {2, 1, 128};
    int64_t sr_val = (int64_t) ctx->config.sample_rate;
    
    OrtValue* input_tensor = nullptr;
    g_ort->CreateTensorWithDataAsOrtValue(ctx->mem_info, (void*)input_with_context.data(), total_samples * sizeof(float), input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
    
    OrtValue* state_tensor = nullptr;
    g_ort->CreateTensorWithDataAsOrtValue(ctx->mem_info, (void*)ctx->state.data(), ctx->state.size() * sizeof(float), state_shape, 3, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &state_tensor);

    OrtValue* sr_tensor = nullptr;
    g_ort->CreateTensorWithDataAsOrtValue(ctx->mem_info, (void*)&sr_val, sizeof(int64_t), nullptr, 0, ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64, &sr_tensor);
    
    OrtValue* inputs[] = {input_tensor, state_tensor, sr_tensor};
    OrtValue* outputs[] = {nullptr, nullptr};
    
    OrtStatus* status = g_ort->Run(ctx->session, nullptr, input_names, (const OrtValue* const*)inputs, 3, output_names, 2, outputs);
    
    float prob = 0.0f;
    if (status == nullptr) {
        float* output_data;
        g_ort->GetTensorMutableData(outputs[0], (void**)&output_data);
        
        // Debug: print output tensor info
        if (debug_counter % 50 == 0) {
            OrtTensorTypeAndShapeInfo* type_info;
            g_ort->GetTensorTypeAndShape(outputs[0], &type_info);
            size_t num_dims;
            g_ort->GetDimensionsCount(type_info, &num_dims);
            std::vector<int64_t> dims(num_dims);
            g_ort->GetDimensions(type_info, dims.data(), num_dims);
            std::cout << "DEBUG: [VAD Native] output dims=" << num_dims << " [";
            for (size_t i = 0; i < num_dims; i++) std::cout << dims[i] << (i < num_dims-1 ? ", " : "");
            std::cout << "] values=[" << output_data[0] << "]" << std::endl;
            g_ort->ReleaseTensorTypeAndShapeInfo(type_info);
        }
        
        prob = output_data[0];
        
        // Update hidden state
        float* next_state_data;
        g_ort->GetTensorMutableData(outputs[1], (void**)&next_state_data);
        if (next_state_data) {
            std::memcpy(ctx->state.data(), next_state_data, ctx->state.size() * sizeof(float));
        }
        
        g_ort->ReleaseValue(outputs[0]);
        g_ort->ReleaseValue(outputs[1]);
    } else {
        const char* msg = g_ort->GetErrorMessage(status);
        std::cerr << "VAD ORT Run failed: " << msg << std::endl;
        g_ort->ReleaseStatus(status);
    }
    
    // Update context with the last 64 samples of the full input (context + new audio)
    // This matches the Python implementation: self._context = x[..., -context_size:]
    std::copy(input_with_context.end() - context_size, input_with_context.end(), ctx->context.begin());
    
    g_ort->ReleaseValue(input_tensor);
    g_ort->ReleaseValue(state_tensor);
    g_ort->ReleaseValue(sr_tensor);
    
    return prob;
}

}

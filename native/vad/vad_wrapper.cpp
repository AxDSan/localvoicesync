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
    ctx->state.assign(2 * 1 * 128, 0.0f);
    
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
}

float vad_process(vad_context* ctx, const float* samples, int n_samples) {
    if (!ctx || !ctx->session) return 0.0f;
    
    // Debug: check first few samples
    // std::cout << "First sample: " << samples[0] << std::endl;

    const char* input_names[] = {"input", "state", "sr"};
    const char* output_names[] = {"output", "stateN"};
    
    int64_t input_shape[] = {1, (int64_t)n_samples};
    int64_t state_shape[] = {2, 1, 128};
    int64_t sr_val = (int64_t) ctx->config.sample_rate;
    
    OrtValue* input_tensor = nullptr;
    g_ort->CreateTensorWithDataAsOrtValue(ctx->mem_info, (void*)samples, n_samples * sizeof(float), input_shape, 2, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input_tensor);
    
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
        prob = output_data[0];
        
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
    
    g_ort->ReleaseValue(input_tensor);
    g_ort->ReleaseValue(state_tensor);
    g_ort->ReleaseValue(sr_tensor);
    
    return prob;
}

}

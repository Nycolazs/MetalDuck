#ifndef LOSSLESS_SHADER_TRANSLATOR_H
#define LOSSLESS_SHADER_TRANSLATOR_H

#include <stddef.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/// One LSFG compute shader translated from SPIR-V to Metal Shading Language, with lsfg-metal's
/// binding layout: [[buffer(b)]] for binding b, [[sampler(b - 16)]] for samplers at binding 16+,
/// and [[texture(b - 32)]] for images at binding 32+ (sampled 0-15, storage 16+).
typedef struct {
    char *msl;          ///< Metal source, or NULL on failure. Free with lsfg_translation_free.
    char *entryPoint;   ///< Kernel function name in `msl`.
    char *error;        ///< Reason for failure, or NULL.
    uint32_t localSize[3];
} LSFGTranslation;

LSFGTranslation lsfg_translate_spirv(const uint32_t *words, size_t wordCount);
void lsfg_translation_free(LSFGTranslation *translation);

#ifdef __cplusplus
}
#endif

#endif

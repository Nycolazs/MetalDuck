#include "LosslessShaderTranslator.h"

#include "spirv_msl.hpp"

#include <cstdlib>
#include <cstring>
#include <string>

using namespace spirv_cross;

namespace {

char *copyString(const std::string &value) {
    char *out = static_cast<char *>(std::malloc(value.size() + 1));
    std::memcpy(out, value.c_str(), value.size() + 1);
    return out;
}

enum class Slot { buffer, sampler, texture };

/// Binds each resource at its SPIR-V binding minus the range's base, as lsfg-metal expects.
void bind(CompilerMSL &msl, const SmallVector<Resource> &resources, Slot slot, uint32_t base) {
    for (const auto &resource : resources) {
        MSLResourceBinding binding;
        binding.stage = spv::ExecutionModelGLCompute;
        binding.desc_set = msl.get_decoration(resource.id, spv::DecorationDescriptorSet);
        binding.binding = msl.get_decoration(resource.id, spv::DecorationBinding);
        const uint32_t index = binding.binding >= base ? binding.binding - base : binding.binding;
        switch (slot) {
            case Slot::buffer: binding.msl_buffer = index; break;
            case Slot::sampler: binding.msl_sampler = index; break;
            case Slot::texture: binding.msl_texture = index; break;
        }
        msl.add_msl_resource_binding(binding);
    }
}

} // namespace

extern "C" LSFGTranslation lsfg_translate_spirv(const uint32_t *words, size_t wordCount) {
    LSFGTranslation result{};
    try {
        CompilerMSL msl(words, wordCount);

        CompilerMSL::Options options = msl.get_msl_options();
        options.platform = CompilerMSL::Options::macOS;
        options.set_msl_version(3, 0);
        msl.set_msl_options(options);

        const ShaderResources resources = msl.get_shader_resources();
        bind(msl, resources.uniform_buffers, Slot::buffer, 0);
        bind(msl, resources.separate_samplers, Slot::sampler, 16);
        bind(msl, resources.separate_images, Slot::texture, 32);
        bind(msl, resources.storage_images, Slot::texture, 32);

        for (uint32_t i = 0; i < 3; i++)
            result.localSize[i] = msl.get_execution_mode_argument(spv::ExecutionModeLocalSize, i);

        const auto entryPoints = msl.get_entry_points_and_stages();
        if (entryPoints.empty()) {
            result.error = copyString("shader has no entry point");
            return result;
        }

        std::string source = msl.compile();
        // SPIRV-Cross keeps "precise" multiplies exact with helpers marked optnone, which become real
        // function calls on the GPU. They stay exact without the marker (as lsfg-metal's script does).
        const std::string optnone = "[[clang::optnone]] ";
        for (size_t at = source.find(optnone); at != std::string::npos; at = source.find(optnone, at))
            source.erase(at, optnone.size());

        result.entryPoint = copyString(msl.get_cleansed_entry_point_name(entryPoints[0].name, entryPoints[0].execution_model));
        result.msl = copyString(source);
    } catch (const std::exception &error) {
        result.error = copyString(error.what());
    }
    return result;
}

extern "C" void lsfg_translation_free(LSFGTranslation *translation) {
    std::free(translation->msl);
    std::free(translation->entryPoint);
    std::free(translation->error);
    *translation = LSFGTranslation{};
}

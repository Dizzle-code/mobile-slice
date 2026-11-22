// Standalone slicer for Android, Windows and macOS: STL/3MF + flattened Bambu profiles -> G-code and .gcode.3mf.
// Protocol: lines prefixed with "@@" on stderr/stdout are JSON events for the app.
// Modes: with --preview <stl> it only places the model and writes it as binary STL; otherwise it slices.
#include <boost/log/core.hpp>
#include <nlohmann/json.hpp>
#include <oneapi/tbb/task_arena.h>
#include <chrono>
#include <cstdio>
#include <exception>
#include <filesystem>
#include <map>
#include <stdexcept>
#include <string>
#include <thread>
#include "libslic3r/BoundingBox.hpp"
#include "libslic3r/Format/STL.hpp"
#include "libslic3r/Format/bbs_3mf.hpp"
#include "libslic3r/GCode/GCodeProcessor.hpp"
#include "libslic3r/Model.hpp"
#include "libslic3r/Print.hpp"
#include "libslic3r/PrintConfig.hpp"
#include "libslic3r/ProjectTask.hpp"
#include "libslic3r/Utils.hpp"
#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#define WIN32_LEAN_AND_MEAN
#include <io.h>
#include <process.h>
#include <windows.h>
#include <psapi.h>
#else
#include <sys/resource.h>
#include <unistd.h>
#endif

namespace {
namespace fs = std::filesystem;
using nlohmann::json;
using Clock = std::chrono::steady_clock;

std::string g_stage = "start";

void emit(const json& event) {
    const std::string line = "@@" + event.dump() + "\n";
    std::fwrite(line.data(), 1, line.size(), stderr);
    std::fflush(stderr);
}

void set_stage(const std::string& stage) {
    g_stage = stage;
    emit({{"stage", stage}});
}

long max_rss_kb() {
#ifdef _WIN32
    PROCESS_MEMORY_COUNTERS counters{};
    if (!GetProcessMemoryInfo(GetCurrentProcess(), &counters, sizeof(counters))) return 0;
    return static_cast<long>(counters.PeakWorkingSetSize / 1024);
#else
    rusage usage{};
    getrusage(RUSAGE_SELF, &usage);
#ifdef __APPLE__
    return static_cast<long>(usage.ru_maxrss / 1024); // bytes on macOS
#else
    return usage.ru_maxrss;
#endif
#endif
}

long elapsed_ms(Clock::time_point since) {
    return static_cast<long>(std::chrono::duration_cast<std::chrono::milliseconds>(Clock::now() - since).count());
}

struct Args {
    std::map<std::string, std::string> values;
    const std::string& get(const std::string& key) const {
        auto it = values.find(key);
        if (it == values.end()) throw std::runtime_error("Argument fehlt: --" + key);
        return it->second;
    }
    std::string get_or(const std::string& key, const std::string& fallback) const {
        auto it = values.find(key);
        return it == values.end() ? fallback : it->second;
    }
    bool has(const std::string& key) const { return values.count(key) != 0; }
};

Args parse_args(int argc, char** argv) {
    Args args;
    for (int i = 1; i + 1 < argc; i += 2) {
        std::string key = argv[i];
        if (key.rfind("--", 0) != 0) throw std::runtime_error("Unerwartetes Argument: " + key);
        args.values[key.substr(2)] = argv[i + 1];
    }
    return args;
}

// Generic enum defaults need their definition map reattached before profile values apply.
void fix_enum_maps(Slic3r::DynamicPrintConfig& config) {
    for (const auto& entry : config.def()->options) {
        const auto& def = entry.second;
        if (def.type != Slic3r::coEnums || def.enum_keys_map == nullptr) continue;
        auto* option = config.option(entry.first, false);
        if (auto* item = dynamic_cast<Slic3r::ConfigOptionEnumsGeneric*>(option)) {
            if (!item->keys_map) item->keys_map = def.enum_keys_map;
        } else if (auto* item = dynamic_cast<Slic3r::ConfigOptionEnumsGenericNullable*>(option)) {
            if (!item->keys_map) item->keys_map = def.enum_keys_map;
        }
    }
}

Slic3r::DynamicPrintConfig load_profile(const fs::path& path, Slic3r::ConfigSubstitutionContext& substitutions) {
    if (!fs::is_regular_file(path)) throw std::runtime_error("Profil fehlt: " + path.string());
    Slic3r::DynamicPrintConfig config;
    std::map<std::string, std::string> key_values;
    std::string reason;
    if (config.load_from_json(path.string(), substitutions, true, key_values, reason) != 0 || !reason.empty())
        throw std::runtime_error("Profil " + path.filename().string() + " nicht lesbar: " + reason);
    return config;
}

// Values arrive as JSON (string, number or bool) and are parsed like profile values.
void apply_overrides(Slic3r::DynamicPrintConfig& config, const std::string& text) {
    const json overrides = json::parse(text);
    if (!overrides.is_object()) throw std::runtime_error("--overrides muss ein JSON-Objekt sein");
    for (const auto& [key, value] : overrides.items()) {
        if (config.def()->get(key) == nullptr) throw std::runtime_error("Unbekannte Einstellung: " + key);
        std::string text_value;
        if (value.is_string()) text_value = value.get<std::string>();
        else if (value.is_boolean()) text_value = value.get<bool>() ? "1" : "0";
        else if (value.is_number()) text_value = value.dump();
        else throw std::runtime_error("Ungültiger Wert für " + key);
        try {
            config.set_deserialize_strict(key, text_value);
        } catch (const std::exception&) {
            throw std::runtime_error("Ungültiger Wert für " + key + ": " + text_value);
        }
    }
    emit({{"overrides", overrides.size()}});
}

Slic3r::DynamicPrintConfig load_config(const Args& args, Slic3r::ConfigSubstitutionContext& substitutions, bool with_print_profiles) {
    auto config = Slic3r::DynamicPrintConfig::full_print_config();
    fix_enum_maps(config);
    config.apply(load_profile(args.get("printer"), substitutions), true);
    if (with_print_profiles) {
        config.apply(load_profile(args.get("process"), substitutions), true);
        config.apply(load_profile(args.get("filament"), substitutions), true);
    }
    // The P1S ships with the textured PEI plate.
    config.set_key_value("curr_bed_type", new Slic3r::ConfigOptionEnum<Slic3r::BedType>(Slic3r::btPTE));
    if (args.has("overrides")) apply_overrides(config, args.get("overrides"));
    // The app must never run host post-processing scripts.
    if (auto* commands = config.option<Slic3r::ConfigOptionStrings>("post_process")) commands->values.clear();
    config.normalize_fdm();
    return config;
}

Slic3r::BoundingBoxf bed_of(const Slic3r::DynamicPrintConfig& config) {
    const auto* area = config.option<Slic3r::ConfigOptionPoints>("printable_area");
    if (area == nullptr || area->values.empty()) throw std::runtime_error("Druckbereich fehlt im Druckerprofil");
    return Slic3r::BoundingBoxf(area->values);
}

struct LoadedModel {
    Slic3r::Model model;
    size_t triangles = 0;
    long load_ms = 0;
    Slic3r::BoundingBoxf3 bounds;
    bool fits = false;
};

double scale_of(const Args& args) {
    if (!args.has("scale")) return 1.0;
    double scale = 0;
    try {
        scale = std::stod(args.get("scale"));
    } catch (const std::exception&) {
        throw std::runtime_error("Ungültiger Wert für --scale: " + args.get("scale"));
    }
    if (!(scale >= 0.01 && scale <= 100.0)) throw std::runtime_error("--scale muss zwischen 0.01 und 100 liegen");
    return scale;
}

// Loads STL or 3MF geometry only (project settings inside a 3MF are ignored), scales it uniformly and centers it on the bed.
LoadedModel load_model(const fs::path& model_path, const Slic3r::DynamicPrintConfig& config, double scale) {
    set_stage("load_model");
    const auto load_start = Clock::now();
    if (!fs::is_regular_file(model_path)) throw std::runtime_error("Modell fehlt: " + model_path.string());
    LoadedModel loaded;
    loaded.model = Slic3r::Model::read_from_file(model_path.string(), nullptr, nullptr,
        Slic3r::LoadStrategy::LoadModel | Slic3r::LoadStrategy::AddDefaultInstances);
    auto& model = loaded.model;
    if (model.objects.empty()) throw std::runtime_error("Modell enthält keine Objekte");
    for (auto* object : model.objects) {
        if (scale != 1.0) object->scale(scale);
        object->ensure_on_bed();
        for (const auto* volume : object->volumes)
            if (volume->is_model_part()) loaded.triangles += volume->mesh().facets_count();
    }
    const auto bed = bed_of(config);
    model.center_instances_around_point(bed.center());
    loaded.bounds = model.bounding_box_exact();
    const double height = config.opt_float("printable_height");
    constexpr double eps = 0.01;
    loaded.fits = loaded.bounds.min.x() >= bed.min.x() - eps && loaded.bounds.min.y() >= bed.min.y() - eps &&
        loaded.bounds.max.x() <= bed.max.x() + eps && loaded.bounds.max.y() <= bed.max.y() + eps &&
        loaded.bounds.max.z() <= height + eps;
    loaded.load_ms = elapsed_ms(load_start);
    const auto size = loaded.bounds.size();
    emit({{"model", {{"objects", model.objects.size()}, {"triangles", loaded.triangles}, {"loadMs", loaded.load_ms},
        {"size", {size.x(), size.y(), size.z()}}, {"scale", scale}, {"fits", loaded.fits}}}});
    return loaded;
}

json bounds_json(const Slic3r::BoundingBoxf3& box) {
    return {{"min", {box.min.x(), box.min.y(), box.min.z()}}, {"max", {box.max.x(), box.max.y(), box.max.z()}}};
}

json preview(const Args& args) {
    const auto total_start = Clock::now();
    const fs::path output = args.get("preview");
    Slic3r::set_resources_dir(args.get("resources"));
    Slic3r::set_temporary_dir(output.parent_path().string());
    set_stage("profiles");
    Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Enable);
    const auto config = load_config(args, substitutions, false);
    auto loaded = load_model(args.get("model"), config, scale_of(args));
    set_stage("export");
    if (!Slic3r::store_stl(output.string().c_str(), &loaded.model, true) || !fs::is_regular_file(output))
        throw std::runtime_error("Vorschau-STL konnte nicht geschrieben werden");
    const auto bed = bed_of(config);
    return {
        {"objects", loaded.model.objects.size()},
        {"triangles", loaded.triangles},
        {"bounds", bounds_json(loaded.bounds)},
        {"bed", {{"min", {bed.min.x(), bed.min.y()}}, {"max", {bed.max.x(), bed.max.y()}},
                 {"height", config.opt_float("printable_height")}}},
        {"fits", loaded.fits},
        {"loadMs", loaded.load_ms},
        {"totalMs", elapsed_ms(total_start)},
        {"maxRssKb", max_rss_kb()},
    };
}

std::string first_string(const Slic3r::DynamicPrintConfig& config, const char* key) {
    const auto* option = config.option<Slic3r::ConfigOptionStrings>(key);
    return option == nullptr || option->values.empty() ? std::string() : option->values.front();
}

// Packs the G-code like Bambu Studio's "export plate sliced file": Metadata/plate_1.gcode plus slice info.
void export_gcode_3mf(const fs::path& path, const fs::path& gcode, Slic3r::Model& model, Slic3r::Print& print,
                      Slic3r::DynamicPrintConfig& config, Slic3r::GCodeProcessorResult& result, const std::string& model_id) {
    set_stage("export_3mf");
    Slic3r::PlateData plate;
    plate.plate_index = 0;
    for (size_t o = 0; o < model.objects.size(); ++o)
        for (size_t i = 0; i < model.objects[o]->instances.size(); ++i)
            plate.objects_and_instances.emplace_back(int(o), int(i));
    plate.printer_model_id = model_id;
    const auto* nozzles = config.option<Slic3r::ConfigOptionFloats>("nozzle_diameter");
    if (nozzles != nullptr && !nozzles->values.empty()) {
        char buffer[32];
        std::snprintf(buffer, sizeof buffer, "%.1f", nozzles->values.front());
        plate.nozzle_diameters = buffer;
    }
    plate.gcode_file = gcode.string();
    plate.is_sliced_valid = true;
    plate.gcode_prediction = std::to_string(int(result.print_statistics.modes[0].time));
    char weight[32];
    std::snprintf(weight, sizeof weight, "%.2f", print.print_statistics().total_weight);
    plate.gcode_weight = weight;
    plate.toolpath_outside = result.toolpath_outside;
    plate.is_label_object_enabled = result.label_object_enabled;
    plate.timelapse_warning_code = result.timelapse_warning_code;
    plate.is_support_used = print.is_support_used();
    plate.parse_filament_info(&result);
    for (auto& filament : plate.slice_filaments_info) {
        filament.type = first_string(config, "filament_type");
        filament.color = first_string(config, "filament_colour");
        filament.filament_id = first_string(config, "filament_ids");
    }

    Slic3r::StoreParams params;
    const std::string path_string = path.string();
    params.path = path_string.c_str();
    params.model = &model;
    params.plate_data_list = {&plate};
    params.export_plate_idx = 0;
    params.config = &config;
    params.strategy = Slic3r::SaveStrategy::Silence | Slic3r::SaveStrategy::SplitModel |
        Slic3r::SaveStrategy::WithGcode | Slic3r::SaveStrategy::SkipModel;
    if (!Slic3r::store_bbs_3mf(params) || !fs::is_regular_file(path) || fs::file_size(path) == 0)
        throw std::runtime_error("3MF-Datei konnte nicht geschrieben werden");
}

json slice(const Args& args) {
    const auto total_start = Clock::now();
    const fs::path output = args.get("output");
    Slic3r::set_resources_dir(args.get("resources"));
    Slic3r::set_temporary_dir(output.parent_path().string());

    set_stage("profiles");
    Slic3r::ConfigSubstitutionContext substitutions(Slic3r::ForwardCompatibilitySubstitutionRule::Enable);
    auto config = load_config(args, substitutions, true);

    auto loaded = load_model(args.get("model"), config, scale_of(args));
    auto& model = loaded.model;
    if (!loaded.fits) {
        const auto size = loaded.bounds.size();
        char text[160];
        std::snprintf(text, sizeof text, "Modell passt nicht auf das Druckbett (%.0f x %.0f x %.0f mm)",
                      size.x(), size.y(), size.z());
        throw std::runtime_error(text);
    }

    set_stage("validate");
    Slic3r::Print print;
    print.apply(model, config);
    Slic3r::StringObjectException warning{};
    const auto error = print.validate(&warning);
    if (!warning.string.empty()) emit({{"warning", warning.string}});
    if (!error.string.empty()) throw std::runtime_error("Validierung: " + error.string);

    print.set_status_callback([](const Slic3r::PrintBase::SlicingStatus& status) {
        if (status.percent >= 0) emit({{"progress", status.percent}, {"message", status.text}});
    });

    set_stage("process");
    const auto process_start = Clock::now();
    print.process();
    const long process_ms = elapsed_ms(process_start);

    set_stage("export");
    const auto export_start = Clock::now();
    Slic3r::GCodeProcessorResult result;
    print.export_gcode(output.string(), &result, nullptr);
    if (!fs::is_regular_file(output) || fs::file_size(output) == 0)
        throw std::runtime_error("Keine G-Code-Datei erzeugt");
    json archive = nullptr;
    if (args.has("export-3mf")) {
        const fs::path archive_path = args.get("export-3mf");
        export_gcode_3mf(archive_path, output, model, print, config, result, args.get_or("model-id", ""));
        archive = archive_path.string();
    }
    const long export_ms = elapsed_ms(export_start);

    const auto& mode = result.print_statistics.modes[0];
    const auto& stats = print.print_statistics();
    return {
        {"gcodeBytes", fs::file_size(output)},
        {"archive", archive},
        {"objects", model.objects.size()},
        {"triangles", loaded.triangles},
        {"layers", mode.layers_times.size()},
        {"printSeconds", mode.time},
        {"filamentMm", stats.total_used_filament},
        {"filamentGrams", stats.total_weight},
        {"supportUsed", print.is_support_used()},
        {"bounds", bounds_json(loaded.bounds)},
        {"loadMs", loaded.load_ms},
        {"processMs", process_ms},
        {"exportMs", export_ms},
        {"totalMs", elapsed_ms(total_start)},
        {"maxRssKb", max_rss_kb()},
        {"threads", oneapi::tbb::this_task_arena::max_concurrency()},
        {"hardwareThreads", std::thread::hardware_concurrency()},
        {"substitutions", substitutions.substitutions.size()},
    };
}
}

int main(int argc, char** argv) {
    // Engine diagnostics stay on stderr; the app reads both streams line by line.
#ifdef _WIN32
    ::_dup2(::_fileno(stderr), ::_fileno(stdout));
    emit({{"pid", static_cast<long>(::_getpid())}});
#else
    ::dup2(STDERR_FILENO, STDOUT_FILENO);
    emit({{"pid", static_cast<long>(::getpid())}});
#endif
    boost::log::core::get()->set_logging_enabled(false);
    try {
        const auto args = parse_args(argc, argv);
        if (args.values.count("verbose") && args.values.at("verbose") == "1")
            boost::log::core::get()->set_logging_enabled(true);
        auto result = args.has("preview") ? preview(args) : slice(args);
        emit({{"result", result}});
        return 0;
    } catch (const std::exception& e) {
        emit({{"error", e.what()}, {"stage", g_stage}, {"maxRssKb", max_rss_kb()}});
        return 1;
    } catch (...) {
        emit({{"error", "Unbekannter Fehler"}, {"stage", g_stage}, {"maxRssKb", max_rss_kb()}});
        return 1;
    }
}

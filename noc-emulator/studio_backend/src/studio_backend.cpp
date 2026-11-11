#include "noc_studio.h"
#include "device.hpp"
#include <nlohmann/json.hpp>
#include <algorithm>
#include <array>
#include <bit>
#include <chrono>
#include <cmath>
#include <cstdlib>
#include <cstring>
#include <numeric>
#include <random>
#include <stdexcept>
#include <string>
#include <vector>

namespace {
using Json = nlohmann::json;
using Clock = std::chrono::steady_clock;
using Event = noc::Event;
constexpr size_t max_events = 8'000'000;
double milliseconds(Clock::time_point t) {
    return std::chrono::duration<double, std::milli>(Clock::now() - t).count();
}
void require(bool ok, const std::string &message) {
    if (!ok) throw std::invalid_argument(message);
}
struct Request {
    noc::Mesh mesh{};
    std::string traffic, routing, requirement, model_source;
    uint64_t period, warmup, samples, seed, begin, end;
    double center, l_max, l_mean, bandwidth;
    std::vector<uint32_t> terminals;
    std::vector<double> rates;
};
Request parse(const Json &j) {
    Request r{};
    r.mesh.rows = j.at("rows").get<uint32_t>(); r.mesh.cols = j.at("cols").get<uint32_t>();
    require(r.mesh.rows >= 1 && r.mesh.rows <= 8 && r.mesh.cols >= 1 && r.mesh.cols <= 8 &&
            r.mesh.rows * r.mesh.cols >= 2, "FPGA supports rectangular meshes with 1..8 rows/cols and at least two nodes");
    r.mesh.transform = j.value("transform", uint32_t(noc::Transpose));
    r.mesh.origin_row = j.value("origin_row", 0u); r.mesh.origin_col = j.value("origin_col", 0u);
    const auto pr = r.mesh.transform & noc::Transpose ? r.mesh.cols : r.mesh.rows;
    const auto pc = r.mesh.transform & noc::Transpose ? r.mesh.rows : r.mesh.cols;
    require(r.mesh.transform <= 7 && r.mesh.origin_row <= 8 - pr && r.mesh.origin_col <= 8 - pc,
            "Coordinate transform does not fit the physical 8x8 mesh");
    r.traffic = j.value("traffic", std::string("worst_perm"));
    r.routing = j.value("routing", std::string("dor"));
    if (r.routing.empty()) r.routing = "dor";
    require(r.routing == "dor" || r.routing == "valiant" || r.routing == "valiant_terminal",
            "FPGA routing must be dor, valiant or valiant_terminal");
    r.mesh.routing = r.routing == "dor" ? 0 : 1;
    r.period = j.value("sample_period", uint64_t(1000));
    r.warmup = j.value("warmup_periods", uint64_t(3));
    r.samples = j.value("max_samples", uint64_t(10));
    r.seed = j.value("seed", uint64_t(42));
    require(r.period >= 10 && r.period <= 1'000'000 && r.warmup <= 1000 &&
            r.samples >= 1 && r.samples <= 10000, "Invalid sampling period/count");
    r.begin = r.period * r.warmup; r.end = r.begin + r.period * r.samples;
    r.center = j.value("injection_rate", 0.1);
    require(std::isfinite(r.center) && r.center > 0 && r.center <= 1, "Injection rate must be in (0,1]");
    r.terminals = j.value("terminals", std::vector<uint32_t>{});
    std::array<bool, 64> seen{};
    for (auto id : r.terminals) {
        require(id < r.mesh.rows * r.mesh.cols && !seen[id], "Invalid or duplicate terminal node ID");
        seen[id] = true;
    }
    r.l_max = 0; r.l_mean = 0;
    const auto loads = j.value("l_star", std::vector<double>{});
    for (double x : loads) {
        require(std::isfinite(x) && x >= 0, "Invalid model link load");
        r.l_max = std::max(r.l_max, x); r.l_mean += x;
    }
    if (!loads.empty()) r.l_mean /= loads.size();
    r.bandwidth = j.value("B_star", 0.0);
    r.requirement = j.value("requirement", std::string("qos"));
    r.model_source = j.value("model_source", std::string("unknown"));
    const bool use_model = r.l_max > 1e-6;
    const double center = std::clamp(use_model ? 1.0 / r.l_max : r.center, 0.005, 0.95);
    const double low = std::max(0.005, center * (use_model ? 0.4 : 0.25));
    const double high = std::min(0.95, center * (use_model ? 2.0 : 3.0));
    // Distribute after clipping so all 12 rates remain distinct at the limits.
    for (unsigned i = 0; i < 12; ++i)
        r.rates.push_back(std::round((low + (high - low) * i / 11) * 1e6) / 1e6);
    return r;
}

struct Traffic {
    struct Row {
        uint32_t src;
        std::vector<uint8_t> destinations;
        std::vector<double> weights;
        double intensity = 0;
    };
    std::vector<Row> rows;
    std::vector<uint8_t> mids;
    uint32_t normalization_nodes = 0;
    std::string scope, note;
};
Traffic traffic(const Request &r, const Json &j) {
    Traffic t;
    const uint32_t n = r.mesh.rows * r.mesh.cols;
    const bool model = r.traffic == "worst_perm" || r.traffic == "custom" || r.traffic == "self_defined";
    std::vector<uint32_t> sources = r.terminals;
    if (!model) { sources.resize(n); std::iota(sources.begin(), sources.end(), 0); }
    require(!sources.empty(), "Model traffic requires terminal node IDs");
    t.normalization_nodes = sources.size();
    t.scope = model ? "terminal" : "logical_node";
    if (r.routing == "valiant_terminal") {
        require(!r.terminals.empty(), "valiant_terminal requires terminal node IDs");
        t.mids.assign(r.terminals.begin(), r.terminals.end());
    } else {
        for (uint32_t i = 0; i < n; ++i) t.mids.push_back(i);
    }
    auto permutation = j.value("permutation", std::vector<uint32_t>{});
    bool valid_perm = permutation.size() == sources.size();
    std::vector<bool> seen(sources.size());
    for (auto v : permutation) {
        if (v >= seen.size() || seen[v]) { valid_perm = false; break; }
        seen[v] = true;
    }
    const bool use_perm = (r.traffic == "worst_perm" || r.traffic == "self_defined") && valid_perm;
    if (r.traffic == "self_defined") require(use_perm, "self_defined requires a terminal-index permutation");
    std::vector<std::vector<double>> od;
    if (model && !use_perm) {
        od = j.value("od", std::vector<std::vector<double>>{});
        require(od.size() == sources.size(), "Model traffic requires an OD matrix or valid worst permutation");
        for (const auto &row : od) require(row.size() == sources.size(), "OD matrix must be square in terminal-index space");
    }
    if (r.traffic == "transpose") require(r.mesh.rows == r.mesh.cols, "transpose traffic requires a square logical mesh");
    if (r.traffic == "bitrev" || r.traffic == "shuffle")
        require(std::has_single_bit(n), "bitrev/shuffle traffic requires a power-of-two node count");
    std::vector<uint32_t> random_perm(n);
    std::iota(random_perm.begin(), random_perm.end(), 0);
    if (r.traffic == "randperm") {
        std::mt19937_64 random(r.seed);
        bool good = false;
        for (unsigned tries = 0; tries < 64 && !good; ++tries) {
            std::shuffle(random_perm.begin(), random_perm.end(), random);
            good = true;
            for (uint32_t i = 0; i < n; ++i) good &= random_perm[i] != i;
        }
        if (!good) for (uint32_t i = 0; i < n; ++i) random_perm[i] = (i + 1) % n;
    }
    double max_weight = 0;
    for (size_t si = 0; si < sources.size(); ++si) {
        const auto src = sources[si];
        Traffic::Row row{src, {}, {}, 0};
        auto add = [&](uint32_t dst, double weight = 1) {
            require(std::isfinite(weight) && weight >= 0, "OD weights must be finite and nonnegative");
            if (dst != src && weight > 0) {
                row.destinations.push_back(dst); row.weights.push_back(weight); row.intensity += weight;
            }
        };
        const uint32_t x = src % r.mesh.cols, y = src / r.mesh.cols;
        if (model) {
            if (use_perm) add(sources[permutation[si]]);
            else for (size_t di = 0; di < sources.size(); ++di) add(sources[di], od[si][di]);
        } else if (r.traffic == "uniform") {
            for (uint32_t dst = 0; dst < n; ++dst) add(dst);
        } else if (r.traffic == "randperm") add(random_perm[src]);
        else if (r.traffic == "bitcomp") add(n - 1 - src);
        else if (r.traffic == "transpose") add(x * r.mesh.cols + y);
        else if (r.traffic == "neighbor") add(r.mesh.cols > 1 ? y * r.mesh.cols + (x + 1) % r.mesh.cols : (src + 1) % n);
        else if (r.traffic == "diagonal") add((y + 1) % r.mesh.rows * r.mesh.cols + (x + 1) % r.mesh.cols);
        else if (r.traffic == "hotspot") add((r.mesh.rows / 2) * r.mesh.cols + r.mesh.cols / 2);
        else if (r.traffic == "tornado") {
            const uint32_t dx = std::max(1, int(r.mesh.cols / 2) - 1);
            const uint32_t dy = std::max(1, int(r.mesh.rows / 2) - 1);
            add((y + dy) % r.mesh.rows * r.mesh.cols + (x + dx) % r.mesh.cols);
        } else if (r.traffic == "bitrev") {
            uint32_t dst = 0, v = src;
            for (int b = 0; b < std::bit_width(n) - 1; ++b) { dst = (dst << 1) | (v & 1); v >>= 1; }
            add(dst);
        } else if (r.traffic == "shuffle") add(((src << 1) & (n - 1)) | (src >> (std::bit_width(n) - 2)));
        else throw std::invalid_argument("Unsupported FPGA traffic: " + r.traffic);
        require(std::isfinite(row.intensity), "OD row sum overflow");
        max_weight = std::max(max_weight, row.intensity);
        if (row.intensity > 0) t.rows.push_back(std::move(row));
    }
    require(max_weight > 0, "Traffic contains no non-local packets");
    for (auto &row : t.rows) {
        row.intensity /= max_weight;
        require(row.intensity >= 1e-12, "OD source intensity is too small to sample");
    }
    t.note = model ? (use_perm ? "模型置换；仅 terminal 注入" : "OD 行和决定源强度，行内权重决定目的概率") :
                      "逻辑 mesh 节点注入；自发送映射不产生包";
    return t;
}

std::vector<Event> generate(const Request &r, const Traffic &t, double rate) {
    double expected = 0;
    for (const auto &row : t.rows) expected += r.end * rate * row.intensity;
    require(expected < max_events * 0.95, "Trace exceeds the 8-million-packet budget; reduce sample_period/max_samples");
    std::vector<Event> events;
    events.reserve(std::min<size_t>(max_events, size_t(expected * 1.1) + 64));
    for (const auto &row : t.rows) {
        const uint64_t seed = r.seed ^ (0x9e3779b97f4a7c15ULL * (row.src + 1));
        std::mt19937_64 times(seed), destinations(seed ^ 0x243f6a8885a308d3ULL), mids(seed ^ 0xb7e151628aed2a6bULL);
        std::geometric_distribution<uint64_t> gaps(rate * row.intensity);
        std::discrete_distribution<uint32_t> dest(row.weights.begin(), row.weights.end());
        std::uniform_int_distribution<uint32_t> mid(0, t.mids.size() - 1);
        uint64_t time = gaps(times);
        while (time < r.end) {
            if (events.size() == max_events) throw std::length_error("Trace packet budget exceeded");
            const auto dst = row.destinations[dest(destinations)];
            events.push_back({time, 1, uint8_t(row.src), dst,
                             r.mesh.routing ? t.mids[mid(mids)] : dst});
            const uint64_t gap = gaps(times);
            if (gap >= r.end - time - 1) break;
            time += gap + 1;
        }
    }
    return events;
}
unsigned distance(uint8_t a, uint8_t b, uint32_t cols) {
    return std::abs(int(a / cols) - int(b / cols)) + std::abs(int(a % cols) - int(b % cols));
}
Json timing(const noc::Timings &t) {
    return {{"prepare_ms", t.prepare_ns / 1e6}, {"upload_ms", t.upload_ns / 1e6},
            {"command_to_done_ms", t.command_to_done_ns / 1e6}, {"download_ms", t.download_ns / 1e6},
            {"decode_ms", t.decode_ns / 1e6}, {"submit_to_result_ms", t.submit_to_result_ns / 1e6}};
}
Json summarize(const Request &r, const Traffic &traffic, double rate, const std::vector<Event> &events,
               const noc::Result &output, const std::vector<noc::Link> &links) {
    uint64_t warmup_sent = 0, completed_begin = 0, completed_end = 0, measured = 0, hops = 0;
    long double latency_sum = 0;
    std::vector<uint64_t> latencies;
    latencies.reserve(events.size());
    for (size_t i = 0; i < events.size(); ++i) {
        const auto &e = events[i];
        const auto finish = output.completion_cycles[i];
        warmup_sent += e.send_time < r.begin;
        completed_begin += finish <= r.begin; completed_end += finish <= r.end;
        if (e.send_time >= r.begin) {
            ++measured;
            const uint64_t latency = finish - e.send_time;
            latency_sum += latency; latencies.push_back(latency);
            hops += r.mesh.routing ? distance(e.src, e.mid, r.mesh.cols) + distance(e.mid, e.dst, r.mesh.cols) :
                                     distance(e.src, e.dst, r.mesh.cols);
        }
    }
    const double cycles = r.end - r.begin;
    const double denom = cycles * traffic.normalization_nodes;
    const double accepted = (completed_end - completed_begin) / denom;
    const double offered = measured / denom;
    const uint64_t backlog_begin = warmup_sent - completed_begin;
    const uint64_t backlog_end = events.size() - completed_end;
    const int64_t growth = int64_t(backlog_end) - int64_t(backlog_begin);
    Json latency = nullptr, p95 = nullptr, maximum = nullptr, mean_hops = nullptr;
    if (measured) {
        latency = double(latency_sum / measured); mean_hops = double(hops) / measured;
        maximum = *std::max_element(latencies.begin(), latencies.end());
        const size_t rank = std::min(latencies.size() - 1, size_t(std::ceil(0.95 * latencies.size())) - 1);
        std::nth_element(latencies.begin(), latencies.begin() + rank, latencies.end());
        p95 = latencies[rank];
    }
    Json stats = Json::array();
    for (const auto &link : links) {
        const auto &c = output.physical_counters[link.physical_id];
        stats.push_back({c.flits, c.heads, c.blocked, c.contended});
    }
    return {{"injection_rate", rate}, {"offered_rate", offered}, {"injected_rate", nullptr},
            {"accepted_throughput", accepted},
            {"accepted_per_logical_node", (completed_end - completed_begin) / (cycles * r.mesh.rows * r.mesh.cols)},
            {"latency_cycles", latency}, {"latency_p95_cycles", p95}, {"latency_max_cycles", maximum},
            {"network_latency_cycles", nullptr}, {"hops", mean_hops}, {"ok", measured > 0},
            {"unstable", growth > std::max<int64_t>(8, measured / 20) && accepted < offered * 0.95},
            {"packet_count", events.size()}, {"measured_packets", measured},
            {"accepted_packets", completed_end - completed_begin}, {"backlog_begin", backlog_begin},
            {"backlog_end", backlog_end}, {"logical_cycle", output.logical_cycle},
            {"link_stats", std::move(stats)}, {"timing", timing(output.timings)}, {"label", std::to_string(rate)}};
}

Json run(const Json &j) {
    const auto started = Clock::now();
    const auto r = parse(j);
    const auto pattern = traffic(r, j);
    noc::Device device(r.mesh);
    Json series = Json::array(), links = Json::array(), log = Json::array(), warnings = Json::array();
    for (const auto &link : device.links())
        links.push_back({{"src", link.src}, {"dst", link.dst}, {"kind", link.kind}, {"physical_id", link.physical_id}});
    log.push_back(pattern.note);
    log.push_back("单 flit 包；固定种子 " + std::to_string(r.seed) + "；统计窗口 (" +
                  std::to_string(r.begin) + ", " + std::to_string(r.end) + "]");
    for (double rate : r.rates) {
        const auto point_start = Clock::now();
        auto events = generate(r, pattern, rate);
        const double generate_ms = milliseconds(point_start);
        const auto output = device.run(events);
        const auto summary_start = Clock::now();
        auto point = summarize(r, pattern, rate, events, output, device.links());
        point["timing"]["generate_ms"] = generate_ms;
        point["timing"]["statistics_ms"] = milliseconds(summary_start);
        point["timing"]["total_ms"] = milliseconds(point_start);
        log.push_back("rate=" + std::to_string(rate) + ", packets=" + std::to_string(events.size()) +
                      ", latency=" + point["latency_cycles"].dump() + ", accepted=" + point["accepted_throughput"].dump());
        series.push_back(std::move(point));
    }
    double baseline = 0, maximum = 0;
    unsigned successful = 0;
    for (const auto &point : series) if (point["ok"].get<bool>()) {
        const double latency = point["latency_cycles"].get<double>();
        if (successful++ == 0) baseline = latency;
        baseline = std::min(baseline, latency); maximum = std::max(maximum, latency);
    }
    Json saturation = nullptr;
    for (const auto &point : series) if (point["ok"].get<bool>()) {
        if (point["unstable"].get<bool>() || point["latency_cycles"].get<double>() > 2 * baseline) {
            saturation = point["injection_rate"]; break;
        }
    }
    if (successful != series.size()) warnings.push_back("部分采样点没有测量包；可增加采样周期。");
    if (r.model_source == "synthetic") warnings.push_back("Studio 当前使用合成模型数据；本次 NoC 执行来自真实 FPGA。");
    const Json rho = r.l_max > 1e-6 ? Json(1.0 / r.l_max) : Json(nullptr);
    Json metrics{{"runs", series.size()}, {"successful_runs", successful}, {"saturation_rate", saturation},
                 {"base_latency_cycles", successful ? Json(baseline) : Json(nullptr)}, {"max_latency_cycles", maximum},
                 {"nodes", r.mesh.rows * r.mesh.cols}, {"rows", r.mesh.rows}, {"cols", r.mesh.cols},
                 {"flavor", "FPGA trace / 2 VC / depth 8"}, {"topology_exact", true},
                 {"routing", r.routing}, {"logical_order", r.mesh.transform & noc::Transpose ? "XY" : "YX"},
                 {"model_terminals", r.terminals.size()}, {"injection_scope", pattern.scope},
                 {"normalization_nodes", pattern.normalization_nodes}, {"active_sources", pattern.rows.size()},
                 {"packet_flits", 1}, {"seed", r.seed}, {"measurement_begin", r.begin}, {"measurement_end", r.end},
                 {"links", std::move(links)}, {"link_stat_columns", {"flits", "heads", "blocked", "contended"}},
                 {"link_stats_scope", "whole_trace_including_warmup_and_drain"}};
    Json comparison{{"model_B_star_gbps", r.bandwidth}, {"model_l_star_max", r.l_max}, {"model_l_star_mean", r.l_mean},
                    {"model_rho_sat", rho}, {"sim_rho_sat", saturation},
                    {"sim_base_latency_cycles", successful ? Json(baseline) : Json(nullptr)}, {"topology_exact", true},
                    {"topology_note", "逻辑二维 mesh 精确嵌入物理 8×8，坐标转换不保持端口仲裁优先级"},
                    {"soundness", "仅提供有限窗口测量；尚未校准模型路由与稳态条件，不自动判定 soundness"},
                    {"tightness", "饱和标记是排队增长或时延超过基线两倍的观测点"},
                    {"unit_note", "注入/接收率按声明的源节点集合归一化；100 MHz 是物理时钟，不换算为业务 Gbps"},
                    {"discipline", "时延包含源排队；吞吐取固定窗口；链路计数包含预热和排空"},
                    {"verdict", "真实 FPGA trace 测量"}};
    Json config = j;
    config["seed"] = r.seed; config["routing"] = r.routing; config["rates"] = r.rates;
    config["packet_flits"] = 1; config["transform"] = r.mesh.transform;
    return {{"backend", "fpga"}, {"source", "real"}, {"ok", successful > 0}, {"metrics", std::move(metrics)},
            {"series", std::move(series)}, {"comparison", std::move(comparison)}, {"config_text", config.dump(2)},
            {"command", "libnoc_studio.so.1 : noc_studio_v1_run"}, {"stdout_tail", ""}, {"log", std::move(log)},
            {"warnings", std::move(warnings)}, {"elapsed_ms", milliseconds(started)}};
}
void encode(const Json &j, char **out) {
    const auto text = j.dump();
    auto *buffer = new char[text.size() + 1];
    std::memcpy(buffer, text.c_str(), text.size() + 1);
    *out = buffer;
}
} // namespace

extern "C" {
int32_t noc_studio_v1_run(const char *request, char **out) {
    if (!out) return noc::BadConfig;
    *out = nullptr;
    int32_t code = noc::BadConfig;
    try {
        require(request != nullptr, "Missing JSON request");
        encode(run(Json::parse(request)), out); return 0;
    } catch (const noc::Error &e) {
        code = e.code;
        try { encode({{"error", e.what()}, {"code", code}}, out); } catch (...) {}
    } catch (const std::bad_alloc &) {
        code = noc::NoMemory;
    } catch (const std::exception &e) {
        try { encode({{"error", e.what()}, {"code", code}}, out); } catch (...) {}
    } catch (...) { code = noc::IoError; }
    return code;
}
void noc_studio_v1_free(char *response) { delete[] response; }
const char *noc_studio_v1_capabilities() {
    return R"json({
      "topology_modes":["mesh"], "max_rows":8, "max_cols":8,
      "routing_options":[
        {"value":"dor","label":"DOR · XY"},
        {"value":"valiant_terminal","label":"Valiant · terminal 中间节点"},
        {"value":"valiant","label":"Valiant · 全 mesh 中间节点"}],
      "traffic_options":[
        {"value":"worst_perm","label":"最差置换（模型 D*）"},
        {"value":"custom","label":"OD 权重矩阵"},
        {"value":"uniform","label":"uniform · 均匀随机"},
        {"value":"randperm","label":"randperm · 随机无自环置换"},
        {"value":"bitcomp","label":"bitcomp · 镜像节点"},
        {"value":"transpose","label":"transpose · 方形 mesh 转置"},
        {"value":"bitrev","label":"bitrev · 位反转（2 的幂节点数）"},
        {"value":"shuffle","label":"shuffle · 位轮转（2 的幂节点数）"},
        {"value":"tornado","label":"tornado · 双维偏移"},
        {"value":"neighbor","label":"neighbor · 相邻节点"},
        {"value":"diagonal","label":"diagonal · 对角节点"},
        {"value":"hotspot","label":"hotspot · 中心节点热点"}],
      "kind":"trace", "vc_num":2, "buffer_depth":8, "packet_flits":1
    })json";
}
} // extern C

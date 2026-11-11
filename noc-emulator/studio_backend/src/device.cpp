#include "device.hpp"
#include <algorithm>
#include <bit>
#include <cerrno>
#include <chrono>
#include <cstring>
#include <fcntl.h>
#include <sys/file.h>
#include <thread>
#include <unistd.h>

namespace noc {
namespace {
using Clock = std::chrono::steady_clock;
uint64_t ns(Clock::time_point start) {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(Clock::now() - start).count();
}
constexpr uint64_t control = 0x100000, event_base = control + 4096;
constexpr uint64_t magic = 0x314c554d45434f4eULL, ddr_limit = 0x80000000;
constexpr size_t chunk_bytes = 1 << 20;
constexpr uint64_t page(uint64_t n) { return (n + 4095) & ~uint64_t(4095); }
struct WireEvent { uint64_t time; uint16_t dst, mid; uint32_t flits; };
struct Command { uint64_t magic; uint32_t count, routing; };
struct Status { uint16_t state, error; uint32_t count; uint64_t cycle; };
struct Completion { uint64_t key, cycle; };
static_assert(std::endian::native == std::endian::little);
static_assert(sizeof(WireEvent) == 16 && sizeof(Command) == 16 && sizeof(Status) == 16);
static_assert(sizeof(Completion) == 16 && sizeof(Counters) == 32);

auto buffer(size_t bytes) {
    void *p = nullptr;
    if (posix_memalign(&p, 4096, std::max<size_t>(bytes, 16))) throw std::bad_alloc();
    return std::unique_ptr<void, decltype(&std::free)>(p, &std::free);
}
uint8_t map_node(uint32_t id, const Mesh &o) {
    uint32_t r = id / o.cols, c = id % o.cols, rows = o.rows, cols = o.cols;
    if (o.transform & Transpose) { std::swap(r, c); std::swap(rows, cols); }
    if (o.transform & FlipRows) r = rows - 1 - r;
    if (o.transform & FlipCols) c = cols - 1 - c;
    return uint8_t((r + o.origin_row) * 8 + c + o.origin_col);
}
uint16_t physical_link(uint16_t a, uint16_t b, uint8_t kind) {
    if (kind == 0) return a;
    if (kind == 2) return 288 + a;
    if (a / 8 == b / 8) return 64 + 2 * (a / 8 * 7 + std::min(a, b) % 8) + (a > b);
    return 176 + 2 * std::min(a, b) + (a > b);
}
int open_device(const char *env, const char *fallback, int mode) {
    const char *path = std::getenv(env);
    if (!path) path = fallback;
    const int fd = ::open(path, mode | O_CLOEXEC);
    if (fd < 0) throw Error(IoError, std::string(path) + ": " + std::strerror(errno));
    return fd;
}
} // namespace

Device::Fd::~Fd() { if (value >= 0) ::close(value); }

Device::Device(const Mesh &o) : scratch_(buffer(chunk_bytes + 4096)), routing_(o.routing) {
    h2c_.value = open_device("NOC_XDMA_H2C", "/dev/xdma0_h2c_0", O_RDWR);
    if (::flock(h2c_.value, LOCK_EX | LOCK_NB)) {
        const int code = errno;
        throw Error(code == EWOULDBLOCK ? Busy : IoError,
                    "FPGA device lock: " + std::string(std::strerror(code)));
    }
    c2h_.value = open_device("NOC_XDMA_C2H", "/dev/xdma0_c2h_0", O_RDONLY);
    const uint32_t n = o.rows * o.cols;
    for (uint32_t i = 0; i < n; ++i) map_[i] = map_node(i, o);
    auto add = [&](uint16_t a, uint16_t b, uint8_t kind) {
        links_.push_back({a, b, physical_link(map_[a], map_[b], kind), kind});
    };
    for (uint32_t i = 0; i < n; ++i) add(i, i, 0);
    for (uint32_t r = 0; r < o.rows; ++r)
        for (uint32_t c = 0; c + 1 < o.cols; ++c) {
            const uint16_t a = r * o.cols + c;
            add(a, a + 1, 1); add(a + 1, a, 1);
        }
    for (uint32_t r = 0; r + 1 < o.rows; ++r)
        for (uint32_t c = 0; c < o.cols; ++c) {
            const uint16_t a = r * o.cols + c;
            add(a, a + o.cols, 1); add(a + o.cols, a, 1);
        }
    for (uint32_t i = 0; i < n; ++i) add(i, i, 2);
}

void Device::dma(bool write, uint64_t address, void *data, size_t bytes) {
    auto *p = static_cast<std::byte *>(data);
    while (bytes) {
        const size_t size = std::min(bytes, chunk_bytes);
        auto *scratch = static_cast<std::byte *>(scratch_.get()) + (address & 4095);
        const bool direct = (reinterpret_cast<uintptr_t>(p) & 4095) == (address & 4095);
        auto *transfer = direct ? p : scratch;
        if (write && !direct) std::memcpy(transfer, p, size);
        size_t done = 0;
        while (done < size) {
            const ssize_t rc = write ? ::pwrite(h2c_.value, transfer + done, size - done, address + done)
                                     : ::pread(c2h_.value, transfer + done, size - done, address + done);
            if (rc < 0 && errno == EINTR) continue;
            if (rc <= 0 || (rc % 16) != 0) {
                const std::string detail = rc < 0 ? std::strerror(errno) : "short or unaligned transfer";
                throw Error(IoError, std::string(write ? "XDMA write: " : "XDMA read: ") + detail);
            }
            done += size_t(rc);
        }
        if (!write && !direct) std::memcpy(p, transfer, size);
        address += size; p += size; bytes -= size;
    }
}

Result Device::run(std::span<const Event> events) {
    const auto prepare_start = Clock::now();
    const uint64_t completion_address = page(event_base + events.size() * 16);
    const uint64_t stats_address = page(completion_address + events.size() * 16);
    if (page(stats_address + 352 * 32) > ddr_limit)
        throw Error(Capacity, "Trace and results exceed the 2 GiB DDR region");
    const auto count = uint32_t(events.size());
    std::array<uint32_t, 64> counts{}, cursors{};
    for (const auto &e : events) ++counts[map_[e.src]];
    for (size_t i = 1; i < 64; ++i) cursors[i] = cursors[i - 1] + counts[i - 1];
    auto image = buffer(size_t(count) * 16);
    auto *wire = static_cast<WireEvent *>(image.get());
    std::vector<uint32_t> key_to_input(count);
    // Stable scatter: physical source groups, preserving each source's times.
    for (uint32_t i = 0; i < count; ++i) {
        const auto &e = events[i];
        const auto key = cursors[map_[e.src]]++;
        key_to_input[key] = i;
        wire[key] = {e.send_time, map_[e.dst], map_[routing_ ? e.mid : e.dst], e.flit_num};
    }
    Result result;
    result.timings.prepare_ns = ns(prepare_start);
    const auto submitted = Clock::now();
    // RUNNING is published before command clear: read command FIRST.
    Command pending{};
    Status status{};
    dma(false, control, &pending, 16);
    dma(false, control + 16, &status, 16);
    if (pending.magic || pending.count || pending.routing || status.state == 2)
        throw Error(Busy, "FPGA has a running or pending command");
    if (status.state != 1 && status.state != 3 && status.state != 4)
        throw Error(FpgaError, "FPGA status is not initialized; check the loaded firmware");
    status = {1, 0, 0, 0};
    dma(true, control + 16, &status, 16);
    dma(true, control + 32, counts.data(), sizeof(counts));
    dma(true, event_base, image.get(), size_t(count) * 16);
    image.reset();
    const auto command_start = Clock::now();
    result.timings.upload_ns = ns(submitted);
    Command command{magic, count, routing_};
    dma(true, control, &command, 16);
    for (;;) {
        dma(false, control + 16, &status, 16);
        if (status.state == 3 || status.state == 4) break;
        if (status.state != 1 && status.state != 2)
            throw Error(FpgaError, "Invalid FPGA state during wait");
        if (Clock::now() - command_start >= std::chrono::seconds(60))
            throw Error(Timeout, "FPGA wait timed out; hardware job is still running");
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    if (status.state == 4) throw Error(FpgaError, "FPGA error code " + std::to_string(status.error));
    if (status.count != count) throw Error(FpgaError, "FPGA completion count mismatch");
    result.timings.command_to_done_ns = ns(command_start);
    result.logical_cycle = status.cycle;
    result.completion_cycles.resize(count);
    // Read exactly the occupied bytes; padding can contain uninitialized DDR ECC words.
    size_t remaining = size_t(count) * 16;
    uint64_t address = completion_address;
    while (remaining) {
        const auto size = std::min(remaining, chunk_bytes);
        auto *records = static_cast<Completion *>(scratch_.get());
        auto started = Clock::now();
        dma(false, address, records, size);
        result.timings.download_ns += ns(started);
        started = Clock::now();
        for (size_t i = 0; i < size / 16; ++i) {
            if (records[i].key >= count) throw Error(FpgaError, "Completion key out of range");
            result.completion_cycles[key_to_input[records[i].key]] = records[i].cycle;
        }
        result.timings.decode_ns += ns(started);
        address += size; remaining -= size;
    }
    const auto started = Clock::now();
    dma(false, stats_address, result.physical_counters.data(), sizeof(result.physical_counters));
    result.timings.download_ns += ns(started);
    result.timings.submit_to_result_ns = ns(submitted);
    return result;
}
} // namespace noc

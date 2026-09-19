/*
 * karing-HM 基本 VPN 数据面
 * 读 tun 虚拟网卡 fd → 解析 IPv4 → TCP/UDP 直连目标（进程已被 protectProcessNet 保护，
 * socket 流量天然绕过 VPN 避免回环）→ 回包重写 IP/TCP/UDP 头写回 tun。
 *
 * v0.2：最小可用（IPv4 only；TCP 维护基础 seq/ack 映射；UDP 简单映射）。
 */
#include "napi/native_api.h"
#include <cstring>
#include <cstdint>
#include <cstdio>
#include <unistd.h>
#include <fcntl.h>
#include <poll.h>
#include <netinet/in.h>
#include <netinet/ip.h>
#include <netinet/tcp.h>
#include <netinet/udp.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <arpa/inet.h>
#include <pthread.h>
#include <time.h>
#include <map>
#include <mutex>

#define LOG_TAG "karingVpn"
#define MAX_PKT 4096
#define MAX_FLOWS 512

// ---------------- 日志 ----------------
#include <hilog/log.h>
#define LOGE(...) OH_LOG_Print(LOG_APP, LOG_ERROR, 0x15b0, LOG_TAG, __VA_ARGS__)
#define LOGI(...) OH_LOG_Print(LOG_APP, LOG_INFO, 0x15b0, LOG_TAG, __VA_ARGS__)

// ---------------- 网络头结构（手动布局，避免字节序歧义） ----------------
#pragma pack(push, 1)
struct Ip4Hdr {
    uint8_t ver_ihl;
    uint8_t tos;
    uint16_t total_len;
    uint16_t id;
    uint16_t frag_off;
    uint8_t ttl;
    uint8_t proto;
    uint16_t checksum;
    uint32_t src;
    uint32_t dst;
};
struct TcpHdr {
    uint16_t sport;
    uint16_t dport;
    uint32_t seq;
    uint32_t ack;
    uint8_t off_flags;
    uint8_t flags;
    uint16_t window;
    uint16_t checksum;
    uint16_t urg;
};
struct UdpHdr {
    uint16_t sport;
    uint16_t dport;
    uint16_t len;
    uint16_t checksum;
};
#pragma pack(pop)

// ---------------- 流表 ----------------
struct FlowKey {
    uint32_t src;
    uint32_t dst;
    uint16_t sport;
    uint16_t dport;
    uint8_t proto;
    bool operator<(const FlowKey &o) const {
        if (src != o.src) return src < o.src;
        if (dst != o.dst) return dst < o.dst;
        if (sport != o.sport) return sport < o.sport;
        if (dport != o.dport) return dport < o.dport;
        return proto < o.proto;
    }
};

struct Flow {
    int fd = -1;
    // TCP 方向映射：client(入 tun) <-> server(出向 socket)
    uint32_t clientIsn = 0;       // 客户端 ISN（收到 SYN 时记录）
    uint32_t serverIsn = 0;       // 我们为回包选择的 ISN
    uint32_t clientSent = 0;      // 已从 client 转发的 payload 字节（不含 SYN）
    uint32_t serverSent = 0;      // 已从 server 转发的 payload 字节
    uint8_t finClient = 0;
    uint8_t finServer = 0;
    uint8_t tcpState = 0;         // 0=未建 1=已建 2=关闭
};

static int g_tunFd = -1;
static volatile bool g_running = false;
static pthread_t g_thread = 0;
static std::mutex g_flowMutex;
static std::map<FlowKey, Flow> g_flows;

// ---------------- 校验和 ----------------
static uint16_t checksum(const uint8_t *data, size_t len, uint32_t sum = 0) {
    size_t i = 0;
    for (; i + 1 < len; i += 2) {
        sum += ((uint16_t)data[i] << 8) | data[i + 1];
    }
    if (i < len) {
        sum += (uint16_t)data[i] << 8;
    }
    while (sum >> 16) {
        sum = (sum & 0xffff) + (sum >> 16);
    }
    return (uint16_t)~sum;
}

// pseudo header checksum for tcp/udp
static uint16_t tcpudp_checksum(uint32_t src, uint32_t dst, uint8_t proto,
                                const uint8_t *seg, size_t segLen) {
    uint32_t sum = 0;
    sum += (src >> 16) & 0xffff;
    sum += src & 0xffff;
    sum += (dst >> 16) & 0xffff;
    sum += dst & 0xffff;
    sum += proto;
    sum += (uint16_t)segLen;
    return checksum(seg, segLen, sum);
}

// ---------------- 写回 tun ----------------
static bool writeTun(const uint8_t *pkt, size_t len) {
    if (g_tunFd < 0) return false;
    ssize_t n = write(g_tunFd, pkt, len);
    return n > 0;
}

// 构造 IPv4+TCP 包写回 tun（server → client 方向）
static void writeTcpToClient(uint32_t srcIp, uint32_t dstIp, uint16_t sport, uint16_t dport,
                             uint32_t seq, uint32_t ack, uint8_t flags,
                             const uint8_t *payload, size_t payloadLen, uint16_t window) {
    uint8_t buf[MAX_PKT];
    if (20 + 20 + payloadLen > sizeof(buf)) return;
    Ip4Hdr *ip = (Ip4Hdr *)buf;
    TcpHdr *tcp = (TcpHdr *)(buf + 20);
    memset(ip, 0, 20);
    ip->ver_ihl = 0x45;
    ip->total_len = htons(20 + 20 + (uint16_t)payloadLen);
    ip->id = htons((uint16_t)(seq & 0xffff));
    ip->ttl = 64;
    ip->proto = IPPROTO_TCP;
    ip->src = srcIp;
    ip->dst = dstIp;
    memset(tcp, 0, 20);
    tcp->sport = htons(sport);
    tcp->dport = htons(dport);
    tcp->seq = htonl(seq);
    tcp->ack = htonl(ack);
    tcp->off_flags = 0x50;
    tcp->flags = flags;
    tcp->window = htons(window);
    if (payloadLen > 0) {
        memcpy(buf + 40, payload, payloadLen);
    }
    tcp->checksum = tcpudp_checksum(srcIp, dstIp, IPPROTO_TCP, buf + 20, 20 + payloadLen);
    ip->checksum = checksum(buf, 20);
    writeTun(buf, 20 + 20 + payloadLen);
}

// 构造 IPv4+UDP 包写回 tun
static void writeUdpToClient(uint32_t srcIp, uint32_t dstIp, uint16_t sport, uint16_t dport,
                             const uint8_t *payload, size_t payloadLen) {
    uint8_t buf[MAX_PKT];
    if (20 + 8 + payloadLen > sizeof(buf)) return;
    Ip4Hdr *ip = (Ip4Hdr *)buf;
    UdpHdr *udp = (UdpHdr *)(buf + 20);
    memset(ip, 0, 20);
    ip->ver_ihl = 0x45;
    ip->total_len = htons(20 + 8 + (uint16_t)payloadLen);
    ip->id = htons((uint16_t)((srcIp ^ dstIp) & 0xffff));
    ip->ttl = 64;
    ip->proto = IPPROTO_UDP;
    ip->src = srcIp;
    ip->dst = dstIp;
    udp->sport = htons(sport);
    udp->dport = htons(dport);
    udp->len = htons((uint16_t)(8 + payloadLen));
    udp->checksum = 0;
    if (payloadLen > 0) {
        memcpy(buf + 28, payload, payloadLen);
    }
    udp->checksum = tcpudp_checksum(srcIp, dstIp, IPPROTO_UDP, buf + 20, 8 + payloadLen);
    ip->checksum = checksum(buf, 20);
    writeTun(buf, 20 + 8 + payloadLen);
}

// ---------------- TCP 流处理 ----------------
static void handleTcpPacket(const uint8_t *pkt, size_t len) {
    if (len < 20) return;
    const Ip4Hdr *ip = (const Ip4Hdr *)pkt;
    size_t ipHdrLen = (size_t)((ip->ver_ihl & 0x0f) * 4);
    if (ipHdrLen < 20 || len < ipHdrLen + 20) return;
    const TcpHdr *tcp = (const TcpHdr *)(pkt + ipHdrLen);
    size_t tcpHdrLen = (size_t)(((tcp->off_flags >> 4) & 0x0f) * 4);
    if (tcpHdrLen < 20 || len < ipHdrLen + tcpHdrLen) return;

    uint32_t src = ip->src;
    uint32_t dst = ip->dst;
    uint16_t sport = ntohs(tcp->sport);
    uint16_t dport = ntohs(tcp->dport);
    uint32_t seq = ntohl(tcp->seq);
    uint8_t flags = tcp->flags;
    const uint8_t *payload = pkt + ipHdrLen + tcpHdrLen;
    size_t payloadLen = len - ipHdrLen - tcpHdrLen;
    uint16_t window = ntohs(tcp->window);
    if (window == 0) window = 65535;

    FlowKey key{src, dst, sport, dport, IPPROTO_TCP};
    std::lock_guard<std::mutex> lock(g_flowMutex);

    auto it = g_flows.find(key);
    if (it == g_flows.end()) {
        // 只对 SYN 建流
        if (!(flags & 0x02)) return;
        if (g_flows.size() >= MAX_FLOWS) return;
        int fd = socket(AF_INET, SOCK_STREAM, 0);
        if (fd < 0) return;
        // 允许被 VPN 外发：socket 由本进程创建，进程已被 protectProcessNet 保护
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = dst;
        sa.sin_port = htons(dport);
        // 非阻塞 connect + 短暂等待握手（内核自行完成，先轮询 POLLOUT）
        int fl = fcntl(fd, F_GETFL, 0);
        fcntl(fd, F_SETFL, fl | O_NONBLOCK);
        int cr = connect(fd, (struct sockaddr *)&sa, sizeof(sa));
        if (cr != 0 && errno != EINPROGRESS) {
            close(fd);
            return;
        }
        struct pollfd cpf;
        cpf.fd = fd;
        cpf.events = POLLOUT;
        if (poll(&cpf, 1, 300) <= 0 || (cpf.revents & (POLLERR | POLLHUP))) {
            close(fd);
            return;
        }
        Flow f;
        f.fd = fd;
        f.clientIsn = seq;
        f.serverIsn = 0x12340000u + (uint32_t)((uintptr_t)fd * 2654435761u);
        f.serverSent = 1; // SYN 消耗 1 序号
        f.tcpState = 1;
        g_flows[key] = f;
        // 回 SYN-ACK（payload 通常为空）
        writeTcpToClient(dst, src, dport, sport, f.serverIsn, f.clientIsn + 1,
                         0x12 /* SYN|ACK */, nullptr, 0, window);
        return;
    }

    Flow &f = it->second;
    if (f.tcpState != 1) return;

    if (flags & 0x04 /* RST */ || flags & 0x01 /* FIN */) {
        if (flags & 0x01) f.finClient = 1;
        f.clientSent += payloadLen;
        shutdown(f.fd, SHUT_WR);
        // 回应 ACK + FIN-ACK
        writeTcpToClient(dst, src, dport, sport, f.serverIsn + f.serverSent,
                         f.clientIsn + 1 + f.clientSent, 0x10 /* ACK */, nullptr, 0, window);
        if (flags & 0x04) {
            close(f.fd);
            f.tcpState = 2;
            g_flows.erase(it);
        }
        return;
    }

    // 数据转发：写 socket（内核 socket 自己管理发向 server 的 seq）
    if (payloadLen > 0) {
        ssize_t n = send(f.fd, payload, payloadLen, MSG_NOSIGNAL);
        if (n > 0) {
            f.clientSent += (uint32_t)n;
        }
    }
    // 及时 ACK（可选，依赖对端重传）
    writeTcpToClient(dst, src, dport, sport, f.serverIsn + f.serverSent,
                     f.clientIsn + 1 + f.clientSent, 0x10 /* ACK */, nullptr, 0, window);
}

// ---------------- UDP 流处理 ----------------
static void handleUdpPacket(const uint8_t *pkt, size_t len) {
    if (len < 20) return;
    const Ip4Hdr *ip = (const Ip4Hdr *)pkt;
    size_t ipHdrLen = (size_t)((ip->ver_ihl & 0x0f) * 4);
    if (ipHdrLen < 20 || len < ipHdrLen + 8) return;
    const UdpHdr *udp = (const UdpHdr *)(pkt + ipHdrLen);
    uint16_t udpLen = ntohs(udp->len);
    if (udpLen < 8 || len < ipHdrLen + udpLen) return;

    uint32_t src = ip->src;
    uint32_t dst = ip->dst;
    uint16_t sport = ntohs(udp->sport);
    uint16_t dport = ntohs(udp->dport);
    const uint8_t *payload = pkt + ipHdrLen + 8;
    size_t payloadLen = udpLen - 8;

    FlowKey key{src, dst, sport, dport, IPPROTO_UDP};
    std::lock_guard<std::mutex> lock(g_flowMutex);

    auto it = g_flows.find(key);
    if (it == g_flows.end()) {
        if (g_flows.size() >= MAX_FLOWS) return;
        int fd = socket(AF_INET, SOCK_DGRAM, 0);
        if (fd < 0) return;
        struct sockaddr_in sa;
        memset(&sa, 0, sizeof(sa));
        sa.sin_family = AF_INET;
        sa.sin_addr.s_addr = dst;
        sa.sin_port = htons(dport);
        connect(fd, (struct sockaddr *)&sa, sizeof(sa)); // UDP connect 仅绑定对端
        Flow f;
        f.fd = fd;
        g_flows[key] = f;
        it = g_flows.find(key);
    }
    if (it == g_flows.end()) return;
    Flow &f = it->second;
    if (payloadLen > 0) {
        send(f.fd, payload, payloadLen, MSG_NOSIGNAL);
    }
}

// ---------------- 数据面主循环 ----------------
static void *vpnLoop(void *) {
    struct pollfd pfds[MAX_FLOWS + 1];
    uint8_t pkt[MAX_PKT];
    uint8_t tmp[MAX_PKT];
    uint64_t tunRx = 0;
    uint64_t sockRx = 0;
    uint64_t lastLog = 0;
    while (g_running) {
        if (g_tunFd < 0) {
            usleep(200000);
            continue;
        }
        // 周期统计日志（5s）
        uint64_t now = (uint64_t)time(nullptr);
        if (now - lastLog >= 5) {
            LOGI("stats tunRx=%{public}llu sockRx=%{public}llu flows=%{public}zu",
                 (unsigned long long)tunRx, (unsigned long long)sockRx, g_flows.size());
            lastLog = now;
        }
        // 组装 poll 集合
        int nfds = 0;
        pfds[nfds].fd = g_tunFd;
        pfds[nfds].events = POLLIN;
        nfds++;
        std::map<int, FlowKey> fdMap;
        {
            std::lock_guard<std::mutex> lock(g_flowMutex);
            for (auto &kv : g_flows) {
                if (nfds > MAX_FLOWS) break;
                pfds[nfds].fd = kv.second.fd;
                pfds[nfds].events = POLLIN;
                fdMap[kv.second.fd] = kv.first;
                nfds++;
            }
        }
        int r = poll(pfds, (nfds_t)nfds, 500);
        if (r <= 0) continue;

        // 读 tun
        if (pfds[0].revents & POLLIN) {
            ssize_t n = read(g_tunFd, pkt, sizeof(pkt));
            if (n > 0) {
                tunRx++;
                if ((pkt[0] & 0xf0) == 0x40 && (size_t)n >= 20) {
                    const Ip4Hdr *ip = (const Ip4Hdr *)pkt;
                    if (ip->proto == IPPROTO_TCP) {
                        handleTcpPacket(pkt, (size_t)n);
                    } else if (ip->proto == IPPROTO_UDP) {
                        handleUdpPacket(pkt, (size_t)n);
                    }
                }
            }
        }

        // 读各流 socket
        for (int i = 1; i < nfds; i++) {
            if (!(pfds[i].revents & (POLLIN | POLLERR | POLLHUP))) continue;
            int fd = pfds[i].fd;
            ssize_t n = recv(fd, tmp, sizeof(tmp) - 64, 0);
            if (n <= 0) {
                std::lock_guard<std::mutex> lock(g_flowMutex);
                auto fit = fdMap.find(fd);
                if (fit != fdMap.end()) {
                    auto git = g_flows.find(fit->second);
                    if (git != g_flows.end()) {
                        close(git->second.fd);
                        g_flows.erase(git);
                    }
                }
                continue;
            }
            sockRx++;
            std::lock_guard<std::mutex> lock(g_flowMutex);
            auto fit = fdMap.find(fd);
            if (fit == fdMap.end()) continue;
            auto git = g_flows.find(fit->second);
            if (git == g_flows.end()) continue;
            Flow &f = git->second;
            const FlowKey &k = fit->second;
            if (k.proto == IPPROTO_TCP) {
                writeTcpToClient(k.dst, k.src, k.dport, k.sport,
                                 f.serverIsn + f.serverSent,
                                 f.clientIsn + 1 + f.clientSent,
                                 0x18 /* PSH|ACK */, tmp, (size_t)n, 65535);
                f.serverSent += (uint32_t)n;
            } else {
                writeUdpToClient(k.dst, k.src, k.dport, k.sport, tmp, (size_t)n);
            }
        }
    }
    return nullptr;
}

// ---------------- N-API 导出 ----------------
static napi_value StartVpn(napi_env env, napi_callback_info info) {
    size_t argc = 1;
    napi_value args[1] = {nullptr};
    napi_get_cb_info(env, info, &argc, args, nullptr, nullptr);
    int32_t tunFd = -1;
    napi_get_value_int32(env, args[0], &tunFd);
    if (g_running) {
        g_running = false;
        pthread_join(g_thread, nullptr);
    }
    if (g_tunFd >= 0) {
        close(g_tunFd);
        g_tunFd = -1;
    }
    g_tunFd = tunFd;
    // 非阻塞读 tun
    int flags = fcntl(g_tunFd, F_GETFL, 0);
    fcntl(g_tunFd, F_SETFL, flags | O_NONBLOCK);
    g_running = true;
    pthread_create(&g_thread, nullptr, vpnLoop, nullptr);
    LOGI("startVpn tunFd=%{public}d", tunFd);
    napi_value ret;
    napi_create_int32(env, 0, &ret);
    return ret;
}

static napi_value StopVpn(napi_env env, napi_callback_info info) {
    g_running = false;
    if (g_thread) {
        pthread_join(g_thread, nullptr);
        g_thread = 0;
    }
    {
        std::lock_guard<std::mutex> lock(g_flowMutex);
        for (auto &kv : g_flows) {
            close(kv.second.fd);
        }
        g_flows.clear();
    }
    if (g_tunFd >= 0) {
        close(g_tunFd);
        g_tunFd = -1;
    }
    LOGI("stopVpn");
    napi_value ret;
    napi_create_int32(env, 0, &ret);
    return ret;
}

EXTERN_C_START
static napi_value Init(napi_env env, napi_value exports) {
    napi_property_descriptor desc[] = {
        {"startVpn", nullptr, StartVpn, nullptr, nullptr, nullptr, napi_default, nullptr},
        {"stopVpn", nullptr, StopVpn, nullptr, nullptr, nullptr, napi_default, nullptr},
    };
    napi_define_properties(env, exports, sizeof(desc) / sizeof(desc[0]), desc);
    return exports;
}
EXTERN_C_END

static napi_module demoModule = {
    .nm_version = 1,
    .nm_flags = 0,
    .nm_filename = nullptr,
    .nm_register_func = Init,
    .nm_modname = "karing_vpn",
    .nm_priv = ((void *)0),
    .reserved = {0},
};

extern "C" __attribute__((constructor)) void RegisterVpnModule(void) {
    napi_module_register(&demoModule);
}

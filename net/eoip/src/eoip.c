#include <arpa/inet.h>
#include <errno.h>
#include <fcntl.h>
#include <linux/if.h>
#include <linux/if_ether.h>
#include <linux/if_tun.h>
#include <linux/ip.h>
#include <netinet/in.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <time.h>
#include <unistd.h>

#define EOIP_LOOP_ETHERTYPE 0x88B5
#define EOIP_LOOP_MAGIC "E0LPv1"
#define EOIP_LOOP_MAGIC_LEN 6

static inline uint16_t eoip_to_le16(uint16_t v) {
#if __BYTE_ORDER__ == __ORDER_LITTLE_ENDIAN__
    return v;
#else
    return (uint16_t)((v << 8) | (v >> 8));
#endif
}

static inline uint16_t eoip_from_le16(uint16_t v) {
    return eoip_to_le16(v);
}

struct eoip_hdr {
    uint16_t gre_flags;
    uint16_t gre_proto;
    uint16_t len;
    uint16_t tid;
} __attribute__((packed));

static uint32_t next_probe_nonce(uint32_t prev, uint16_t tid) {
    uint32_t now = (uint32_t)time(NULL);
    uint32_t nonce = prev ^ (now + 0x9e3779b9u + ((uint32_t)tid << 16));
    if (nonce == 0)
        nonce = now ^ ((uint32_t)getpid() << 12) ^ tid;
    return nonce ? nonce : 1u;
}

static void get_if_hwaddr(const char *ifname, unsigned char out[6], uint16_t tid) {
    int fd;
    struct ifreq ifr;

    memset(out, 0, 6);

    fd = socket(AF_INET, SOCK_DGRAM, 0);
    if (fd < 0)
        goto fallback;

    memset(&ifr, 0, sizeof(ifr));
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(fd, SIOCGIFHWADDR, &ifr) == 0) {
        memcpy(out, ifr.ifr_hwaddr.sa_data, 6);
        close(fd);
        return;
    }
    close(fd);

fallback:
    out[0] = 0x02;
    out[1] = 0x00;
    out[2] = 0x00;
    out[3] = (unsigned char)((tid >> 8) & 0xff);
    out[4] = (unsigned char)(tid & 0xff);
    out[5] = (unsigned char)(getpid() & 0xff);
}

static int build_loop_probe(unsigned char *buf, size_t buflen,
                            const unsigned char srcmac[6], uint32_t nonce) {
    uint16_t ethertype = htons(EOIP_LOOP_ETHERTYPE);
    uint32_t nonce_be = htonl(nonce);

    if (buflen < 24)
        return -1;

    memset(buf, 0xff, 6);                   /* dst = ff:ff:ff:ff:ff:ff */
    memcpy(buf + 6, srcmac, 6);             /* src */
    memcpy(buf + 12, &ethertype, 2);        /* ethertype */
    memcpy(buf + 14, EOIP_LOOP_MAGIC, EOIP_LOOP_MAGIC_LEN);
    memcpy(buf + 20, &nonce_be, 4);
    return 24;
}

static int is_our_loop_probe(const unsigned char *payload, int payload_len, uint32_t nonce) {
    uint16_t ethertype;
    uint32_t rx_nonce;

    if (payload_len < 24)
        return 0;

    ethertype = (uint16_t)((payload[12] << 8) | payload[13]);
    if (ethertype != EOIP_LOOP_ETHERTYPE)
        return 0;

    if (memcmp(payload + 14, EOIP_LOOP_MAGIC, EOIP_LOOP_MAGIC_LEN) != 0)
        return 0;

    memcpy(&rx_nonce, payload + 20, sizeof(rx_nonce));
    rx_nonce = ntohl(rx_nonce);
    return rx_nonce == nonce;
}

int main(int argc, char *argv[]) {
    int tap_fd, net_fd;
    int dynamic, peer_set = 0;
    int keepalive_interval, dscp, df;
    int loop_protect, loop_disable_time, loop_send_interval;
    uint16_t tid;
    const char *ifname, *remote_ip, *local_ip, *output_dev;
    struct ifreq ifr;
    struct sockaddr_in addr;
    unsigned char srcmac[6];
    unsigned char buf[2048];
    struct eoip_hdr *hdr = (struct eoip_hdr *)buf;
    time_t last_keepalive = 0;
    time_t last_probe = 0;
    time_t blocked_until = 0;
    uint32_t probe_nonce = 0;

    if (argc < 4) {
        fprintf(stderr,
                "Uso: %s <ifname> <tid> <remote_ip> [dynamic] [local_ip] [output_dev] "
                "[keepalive_interval] [dscp] [df] [loop_protect] [loop_disable_time] "
                "[loop_send_interval]\n",
                argv[0]);
        return 1;
    }

    ifname = argv[1];
    tid = (uint16_t)atoi(argv[2]);
    remote_ip = argv[3];
    dynamic = (argc > 4) ? atoi(argv[4]) : 0;
    local_ip = (argc > 5 && argv[5] && argv[5][0]) ? argv[5] : NULL;
    output_dev = (argc > 6 && argv[6] && argv[6][0]) ? argv[6] : NULL;
    keepalive_interval = (argc > 7) ? atoi(argv[7]) : 3;
    dscp = (argc > 8) ? atoi(argv[8]) : -1;
    df = (argc > 9) ? atoi(argv[9]) : 0;
    loop_protect = (argc > 10) ? atoi(argv[10]) : 0;
    loop_disable_time = (argc > 11) ? atoi(argv[11]) : 5;
    loop_send_interval = (argc > 12) ? atoi(argv[12]) : 5;

    if (keepalive_interval < 0)
        keepalive_interval = 0;
    if (loop_disable_time < 1)
        loop_disable_time = 1;
    if (loop_send_interval < 1)
        loop_send_interval = 1;
    if (loop_protect != 1)
        loop_protect = 0;

    tap_fd = open("/dev/net/tun", O_RDWR);
    if (tap_fd < 0) {
        perror("open(/dev/net/tun)");
        return 1;
    }

    memset(&ifr, 0, sizeof(ifr));
    ifr.ifr_flags = IFF_TAP | IFF_NO_PI;
    strncpy(ifr.ifr_name, ifname, IFNAMSIZ - 1);
    if (ioctl(tap_fd, TUNSETIFF, (void *)&ifr) < 0) {
        perror("ioctl(TUNSETIFF)");
        close(tap_fd);
        return 1;
    }

    net_fd = socket(AF_INET, SOCK_RAW, 47); /* GRE */
    if (net_fd < 0) {
        perror("socket(AF_INET, SOCK_RAW, 47)");
        close(tap_fd);
        return 1;
    }

    if (dscp >= 0 && dscp <= 63) {
        int tos = dscp << 2;
        if (setsockopt(net_fd, IPPROTO_IP, IP_TOS, &tos, sizeof(tos)) < 0)
            perror("setsockopt(IP_TOS)");
    }

#ifdef IP_MTU_DISCOVER
    {
        int pmtudisc = df ? IP_PMTUDISC_DO : IP_PMTUDISC_DONT;
        if (setsockopt(net_fd, IPPROTO_IP, IP_MTU_DISCOVER, &pmtudisc, sizeof(pmtudisc)) < 0)
            perror("setsockopt(IP_MTU_DISCOVER)");
    }
#endif

    if (local_ip) {
        struct sockaddr_in laddr;
        memset(&laddr, 0, sizeof(laddr));
        laddr.sin_family = AF_INET;
        if (inet_pton(AF_INET, local_ip, &laddr.sin_addr) != 1) {
            fprintf(stderr, "local_ip invalido: %s\n", local_ip);
            close(net_fd);
            close(tap_fd);
            return 1;
        }
        if (bind(net_fd, (struct sockaddr *)&laddr, sizeof(laddr)) < 0) {
            perror("bind(local_ip)");
            close(net_fd);
            close(tap_fd);
            return 1;
        }
    }

    if (output_dev) {
        if (setsockopt(net_fd, SOL_SOCKET, SO_BINDTODEVICE, output_dev, strlen(output_dev) + 1) < 0) {
            perror("setsockopt(SO_BINDTODEVICE)");
            close(net_fd);
            close(tap_fd);
            return 1;
        }
    }

    memset(&addr, 0, sizeof(addr));
    addr.sin_family = AF_INET;
    if (inet_pton(AF_INET, remote_ip, &addr.sin_addr) != 1) {
        fprintf(stderr, "remote_ip invalido: %s\n", remote_ip);
        close(net_fd);
        close(tap_fd);
        return 1;
    }
    peer_set = 1;

    get_if_hwaddr(ifname, srcmac, tid);

    while (1) {
        int sel;
        fd_set fds;
        struct timeval tv;

        FD_ZERO(&fds);
        FD_SET(tap_fd, &fds);
        FD_SET(net_fd, &fds);
        tv.tv_sec = 1;
        tv.tv_usec = 0;

        sel = select((tap_fd > net_fd ? tap_fd : net_fd) + 1, &fds, NULL, NULL, &tv);
        if (sel < 0) {
            if (errno == EINTR)
                continue;
            perror("select");
            break;
        }

        if (sel == 0) {
            time_t now = time(NULL);

            if (peer_set && keepalive_interval > 0 && now - last_keepalive >= keepalive_interval) {
                hdr->gre_flags = htons(0x2001);
                hdr->gre_proto = htons(0x6400);
                hdr->len = htons(0);
                hdr->tid = eoip_to_le16(tid);
                sendto(net_fd, buf, sizeof(struct eoip_hdr), 0, (struct sockaddr *)&addr, sizeof(addr));
                last_keepalive = now;
            }

            if (loop_protect && peer_set && now >= blocked_until && now - last_probe >= loop_send_interval) {
                int frame_len;

                probe_nonce = next_probe_nonce(probe_nonce, tid);
                frame_len = build_loop_probe(buf + sizeof(struct eoip_hdr),
                                             sizeof(buf) - sizeof(struct eoip_hdr),
                                             srcmac, probe_nonce);
                if (frame_len > 0) {
                    hdr->gre_flags = htons(0x2001);
                    hdr->gre_proto = htons(0x6400);
                    hdr->len = htons((uint16_t)frame_len);
                    hdr->tid = eoip_to_le16(tid);
                    sendto(net_fd, buf, frame_len + (int)sizeof(struct eoip_hdr), 0,
                           (struct sockaddr *)&addr, sizeof(addr));
                    last_probe = now;
                }
            }
            continue;
        }

        if (FD_ISSET(tap_fd, &fds)) {
            int n;
            time_t now = time(NULL);

            n = read(tap_fd, buf + sizeof(struct eoip_hdr), sizeof(buf) - sizeof(struct eoip_hdr));
            if (n <= 0)
                continue;

            if (!peer_set || now < blocked_until)
                continue;

            hdr->gre_flags = htons(0x2001);
            hdr->gre_proto = htons(0x6400);
            hdr->len = htons((uint16_t)n);
            hdr->tid = eoip_to_le16(tid);
            sendto(net_fd, buf, n + (int)sizeof(struct eoip_hdr), 0, (struct sockaddr *)&addr, sizeof(addr));
        }

        if (FD_ISSET(net_fd, &fds)) {
            int n;
            int ip_hlen;
            int payload_len;
            unsigned char *payload;
            struct sockaddr_in src;
            socklen_t slen = sizeof(src);
            time_t now = time(NULL);
            struct eoip_hdr *r_hdr;

            n = recvfrom(net_fd, buf, sizeof(buf), 0, (struct sockaddr *)&src, &slen);
            if (n <= (int)sizeof(struct iphdr))
                continue;

            ip_hlen = (buf[0] & 0x0F) * 4;
            if (ip_hlen < (int)sizeof(struct iphdr))
                continue;
            if (n < ip_hlen + (int)sizeof(struct eoip_hdr))
                continue;

            r_hdr = (struct eoip_hdr *)(buf + ip_hlen);
            if (ntohs(r_hdr->gre_proto) != 0x6400)
                continue;
            if (eoip_from_le16(r_hdr->tid) != tid)
                continue;

            if (dynamic) {
                addr.sin_addr = src.sin_addr;
                peer_set = 1;
            } else if (src.sin_addr.s_addr != addr.sin_addr.s_addr) {
                continue;
            }

            payload = buf + ip_hlen + sizeof(struct eoip_hdr);
            payload_len = n - ip_hlen - (int)sizeof(struct eoip_hdr);

            if (loop_protect && payload_len > 0 && probe_nonce != 0 &&
                is_our_loop_probe(payload, payload_len, probe_nonce)) {
                blocked_until = now + loop_disable_time;
                fprintf(stderr, "loop-protect: loop detected on %s, blocking for %d seconds\n",
                        ifname, loop_disable_time);
                continue;
            }

            if (now < blocked_until)
                continue;

            if (payload_len > 0) {
                if (write(tap_fd, payload, payload_len) < 0 && errno != EAGAIN && errno != EINTR) {
                    perror("write(tap)");
                }
            } else if (peer_set) {
                /* Reply empty keepalive frames so RouterOS marks tunnel running */
                hdr->gre_flags = htons(0x2001);
                hdr->gre_proto = htons(0x6400);
                hdr->len = htons(0);
                hdr->tid = eoip_to_le16(tid);
                sendto(net_fd, buf, sizeof(struct eoip_hdr), 0,
                       (struct sockaddr *)&addr, sizeof(addr));
            }
        }
    }

    close(net_fd);
    close(tap_fd);
    return 0;
}

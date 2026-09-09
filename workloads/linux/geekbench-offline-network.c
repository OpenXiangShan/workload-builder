#define _GNU_SOURCE

#include <arpa/inet.h>
#include <dlfcn.h>
#include <errno.h>
#include <netdb.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <sys/socket.h>
#include <sys/sendfile.h>
#include <sys/types.h>
#include <sys/uio.h>
#include <unistd.h>

/*
 * Preview Geekbench builds insist on uploading their result. In an offline
 * guest, redirect their resolver and connection setup to an in-process
 * transport.
 */
static int offline_enabled(void)
{
    return 1;
}

static int (*real_getaddrinfo)(const char *, const char *,
                               const struct addrinfo *, struct addrinfo **);
static struct hostent *(*real_gethostbyname)(const char *);
static struct hostent *(*real_gethostbyname2)(const char *, int);
static int (*real_socket)(int, int, int);
static int (*real_socketpair)(int, int, int, int[2]);
static int (*real_connect)(int, const struct sockaddr *, socklen_t);
static ssize_t (*real_send)(int, const void *, size_t, int);
static ssize_t (*real_recv)(int, void *, size_t, int);
static ssize_t (*real_write)(int, const void *, size_t);
static ssize_t (*real_sendto)(int, const void *, size_t, int,
                              const struct sockaddr *, socklen_t);
static ssize_t (*real_sendmsg)(int, const struct msghdr *, int);
static ssize_t (*real_writev)(int, const struct iovec *, int);
static ssize_t (*real_sendfile64)(int, int, off_t *, size_t);
static ssize_t (*real_pread)(int, void *, size_t, off_t);
static ssize_t (*real_recvfrom)(int, void *, size_t, int,
                                struct sockaddr *, socklen_t *);
static ssize_t (*real_recvmsg)(int, struct msghdr *, int);
static ssize_t (*real_read)(int, void *, size_t);
static int (*real_close)(int);
static int (*real_shutdown)(int, int);
static int (*real_setsockopt)(int, int, int, const void *, socklen_t);
static int (*real_getsockopt)(int, int, int, void *, socklen_t *);

#define OFFLINE_FD_LIMIT 4096

static unsigned char fake_connection[OFFLINE_FD_LIMIT];
static int fake_peer[OFFLINE_FD_LIMIT];

struct capture_state {
    char *request;
    size_t capacity;
    size_t length;
    int scores_reported;
    int response_queued;
    size_t response_remaining;
    int request_dumped;
};

static struct capture_state captures[OFFLINE_FD_LIMIT];
static char *offline_host_aliases[] = { NULL };
static char *offline_host_addresses[2];
static struct in_addr offline_ipv4;
static struct in6_addr offline_ipv6;

static void resolve_real_symbols(void)
{
    if (!real_getaddrinfo)
        real_getaddrinfo = dlsym(RTLD_NEXT, "getaddrinfo");
    if (!real_gethostbyname)
        real_gethostbyname = dlsym(RTLD_NEXT, "gethostbyname");
    if (!real_gethostbyname2)
        real_gethostbyname2 = dlsym(RTLD_NEXT, "gethostbyname2");
    if (!real_socket)
        real_socket = dlsym(RTLD_NEXT, "socket");
    if (!real_socketpair)
        real_socketpair = dlsym(RTLD_NEXT, "socketpair");
    if (!real_connect)
        real_connect = dlsym(RTLD_NEXT, "connect");
    if (!real_send)
        real_send = dlsym(RTLD_NEXT, "send");
    if (!real_recv)
        real_recv = dlsym(RTLD_NEXT, "recv");
    if (!real_write)
        real_write = dlsym(RTLD_NEXT, "write");
    if (!real_sendto)
        real_sendto = dlsym(RTLD_NEXT, "sendto");
    if (!real_sendmsg)
        real_sendmsg = dlsym(RTLD_NEXT, "sendmsg");
    if (!real_writev)
        real_writev = dlsym(RTLD_NEXT, "writev");
    if (!real_sendfile64)
        real_sendfile64 = dlsym(RTLD_NEXT, "sendfile64");
    if (!real_pread)
        real_pread = dlsym(RTLD_NEXT, "pread");
    if (!real_recvfrom)
        real_recvfrom = dlsym(RTLD_NEXT, "recvfrom");
    if (!real_recvmsg)
        real_recvmsg = dlsym(RTLD_NEXT, "recvmsg");
    if (!real_read)
        real_read = dlsym(RTLD_NEXT, "read");
    if (!real_close)
        real_close = dlsym(RTLD_NEXT, "close");
    if (!real_shutdown)
        real_shutdown = dlsym(RTLD_NEXT, "shutdown");
    if (!real_setsockopt)
        real_setsockopt = dlsym(RTLD_NEXT, "setsockopt");
    if (!real_getsockopt)
        real_getsockopt = dlsym(RTLD_NEXT, "getsockopt");
}

static int json_number(const char *body, const char *key, long *value)
{
    const char *match = strstr(body, key);

    if (!match)
        return 0;
    match = strchr(match, ':');
    if (!match)
        return 0;
    *value = strtol(match + 1, NULL, 10);
    return 1;
}

static int request_content_length(const struct capture_state *state,
                                  size_t *length)
{
    const char *header = strcasestr(state->request, "Content-Length:");

    if (!header)
        return 0;
    *length = (size_t)strtoull(header + 15, NULL, 10);
    return 1;
}

static int request_complete(const struct capture_state *state)
{
    const char *body = strstr(state->request, "\r\n\r\n");
    size_t content_length;
    size_t header_length;

    if (!body)
        return 0;
    header_length = (size_t)(body + 4 - state->request);
    if (request_content_length(state, &content_length))
        return content_length <= SIZE_MAX - header_length &&
               state->length >= header_length + content_length;
    if (strcasestr(state->request, "Transfer-Encoding: chunked"))
        return strstr(body + 4, "\r\n0\r\n\r\n") != NULL;
    if (!strncmp(state->request, "GET ", 4) ||
        !strncmp(state->request, "HEAD ", 5) ||
        !strncmp(state->request, "DELETE ", 7))
        return 1;
    return 0;
}

static int ensure_capture_capacity(struct capture_state *state, size_t length)
{
    size_t required;
    size_t new_capacity;
    char *new_buffer;

    if (length > SIZE_MAX - state->length - 1)
        return 0;
    required = state->length + length + 1;
    if (required <= state->capacity)
        return 1;
    new_capacity = state->capacity ? state->capacity : 65536;
    while (new_capacity < required) {
        if (new_capacity > SIZE_MAX / 2) {
            new_capacity = required;
            break;
        }
        new_capacity *= 2;
    }
    new_buffer = realloc(state->request, new_capacity);
    if (!new_buffer)
        return 0;
    state->request = new_buffer;
    state->capacity = new_capacity;
    return 1;
}

static void report_scores(int fd, struct capture_state *state)
{
    long single_core = 0;
    long multi_core = 0;
    int have_single;
    int have_multi;

    if (fd < 0 || fd >= OFFLINE_FD_LIMIT || state != &captures[fd] ||
        state->scores_reported)
        return;
    state->request[state->length] = '\0';
    have_single = json_number(state->request, "\"single_core_score\"",
                              &single_core) ||
                  json_number(state->request, "\"score\"", &single_core);
    have_multi = json_number(state->request, "\"multi_core_score\"",
                             &multi_core) ||
                 json_number(state->request, "\"multicore_score\"",
                             &multi_core);
    if (have_single && have_multi) {
        printf("Single-Core Score: %ld\nMulti-Core Score: %ld\n",
               single_core, multi_core);
        fflush(stdout);
        state->scores_reported = 1;
    }
}

static void dump_request(int fd, struct capture_state *state)
{
    if (fd < 0 || fd >= OFFLINE_FD_LIMIT || state != &captures[fd] ||
        state->request_dumped)
        return;
    if (!state->request)
        return;
    state->request[state->length] = '\0';
    printf("Offline upload request (%zu bytes):\n", state->length);
    fwrite(state->request, 1, state->length, stdout);
    fputs("\nEnd offline upload request\n", stdout);
    fflush(stdout);
    report_scores(fd, state);
    state->request_dumped = 1;
    if (state->scores_reported)
        _exit(0);
}

static void queue_response(int fd, struct capture_state *state)
{
    static const char response[] =
        "HTTP/1.1 200 OK\r\n"
        "Content-Type: application/json\r\n"
        "Connection: keep-alive\r\n"
        "Content-Length: 131\r\n\r\n"
        "{\"status\":\"ok\",\"url\":\"http://127.0.0.1/\","
        "\"result_url\":\"http://127.0.0.1/\","
        "\"claim_url\":\"http://127.0.0.1/claim\","
        "\"message\":\"offline\"}";

    if (fd >= 0 && fd < OFFLINE_FD_LIMIT && fake_peer[fd] >= 0 &&
        state->request_dumped && !state->response_queued)
        state->response_remaining = sizeof(response) - 1;
    if (fd >= 0 && fd < OFFLINE_FD_LIMIT && fake_peer[fd] >= 0 &&
        state->request_dumped && !state->response_queued)
        real_write(fake_peer[fd], response, sizeof(response) - 1);
    if (fd >= 0 && fd < OFFLINE_FD_LIMIT && fake_peer[fd] >= 0 &&
        state->request_dumped)
        state->response_queued = 1;
}

int getaddrinfo(const char *node, const char *service,
                const struct addrinfo *hints, struct addrinfo **result)
{
    resolve_real_symbols();
    if (offline_enabled()) {
        struct addrinfo offline_hints;
        if (hints) {
            offline_hints = *hints;
            offline_hints.ai_family = AF_INET;
            return real_getaddrinfo("127.0.0.1", "8080", &offline_hints,
                                    result);
        }
        return real_getaddrinfo("127.0.0.1", "8080", NULL, result);
    }
    return real_getaddrinfo(node, service, hints, result);
}

static struct hostent *offline_hostent(int family)
{
    static struct hostent host;

    memset(&host, 0, sizeof(host));
    host.h_name = (char *)"localhost";
    host.h_aliases = offline_host_aliases;
    host.h_addrtype = family;
    if (family == AF_INET) {
        offline_ipv4.s_addr = htonl(INADDR_LOOPBACK);
        offline_host_addresses[0] = (char *)&offline_ipv4;
        host.h_length = sizeof(offline_ipv4);
    } else if (family == AF_INET6) {
        memset(&offline_ipv6, 0, sizeof(offline_ipv6));
        offline_ipv6.s6_addr[15] = 1;
        offline_host_addresses[0] = (char *)&offline_ipv6;
        host.h_length = sizeof(offline_ipv6);
    } else {
        h_errno = NO_DATA;
        return NULL;
    }
    offline_host_addresses[1] = NULL;
    host.h_addr_list = offline_host_addresses;
    return &host;
}

struct hostent *gethostbyname(const char *name)
{
    resolve_real_symbols();
    if (offline_enabled()) {
        (void)name;
        return offline_hostent(AF_INET);
    }
    return real_gethostbyname(name);
}

struct hostent *gethostbyname2(const char *name, int family)
{
    resolve_real_symbols();
    if (offline_enabled()) {
        (void)name;
        return offline_hostent(family);
    }
    return real_gethostbyname2(name, family);
}

int socket(int domain, int type, int protocol)
{
    int pair[2];

    resolve_real_symbols();
    if (offline_enabled() && (domain == AF_INET || domain == AF_INET6)) {
        if (real_socketpair(AF_UNIX, type, 0, pair) != 0)
            return -1;
        if (pair[0] >= OFFLINE_FD_LIMIT || pair[1] >= OFFLINE_FD_LIMIT) {
            real_close(pair[0]);
            real_close(pair[1]);
            errno = EMFILE;
            return -1;
        }
        fake_connection[pair[0]] = 1;
        fake_peer[pair[0]] = pair[1];
        free(captures[pair[0]].request);
        memset(&captures[pair[0]], 0, sizeof(captures[pair[0]]));
        return pair[0];
    }
    return real_socket(domain, type, protocol);
}

int connect(int sockfd, const struct sockaddr *addr, socklen_t addrlen)
{
    resolve_real_symbols();
    if (offline_enabled()) {
        if (sockfd >= 0 && sockfd < OFFLINE_FD_LIMIT && fake_connection[sockfd])
            return 0;
        (void)addr;
        (void)addrlen;
        errno = ECONNREFUSED;
        return -1;
    }
    return real_connect(sockfd, addr, addrlen);
}

ssize_t send(int sockfd, const void *buffer, size_t length, int flags)
{
    struct capture_state *state;
    size_t requested_length = length;

    resolve_real_symbols();
    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd])
        return real_send(sockfd, buffer, length, flags);
    state = &captures[sockfd];
    if (state->request_dumped && state->response_queued) {
        free(state->request);
        memset(state, 0, sizeof(*state));
    }
    if (!ensure_capture_capacity(state, length)) {
        errno = ENOMEM;
        return -1;
    }
    memcpy(state->request + state->length, buffer, length);
    state->length += length;
    state->request[state->length] = '\0';
    if (request_complete(state)) {
        dump_request(sockfd, state);
        queue_response(sockfd, state);
    }
    return (ssize_t)requested_length;
}

ssize_t write(int fd, const void *buffer, size_t length)
{
    resolve_real_symbols();
    if (!offline_enabled() || fd < 0 || fd >= OFFLINE_FD_LIMIT ||
        !fake_connection[fd])
        return real_write(fd, buffer, length);
    return send(fd, buffer, length, 0);
}

ssize_t recv(int sockfd, void *buffer, size_t length, int flags)
{
    struct capture_state *state;
    ssize_t received;

    resolve_real_symbols();
    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd])
        return real_recv(sockfd, buffer, length, flags);
    state = &captures[sockfd];
    if (state->response_queued && state->response_remaining == 0)
        return 0;
    received = real_recv(sockfd, buffer, length, flags);
    if (received > 0 && state->response_queued) {
        if ((size_t)received >= state->response_remaining)
            state->response_remaining = 0;
        else
            state->response_remaining -= (size_t)received;
    }
    return received;
}

ssize_t sendto(int sockfd, const void *buffer, size_t length, int flags,
               const struct sockaddr *address, socklen_t address_length)
{
    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd]) {
        resolve_real_symbols();
        return real_sendto(sockfd, buffer, length, flags, address,
                           address_length);
    }
    return send(sockfd, buffer, length, flags);
}

ssize_t sendmsg(int sockfd, const struct msghdr *message, int flags)
{
    ssize_t total = 0;
    int index;

    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd]) {
        resolve_real_symbols();
        return real_sendmsg(sockfd, message, flags);
    }
    for (index = 0; index < (int)message->msg_iovlen; ++index) {
        ssize_t sent = send(sockfd, message->msg_iov[index].iov_base,
                            message->msg_iov[index].iov_len, flags);
        if (sent < 0)
            return sent;
        total += sent;
    }
    return total;
}

ssize_t writev(int fd, const struct iovec *vectors, int count)
{
    ssize_t total = 0;
    int index;

    if (!offline_enabled() || fd < 0 || fd >= OFFLINE_FD_LIMIT ||
        !fake_connection[fd]) {
        resolve_real_symbols();
        return real_writev(fd, vectors, count);
    }
    for (index = 0; index < count; ++index) {
        ssize_t written = send(fd, vectors[index].iov_base,
                               vectors[index].iov_len, 0);
        if (written < 0)
            return written;
        total += written;
    }
    return total;
}

ssize_t sendfile64(int out_fd, int in_fd, off_t *offset, size_t count)
{
    unsigned char buffer[65536];
    size_t total = 0;

    resolve_real_symbols();
    if (!offline_enabled() || out_fd < 0 || out_fd >= OFFLINE_FD_LIMIT ||
        !fake_connection[out_fd])
        return real_sendfile64(out_fd, in_fd, offset, count);
    while (total < count) {
        size_t chunk = count - total;
        ssize_t read_count;

        if (chunk > sizeof(buffer))
            chunk = sizeof(buffer);
        if (offset)
            read_count = real_pread(in_fd, buffer, chunk, *offset + total);
        else
            read_count = real_read(in_fd, buffer, chunk);
        if (read_count <= 0)
            break;
        if (send(out_fd, buffer, (size_t)read_count, 0) != read_count)
            return total ? (ssize_t)total : -1;
        total += (size_t)read_count;
    }
    if (offset)
        *offset += (off_t)total;
    return (ssize_t)total;
}

ssize_t sendfile(int out_fd, int in_fd, off_t *offset, size_t count)
{
    return sendfile64(out_fd, in_fd, offset, count);
}

ssize_t recvfrom(int sockfd, void *buffer, size_t length, int flags,
                 struct sockaddr *address, socklen_t *address_length)
{
    resolve_real_symbols();
    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd])
        return real_recvfrom(sockfd, buffer, length, flags, address,
                             address_length);
    return real_recvfrom(sockfd, buffer, length, flags, address,
                         address_length);
}

ssize_t recvmsg(int sockfd, struct msghdr *message, int flags)
{
    resolve_real_symbols();
    if (!offline_enabled() || sockfd < 0 || sockfd >= OFFLINE_FD_LIMIT ||
        !fake_connection[sockfd]) {
        return real_recvmsg(sockfd, message, flags);
    }
    return real_recvmsg(sockfd, message, flags);
}

int setsockopt(int sockfd, int level, int option, const void *value,
               socklen_t value_length)
{
    resolve_real_symbols();
    if (offline_enabled() && sockfd >= 0 && sockfd < OFFLINE_FD_LIMIT &&
        fake_connection[sockfd])
        return 0;
    return real_setsockopt(sockfd, level, option, value, value_length);
}

int getsockopt(int sockfd, int level, int option, void *value,
               socklen_t *value_length)
{
    resolve_real_symbols();
    if (offline_enabled() && sockfd >= 0 && sockfd < OFFLINE_FD_LIMIT &&
        fake_connection[sockfd]) {
        if (value && value_length && *value_length >= sizeof(int)) {
            *(int *)value = 0;
            *value_length = sizeof(int);
        }
        return 0;
    }
    return real_getsockopt(sockfd, level, option, value, value_length);
}

ssize_t read(int fd, void *buffer, size_t length)
{
    resolve_real_symbols();
    if (!offline_enabled() || fd < 0 || fd >= OFFLINE_FD_LIMIT ||
        !fake_connection[fd])
        return real_read(fd, buffer, length);
    return real_read(fd, buffer, length);
}

int close(int fd)
{
    int peer = -1;
    struct capture_state *state;

    resolve_real_symbols();
    if (fd >= 0 && fd < OFFLINE_FD_LIMIT && fake_connection[fd]) {
        state = &captures[fd];
        dump_request(fd, state);
        queue_response(fd, state);
        peer = fake_peer[fd];
        fake_connection[fd] = 0;
        fake_peer[fd] = -1;
        if (peer >= 0)
            real_close(peer);
        free(state->request);
        memset(state, 0, sizeof(*state));
    }
    return real_close(fd);
}

int shutdown(int fd, int how)
{
    struct capture_state *state;

    resolve_real_symbols();
    if (fd >= 0 && fd < OFFLINE_FD_LIMIT && fake_connection[fd] &&
        how != SHUT_RD) {
        state = &captures[fd];
        dump_request(fd, state);
        queue_response(fd, state);
    }
    return real_shutdown(fd, how);
}

/*
 * Static file server for the speedometer workload, with the NEMU control
 * endpoints built in.
 *
 * Speedometer has to be served over HTTP rather than file:// because its
 * harness and every suite are ES modules, which Firefox refuses to load from a
 * file origin. Serving also has to happen inside the guest, since NEMU has no
 * network device and only loopback is available.
 *
 * The control endpoints exist so the benchmark itself decides where the
 * profiled region begins and ends. Issuing the NEMU trap here, rather than
 * forking /bin/nemu-trap from a CGI handler, keeps the process creation out of
 * the measured region.
 */

#ifndef _GNU_SOURCE
#define _GNU_SOURCE
#endif

#include <arpa/inet.h>
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <netinet/in.h>
#include <signal.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>

/* NEMU debug call codes; see the nemu_trap handler in NEMU's riscv64 sources. */
#define NEMU_NOTIFY_PROFILER 0x101
#define NEMU_EXIT_GOOD 0
#define NEMU_EXIT_BAD (-1)

#define REQUEST_MAX 8192
#define TRANSFER_CHUNK 65536
#define PATH_MAX_BYTES 4096

static const char *doc_root = ".";
static const char *results_path = NULL;
static int log_requests = 0;

/* Building for the host is supported so the serving logic can be exercised
 * against a real Speedometer tree before committing to a guest boot. The debug
 * call only exists on the target, so it degrades to a log line elsewhere. */
static void nemu_trap(long code)
{
#ifdef __riscv
    asm volatile("mv a0, %0; .word 0x0000006b" : : "r"(code) : "a0");
#else
    printf("nemu_trap %ld\n", code);
    fflush(stdout);
#endif
}

static const char *mime_type(const char *path)
{
    const char *dot = strrchr(path, '.');

    if (dot == NULL)
        return "application/octet-stream";

    /* Module scripts are subject to strict MIME checking: anything other than
     * a JavaScript type makes Firefox refuse to evaluate them. */
    if (!strcmp(dot, ".js") || !strcmp(dot, ".mjs"))
        return "text/javascript";
    if (!strcmp(dot, ".html") || !strcmp(dot, ".htm"))
        return "text/html";
    if (!strcmp(dot, ".css"))
        return "text/css";
    if (!strcmp(dot, ".json") || !strcmp(dot, ".map"))
        return "application/json";
    if (!strcmp(dot, ".svg"))
        return "image/svg+xml";
    if (!strcmp(dot, ".png"))
        return "image/png";
    if (!strcmp(dot, ".jpg") || !strcmp(dot, ".jpeg"))
        return "image/jpeg";
    if (!strcmp(dot, ".gif"))
        return "image/gif";
    if (!strcmp(dot, ".ico"))
        return "image/x-icon";
    if (!strcmp(dot, ".woff2"))
        return "font/woff2";
    if (!strcmp(dot, ".woff"))
        return "font/woff";
    if (!strcmp(dot, ".ttf"))
        return "font/ttf";
    if (!strcmp(dot, ".wasm"))
        return "application/wasm";
    if (!strcmp(dot, ".txt") || !strcmp(dot, ".md"))
        return "text/plain";
    return "application/octet-stream";
}

static void write_all(int fd, const char *data, size_t length)
{
    while (length > 0) {
        ssize_t written = write(fd, data, length);
        if (written <= 0) {
            if (written < 0 && errno == EINTR)
                continue;
            return;
        }
        data += written;
        length -= (size_t)written;
    }
}

static void send_header(int fd, const char *status, const char *type, long long length)
{
    char header[512];
    int header_length = snprintf(header, sizeof(header),
                                 "HTTP/1.1 %s\r\n"
                                 "Content-Type: %s\r\n"
                                 "Content-Length: %lld\r\n"
                                 "Cache-Control: no-store\r\n"
                                 "Connection: close\r\n"
                                 "\r\n",
                                 status, type, length);
    write_all(fd, header, (size_t)header_length);
}

/* The status line doubles as the body, which is all any client here needs. */
static void send_status(int fd, const char *status)
{
    size_t length = strlen(status);

    send_header(fd, status, "text/plain", (long long)length);
    write_all(fd, status, length);
}

/* Decode %XX escapes and cut the query string and fragment. */
static void normalize_target(char *target)
{
    char *out = target;
    char *in = target;

    while (*in != '\0' && *in != '?' && *in != '#') {
        if (in[0] == '%' && isxdigit((unsigned char)in[1]) && isxdigit((unsigned char)in[2])) {
            char hex[3] = { in[1], in[2], '\0' };
            *out++ = (char)strtol(hex, NULL, 16);
            in += 3;
        } else {
            *out++ = *in++;
        }
    }
    *out = '\0';
}

static int resolve_path(const char *target, char *resolved, size_t size)
{
    struct stat info;

    if (target[0] != '/' || strstr(target, "..") != NULL)
        return -1;
    if (snprintf(resolved, size, "%s%s", doc_root, target) >= (int)size)
        return -1;
    if (stat(resolved, &info) != 0)
        return -1;
    if (S_ISDIR(info.st_mode)) {
        size_t length = strlen(resolved);
        const char *separator = (length > 0 && resolved[length - 1] == '/') ? "" : "/";
        char with_index[PATH_MAX_BYTES];
        if (snprintf(with_index, sizeof(with_index), "%s%sindex.html", resolved, separator) >= (int)sizeof(with_index))
            return -1;
        if (stat(with_index, &info) != 0 || !S_ISREG(info.st_mode))
            return -1;
        if (snprintf(resolved, size, "%s", with_index) >= (int)size)
            return -1;
    } else if (!S_ISREG(info.st_mode)) {
        return -1;
    }
    return 0;
}

static void serve_file(int fd, const char *target, int body_wanted)
{
    char resolved[PATH_MAX_BYTES];
    struct stat info;
    int file;

    if (resolve_path(target, resolved, sizeof(resolved)) != 0) {
        send_status(fd, "404 Not Found");
        return;
    }

    file = open(resolved, O_RDONLY);
    if (file < 0 || fstat(file, &info) != 0) {
        if (file >= 0)
            close(file);
        send_status(fd, "404 Not Found");
        return;
    }

    send_header(fd, "200 OK", mime_type(resolved), (long long)info.st_size);

    if (body_wanted) {
        char chunk[TRANSFER_CHUNK];
        ssize_t got;
        while ((got = read(file, chunk, sizeof(chunk))) > 0)
            write_all(fd, chunk, (size_t)got);
    }
    close(file);
}

static void store_results(const char *body, size_t length)
{
    if (results_path != NULL) {
        FILE *out = fopen(results_path, "w");
        if (out != NULL) {
            fwrite(body, 1, length, out);
            fclose(out);
        }
    }
    /* The console is the only channel that survives the run, so mirror the
     * payload there even when the results file was written. */
    fputs("speedometer-results-begin\n", stdout);
    fwrite(body, 1, length, stdout);
    fputs("\nspeedometer-results-end\n", stdout);
    fflush(stdout);
}

/* Control endpoints whose whole job is to acknowledge and then issue a debug
 * call. roi-start arms SimPoint profiling, so everything before it - browser
 * startup, profile creation, font cache construction, the first page load -
 * stays outside the profiled region. The other two stop the machine. */
static const struct {
    const char *path;
    long code;
    const char *note;
} CONTROL_TRAPS[] = {
    { "/control/roi-start", NEMU_NOTIFY_PROFILER, NULL },
    { "/control/finish",    NEMU_EXIT_GOOD,       NULL },
    { "/control/abort",     NEMU_EXIT_BAD,        "speedometer-run-failed\n" },
};

/* The results payload is larger than a request header, so it usually arrives
 * across several reads rather than whole in the first one. */
static void handle_results(int fd, const char *buffer, size_t used, char *body)
{
    const char *field = strcasestr(buffer, "\r\ncontent-length:");
    size_t present = used - (size_t)(body - buffer);
    size_t expected = present;
    char *complete;

    if (field != NULL)
        expected = (size_t)strtoul(field + strlen("\r\ncontent-length:"), NULL, 10);

    if (expected <= present) {
        store_results(body, expected);
        send_status(fd, "200 OK");
        return;
    }

    complete = (char *)malloc(expected + 1);
    if (complete == NULL) {
        send_status(fd, "500 Internal Server Error");
        return;
    }
    memcpy(complete, body, present);
    while (present < expected) {
        ssize_t got = read(fd, complete + present, expected - present);
        if (got <= 0)
            break;
        present += (size_t)got;
    }
    complete[present] = '\0';
    store_results(complete, present);
    free(complete);
    send_status(fd, "200 OK");
}

static void handle_connection(int fd)
{
    char buffer[REQUEST_MAX];
    char *header_end = NULL;
    size_t used = 0;
    char method[16];
    char target[2048];

    while (used < sizeof(buffer) - 1 && header_end == NULL) {
        ssize_t got = read(fd, buffer + used, sizeof(buffer) - 1 - used);
        if (got <= 0)
            return;
        used += (size_t)got;
        buffer[used] = '\0';
        header_end = strstr(buffer, "\r\n\r\n");
    }
    if (header_end == NULL)
        return;

    if (sscanf(buffer, "%15s %2047s", method, target) != 2) {
        send_status(fd, "400 Bad Request");
        return;
    }
    normalize_target(target);

    if (log_requests) {
        printf("req %s %s\n", method, target);
        fflush(stdout);
    }

    for (size_t i = 0; i < sizeof(CONTROL_TRAPS) / sizeof(CONTROL_TRAPS[0]); i++) {
        if (strcmp(target, CONTROL_TRAPS[i].path) != 0)
            continue;
        send_status(fd, "200 OK");
        if (CONTROL_TRAPS[i].note != NULL)
            fputs(CONTROL_TRAPS[i].note, stdout);
        fflush(stdout);
        nemu_trap(CONTROL_TRAPS[i].code);
        return;
    }

    if (!strcmp(target, "/control/results")) {
        handle_results(fd, buffer, used, header_end + 4);
        return;
    }

    if (!strcmp(method, "GET"))
        serve_file(fd, target, 1);
    else if (!strcmp(method, "HEAD"))
        serve_file(fd, target, 0);
    else
        send_status(fd, "405 Method Not Allowed");
}

int main(int argc, char *argv[])
{
    int port = 8000;
    int listener;
    int reuse = 1;
    struct sockaddr_in address;

    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--root") && i + 1 < argc)
            doc_root = argv[++i];
        else if (!strcmp(argv[i], "--port") && i + 1 < argc)
            port = atoi(argv[++i]);
        else if (!strcmp(argv[i], "--results") && i + 1 < argc)
            results_path = argv[++i];
        else if (!strcmp(argv[i], "--log-requests"))
            log_requests = 1;
        else {
            fprintf(stderr, "usage: %s --root DIR [--port N] [--results PATH] [--log-requests]\n", argv[0]);
            return 1;
        }
    }

    /* Connections are handled in child processes, so a slow or speculative
     * connection cannot stall the ones carrying benchmark assets. */
    signal(SIGCHLD, SIG_IGN);
    signal(SIGPIPE, SIG_IGN);

    listener = socket(AF_INET, SOCK_STREAM, 0);
    if (listener < 0) {
        perror("socket");
        return 1;
    }
    setsockopt(listener, SOL_SOCKET, SO_REUSEADDR, &reuse, sizeof(reuse));

    memset(&address, 0, sizeof(address));
    address.sin_family = AF_INET;
    address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
    address.sin_port = htons((uint16_t)port);

    if (bind(listener, (struct sockaddr *)&address, sizeof(address)) != 0) {
        perror("bind");
        return 1;
    }
    if (listen(listener, 128) != 0) {
        perror("listen");
        return 1;
    }

    printf("bench-httpd serving %s on 127.0.0.1:%d\n", doc_root, port);
    fflush(stdout);

    for (;;) {
        int client = accept(listener, NULL, NULL);
        if (client < 0) {
            if (errno == EINTR)
                continue;
            perror("accept");
            break;
        }
        pid_t child = fork();
        if (child == 0) {
            close(listener);
            handle_connection(client);
            close(client);
            _exit(0);
        }
        close(client);
    }
    return 0;
}

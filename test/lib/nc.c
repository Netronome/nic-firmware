#include <sys/types.h>
#include <sys/socket.h>
#include <sys/stat.h>
#include <sys/mman.h>
#include <netinet/in.h>
#include <netdb.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <assert.h>
#include <ctype.h>

/* ============================ CCAN COMPILER ============================= */
/* CC0 (Public domain) - see LICENSE file for details */

#ifndef COLD
#if HAVE_ATTRIBUTE_COLD
/**
 * COLD - a function is unlikely to be called.
 *
 * Used to mark an unlikely code path and optimize appropriately.
 * It is usually used on logging or error routines.
 *
 * Example:
 * static void COLD moan(const char *reason)
 * {
 *	fprintf(stderr, "Error: %s (%s)\n", reason, strerror(errno));
 * }
 */
#define COLD __attribute__((__cold__))
#else
#define COLD
#endif
#endif

#ifndef NORETURN
#if HAVE_ATTRIBUTE_NORETURN
/**
 * NORETURN - a function does not return
 *
 * Used to mark a function which exits; useful for suppressing warnings.
 *
 * Example:
 * static void NORETURN fail(const char *reason)
 * {
 *	fprintf(stderr, "Error: %s (%s)\n", reason, strerror(errno));
 *	exit(1);
 * }
 */
#define NORETURN __attribute__((__noreturn__))
#else
#define NORETURN
#endif
#endif

#ifndef PRINTF_FMT
#if HAVE_ATTRIBUTE_PRINTF
/**
 * PRINTF_FMT - a function takes printf-style arguments
 * @nfmt: the 1-based number of the function's format argument.
 * @narg: the 1-based number of the function's first variable argument.
 *
 * This allows the compiler to check your parameters as it does for printf().
 *
 * Example:
 * void PRINTF_FMT(2,3) my_printf(const char *prefix, const char *fmt, ...);
 */
#define PRINTF_FMT(nfmt, narg) \
	__attribute__((format(__printf__, nfmt, narg)))
#else
#define PRINTF_FMT(nfmt, narg)
#endif
#endif

#ifndef CONST_FUNCTION
#if HAVE_ATTRIBUTE_CONST
/**
 * CONST_FUNCTION - a function's return depends only on its argument
 *
 * This allows the compiler to assume that the function will return the exact
 * same value for the exact same arguments.  This implies that the function
 * must not use global variables, or dereference pointer arguments.
 */
#define CONST_FUNCTION __attribute__((__const__))
#else
#define CONST_FUNCTION
#endif

#ifndef PURE_FUNCTION
#if HAVE_ATTRIBUTE_PURE
/**
 * PURE_FUNCTION - a function is pure
 *
 * A pure function is one that has no side effects other than it's return value
 * and uses no inputs other than it's arguments and global variables.
 */
#define PURE_FUNCTION __attribute__((__pure__))
#else
#define PURE_FUNCTION
#endif
#endif
#endif

#if HAVE_ATTRIBUTE_UNUSED
#ifndef UNNEEDED
/**
 * UNNEEDED - a variable/function may not be needed
 *
 * This suppresses warnings about unused variables or functions, but tells
 * the compiler that if it is unused it need not emit it into the source code.
 *
 * Example:
 * // With some preprocessor options, this is unnecessary.
 * static UNNEEDED int counter;
 *
 * // With some preprocessor options, this is unnecessary.
 * static UNNEEDED void add_to_counter(int add)
 * {
 *	counter += add;
 * }
 */
#define UNNEEDED __attribute__((__unused__))
#endif

#ifndef NEEDED
#if HAVE_ATTRIBUTE_USED
/**
 * NEEDED - a variable/function is needed
 *
 * This suppresses warnings about unused variables or functions, but tells
 * the compiler that it must exist even if it (seems) unused.
 *
 * Example:
 *	// Even if this is unused, these are vital for debugging.
 *	static NEEDED int counter;
 *	static NEEDED void dump_counter(void)
 *	{
 *		printf("Counter is %i\n", counter);
 *	}
 */
#define NEEDED __attribute__((__used__))
#else
/* Before used, unused functions and vars were always emitted. */
#define NEEDED __attribute__((__unused__))
#endif
#endif

#ifndef UNUSED
/**
 * UNUSED - a parameter is unused
 *
 * Some compilers (eg. gcc with -W or -Wunused) warn about unused
 * function parameters.  This suppresses such warnings and indicates
 * to the reader that it's deliberate.
 *
 * Example:
 *	// This is used as a callback, so needs to have this prototype.
 *	static int some_callback(void *unused UNUSED)
 *	{
 *		return 0;
 *	}
 */
#define UNUSED __attribute__((__unused__))
#endif
#else
#ifndef UNNEEDED
#define UNNEEDED
#endif
#ifndef NEEDED
#define NEEDED
#endif
#ifndef UNUSED
#define UNUSED
#endif
#endif

#ifndef IS_COMPILE_CONSTANT
#if HAVE_BUILTIN_CONSTANT_P
/**
 * IS_COMPILE_CONSTANT - does the compiler know the value of this expression?
 * @expr: the expression to evaluate
 *
 * When an expression manipulation is complicated, it is usually better to
 * implement it in a function.  However, if the expression being manipulated is
 * known at compile time, it is better to have the compiler see the entire
 * expression so it can simply substitute the result.
 *
 * This can be done using the IS_COMPILE_CONSTANT() macro.
 *
 * Example:
 *	enum greek { ALPHA, BETA, GAMMA, DELTA, EPSILON };
 *
 *	// Out-of-line version.
 *	const char *greek_name(enum greek greek);
 *
 *	// Inline version.
 *	static inline const char *_greek_name(enum greek greek)
 *	{
 *		switch (greek) {
 *		case ALPHA: return "alpha";
 *		case BETA: return "beta";
 *		case GAMMA: return "gamma";
 *		case DELTA: return "delta";
 *		case EPSILON: return "epsilon";
 *		default: return "**INVALID**";
 *		}
 *	}
 *
 *	// Use inline if compiler knows answer.  Otherwise call function
 *	// to avoid copies of the same code everywhere.
 *	#define greek_name(g)						\
 *		 (IS_COMPILE_CONSTANT(greek) ? _greek_name(g) : greek_name(g))
 */
#define IS_COMPILE_CONSTANT(expr) __builtin_constant_p(expr)
#else
/* If we don't know, assume it's not. */
#define IS_COMPILE_CONSTANT(expr) 0
#endif
#endif

#ifndef WARN_UNUSED_RESULT
#if HAVE_WARN_UNUSED_RESULT
/**
 * WARN_UNUSED_RESULT - warn if a function return value is unused.
 *
 * Used to mark a function where it is extremely unlikely that the caller
 * can ignore the result, eg realloc().
 *
 * Example:
 * // buf param may be freed by this; need return value!
 * static char *WARN_UNUSED_RESULT enlarge(char *buf, unsigned *size)
 * {
 *	return realloc(buf, (*size) *= 2);
 * }
 */
#define WARN_UNUSED_RESULT __attribute__((__warn_unused_result__))
#else
#define WARN_UNUSED_RESULT
#endif
#endif

/* ============================ CCAN ERR/NOERR ============================ */
#include <stdarg.h>
#include <stdio.h>
#include <errno.h>
#include <string.h>
#include <stdlib.h>

static const char *progname = "unknown program";

void err_set_progname(const char *name)
{
	progname = name;
}

void NORETURN err(int eval, const char *fmt, ...)
{
	int err_errno = errno;
	va_list ap;

	fprintf(stderr, "%s: ", progname);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, ": %s\n", strerror(err_errno));
	exit(eval);
}

void NORETURN errx(int eval, const char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, "%s: ", progname);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, "\n");
	exit(eval);
}

void warn(const char *fmt, ...)
{
	int err_errno = errno;
	va_list ap;

	fprintf(stderr, "%s: ", progname);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, ": %s\n", strerror(err_errno));
}

void warnx(const char *fmt, ...)
{
	va_list ap;

	fprintf(stderr, "%s: ", progname);
	va_start(ap, fmt);
	vfprintf(stderr, fmt, ap);
	va_end(ap);
	fprintf(stderr, "\n");
}

/* CC0 (Public domain) - see LICENSE file for details */
#include <unistd.h>
#include <errno.h>
#include <stdlib.h>

int close_noerr(int fd)
{
	int saved_errno = errno, ret;

	if (close(fd) != 0)
		ret = errno;
	else
		ret = 0;

	errno = saved_errno;
	return ret;
}

int fclose_noerr(FILE *fp)
{
	int saved_errno = errno, ret;

	if (fclose(fp) != 0)
		ret = errno;
	else
		ret = 0;

	errno = saved_errno;
	return ret;
}

int unlink_noerr(const char *pathname)
{
	int saved_errno = errno, ret;

	if (unlink(pathname) != 0)
		ret = errno;
	else
		ret = 0;

	errno = saved_errno;
	return ret;
}

void free_noerr(void *p)
{
	int saved_errno = errno;
	free(p);
	errno = saved_errno;
}

/* ======================= end of CCAN ERR ==============================*/

/* ========================== CCAN NET ================================= */
/* Licensed under BSD-MIT - see LICENSE file for details */
#include <poll.h>
#include <string.h>
#include <stdlib.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <stdbool.h>
#include <netinet/in.h>
#include <assert.h>

struct addrinfo *net_client_lookup(const char *hostname,
				   const char *service,
				   int family,
				   int socktype)
{
	struct addrinfo hints;
	struct addrinfo *res;

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = family;
	hints.ai_socktype = socktype;
	hints.ai_flags = 0;
	hints.ai_protocol = 0;

	if (getaddrinfo(hostname, service, &hints, &res) != 0)
		return NULL;

	return res;
}

static bool set_nonblock(int fd, bool nonblock)
{
	long flags;

	flags = fcntl(fd, F_GETFL);
	if (flags == -1)
		return false;

	if (nonblock)
		flags |= O_NONBLOCK;
	else
		flags &= ~(long)O_NONBLOCK;

	return (fcntl(fd, F_SETFL, flags) == 0);
}

static int start_connect(const struct addrinfo *addr, bool *immediate)
{
	int fd;

	*immediate = false;

	fd = socket(addr->ai_family, addr->ai_socktype, addr->ai_protocol);
	if (fd == -1)
		return fd;

	if (!set_nonblock(fd, true))
		goto close;

	if (connect(fd, addr->ai_addr, addr->ai_addrlen) == 0) {
		/* Immediate connect. */
		*immediate = true;
		return fd;
	}

	if (errno == EINPROGRESS)
		return fd;

close:
	close_noerr(fd);
	return -1;
}


int net_connect_async(const struct addrinfo *addrinfo, struct pollfd pfds[2])
{
	const struct addrinfo *addr[2] = { NULL, NULL };
	unsigned int i;

	pfds[0].fd = pfds[1].fd = -1;
	pfds[0].events = pfds[1].events = POLLOUT;

	/* Give IPv6 a slight advantage, by trying it first. */
	for (; addrinfo; addrinfo = addrinfo->ai_next) {
		switch (addrinfo->ai_family) {
		case AF_INET:
			addr[1] = addrinfo;
			break;
		case AF_INET6:
			addr[0] = addrinfo;
			break;
		default:
			continue;
		}
	}

	/* In case we found nothing. */
	errno = ENOENT;
	for (i = 0; i < 2; i++) {
		bool immediate;

		if (!addr[i])
			continue;

		pfds[i].fd = start_connect(addr[i], &immediate);
		if (immediate) {
			if (pfds[!i].fd != -1)
				close(pfds[!i].fd);
			if (!set_nonblock(pfds[i].fd, false)) {
				close_noerr(pfds[i].fd);
				return -1;
			}
			return pfds[i].fd;
		}
	}

	if (pfds[0].fd != -1 || pfds[1].fd != -1)
		errno = EINPROGRESS;
	return -1;
}

void net_connect_abort(struct pollfd pfds[2])
{
	unsigned int i;

	for (i = 0; i < 2; i++) {
		if (pfds[i].fd != -1)
			close_noerr(pfds[i].fd);
		pfds[i].fd = -1;
	}
}

int net_connect_complete(struct pollfd pfds[2])
{
	unsigned int i;

	assert(pfds[0].fd != -1 || pfds[1].fd != -1);

	for (i = 0; i < 2; i++) {
		int err;
		socklen_t errlen = sizeof(err);

		if (pfds[i].fd == -1)
			continue;
		if (pfds[i].revents & POLLHUP) {
			/* Linux gives this if connecting to local
			 * non-listening port */
			close(pfds[i].fd);
			pfds[i].fd = -1;
			if (pfds[!i].fd == -1) {
				errno = ECONNREFUSED;
				return -1;
			}
			continue;
		}
		if (!(pfds[i].revents & POLLOUT))
			continue;

		if (getsockopt(pfds[i].fd, SOL_SOCKET, SO_ERROR, &err,
			       &errlen) != 0) {
			net_connect_abort(pfds);
			return -1;
		}
		if (err == 0) {
			/* Don't hand them non-blocking fd! */
			if (!set_nonblock(pfds[i].fd, false)) {
				net_connect_abort(pfds);
				return -1;
			}
			/* Close other one. */
			if (pfds[!i].fd != -1)
				close(pfds[!i].fd);
			return pfds[i].fd;
		}
	}

	/* Still going... */
	errno = EINPROGRESS;
	return -1;
}

int net_connect(const struct addrinfo *addrinfo)
{
	struct pollfd pfds[2];
	int sockfd;

	sockfd = net_connect_async(addrinfo, pfds);
	/* Immediate connect or error is easy. */
	if (sockfd >= 0 || errno != EINPROGRESS)
		return sockfd;

	while (poll(pfds, 2, -1) != -1) {
		sockfd = net_connect_complete(pfds);
		if (sockfd >= 0 || errno != EINPROGRESS)
			return sockfd;
	}

	net_connect_abort(pfds);
	return -1;
}

struct addrinfo *net_server_lookup(const char *service,
				   int family,
				   int socktype)
{
	struct addrinfo *res, hints;

	memset(&hints, 0, sizeof(hints));
	hints.ai_family = family;
	hints.ai_socktype = socktype;
	hints.ai_flags = AI_PASSIVE;
	hints.ai_protocol = 0;

	if (getaddrinfo(NULL, service, &hints, &res) != 0)
		return NULL;

	return res;
}

static bool should_listen(const struct addrinfo *addrinfo)
{
#ifdef SOCK_SEQPACKET
	if (addrinfo->ai_socktype == SOCK_SEQPACKET)
		return true;
#endif
	return (addrinfo->ai_socktype == SOCK_STREAM);
}

static int make_listen_fd(const struct addrinfo *addrinfo)
{
	int fd, on = 1;

	fd = socket(addrinfo->ai_family, addrinfo->ai_socktype,
		    addrinfo->ai_protocol);
	if (fd < 0)
		return -1;

	setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &on, sizeof(on));
	if (bind(fd, addrinfo->ai_addr, addrinfo->ai_addrlen) != 0)
		goto fail;

	if (should_listen(addrinfo) && listen(fd, 5) != 0)
		goto fail;
	return fd;

fail:
	close_noerr(fd);
	return -1;
}

int net_bind(const struct addrinfo *addrinfo, int fds[2])
{
	const struct addrinfo *ipv6 = NULL;
	const struct addrinfo *ipv4 = NULL;
	unsigned int num;

	if (addrinfo->ai_family == AF_INET)
		ipv4 = addrinfo;
	else if (addrinfo->ai_family == AF_INET6)
		ipv6 = addrinfo;

	if (addrinfo->ai_next) {
		if (addrinfo->ai_next->ai_family == AF_INET)
			ipv4 = addrinfo->ai_next;
		else if (addrinfo->ai_next->ai_family == AF_INET6)
			ipv6 = addrinfo->ai_next;
	}

	num = 0;
	/* Take IPv6 first, since it might bind to IPv4 port too. */
	if (ipv6) {
		if ((fds[num] = make_listen_fd(ipv6)) >= 0)
			num++;
		else
			ipv6 = NULL;
	}
	if (ipv4) {
		if ((fds[num] = make_listen_fd(ipv4)) >= 0)
			num++;
		else
			ipv4 = NULL;
	}
	if (num == 0)
		return -1;

	return num;
}

/* ========================== end of CCAN NET ============================== */

#define WRITE_SZ	0xffff
#define SND_BUF_SZ	(WRITE_SZ * 16)

int main(int argc, char **argv)
{
	bool wants_v6;
	int fd, sock;
	int snd_buf = SND_BUF_SZ;
	struct stat s;
	const char *p, *end;
	struct addrinfo *addr;

	if (argc < 4) {
		fprintf(stderr, "Usage: %s <host> <port> <file> [-6]\n",
			argv[0]);
		exit(1);
	}

	wants_v6 = argc > 4 && !strcmp(argv[4], "-6");

	fd = open(argv[3], O_RDONLY);
	if (fd < 0)
		err(1, "Unable to open file %s", argv[3]);

	if (fstat(fd, &s))
		err(1, "Unable to fstat file %s", argv[3]);

	p = mmap(NULL, s.st_size, PROT_READ, MAP_PRIVATE, fd, 0);
	if (p == MAP_FAILED)
		err(1, "Unable to mmap file %s", argv[3]);
	end = p + s.st_size;

	/* network stuff */
	addr = net_client_lookup(argv[1], argv[2],
				 wants_v6 ? AF_INET6 : AF_INET, SOCK_STREAM);
        if (!addr)
                err(1, "Failed to look up %s", argv[1]);

        sock = net_connect(addr);
        if (sock < 0)
                err(1, "Failed to connect to %s", argv[1]);
        freeaddrinfo(addr);

	if (setsockopt(sock, SOL_SOCKET, SO_SNDBUF, &snd_buf, sizeof(snd_buf)))
		err(1, "Failed to change SNDBUF");

	while (p < end) {
		write(sock, p, end - p < WRITE_SZ ? end - p : WRITE_SZ);
		p += WRITE_SZ;
	}

	return 0;
}

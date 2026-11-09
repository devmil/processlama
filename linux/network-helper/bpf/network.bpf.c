// SPDX-License-Identifier: GPL-2.0-only

#include <linux/bpf.h>
#include <bpf/bpf_helpers.h>

#define AF_INET_VALUE 2
#define AF_INET6_VALUE 10
#define MSG_PEEK_VALUE 2

struct sock_msg_length_args {
    __u64 common_fields;
    void *socket;
    __u16 family;
    __u16 protocol;
    __s32 result;
    __s32 flags;
};

struct network_counter {
    __u64 bytes_in;
    __u64 bytes_out;
};

struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 65536);
    __type(key, __u32);
    __type(value, struct network_counter);
} counters SEC(".maps");

static __always_inline int account_bytes(struct sock_msg_length_args *context, __u8 inbound)
{
    struct network_counter zero = {};
    struct network_counter *counter;
    __u32 tgid;

    if (context->result <= 0)
        return 0;
    if (context->family != AF_INET_VALUE && context->family != AF_INET6_VALUE)
        return 0;
    if (inbound && (context->flags & MSG_PEEK_VALUE))
        return 0;

    tgid = bpf_get_current_pid_tgid() >> 32;
    if (tgid == 0)
        return 0;
    counter = bpf_map_lookup_elem(&counters, &tgid);
    if (!counter) {
        bpf_map_update_elem(&counters, &tgid, &zero, BPF_NOEXIST);
        counter = bpf_map_lookup_elem(&counters, &tgid);
    }
    if (!counter)
        return 0;

    if (inbound)
        __sync_fetch_and_add(&counter->bytes_in, (__u64)context->result);
    else
        __sync_fetch_and_add(&counter->bytes_out, (__u64)context->result);
    return 0;
}

SEC("tracepoint/sock/sock_send_length")
int processlama_sock_send_length(struct sock_msg_length_args *context)
{
    return account_bytes(context, 0);
}

SEC("tracepoint/sock/sock_recv_length")
int processlama_sock_recv_length(struct sock_msg_length_args *context)
{
    return account_bytes(context, 1);
}

char LICENSE[] SEC("license") = "GPL";

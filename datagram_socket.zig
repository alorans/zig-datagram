//! Pretty good single file Zig 0.14.1 wrapper for Unix domain datagram sockets.
const std = @import("std");
const assert = std.debug.assert;
const builtin = @import("builtin");

// Comptime precondition: operating system is Unix-based, should have datagram sockets
comptime {
    const os = builtin.target.os.tag;
    assert(std.Target.Os.Tag.isBSD(os) or std.Target.Os.Tag.isDarwin(os) or os == .linux or os == .solaris);
}

// Max universally supported datagram size is 2Kb
pub const BUFFER_SIZE = 2048;
pub const Buffer = [BUFFER_SIZE]u8;

/// Unix domain datagram socket sender.
pub const Sender = struct {
    sockfd: std.posix.socket_t,

    pub fn init() !Sender {
        const sockfd = try std.posix.socket(
            std.posix.AF.UNIX,
            std.posix.SOCK.DGRAM | std.posix.SOCK.CLOEXEC,
            0,
        );
        errdefer std.posix.close(sockfd); // good to have for the future
        return .{ .sockfd = sockfd };
    }

    pub fn deinit(self: Sender) void {
        std.posix.close(self.sockfd);
    }

    /// Returns the number of bytes sent.
    pub fn sendto(
        self: Sender,
        buffer: []const u8,
        addr: std.net.Address,
    ) !u32 {
        assert(buffer.len <= BUFFER_SIZE); // Precondition

        // sendto will return SendError.MessageTooBig in the case of a buffer overun.
        const sent_bytes = try std.posix.sendto(
            self.sockfd,
            buffer,
            0,
            &addr.any,
            addr.getOsSockLen(),
        );
        assert(sent_bytes == buffer.len); // Invariant

        return @intCast(sent_bytes);
    }
};

/// Unix domain datagram socket receiver.
pub const Receiver = struct {
    sender: Sender,
    addr: std.net.Address, // receive from here

    // We only have one poll error type because multiple unexpected poll events are possible to occur at once
    const ReceiverError = error{UnexpectedPollEvent};

    pub fn init(
        file_path: []const u8,
    ) !Receiver {
        // Remove possible stale socket file.
        // Don't use std.fs.deleteFileAbsolute because a socket is not a regular file.
        std.posix.unlink(file_path) catch |err| switch (err) {
            std.posix.UnlinkError.FileNotFound => {}, // File not found is the expected case, ignore it.
            else => return err,
        };
        errdefer std.posix.unlink(file_path) catch {}; // If error after bind, try your best to unlink the file

        const sender = try Sender.init();
        errdefer sender.deinit();

        // The core difference between sender and receiver = bind.
        // Resource: std.net.connectUnixSocket
        const addr = try std.net.Address.initUnix(file_path);
        try std.posix.bind(sender.sockfd, &addr.any, addr.getOsSockLen());
        // There is no listen function because we're using datagram sockets.

        return .{
            .sender = sender,
            .addr = addr,
        };
    }

    /// Close the socket and unlink the file descriptor.
    pub fn deinit(
        self: Receiver,
    ) void {
        self.sender.deinit();

        // File path slice cannot have a null byte to be used with unlink
        assert(std.mem.indexOfScalar(u8, &(self.addr.un.path), 0) != null); // Invariant because of how addr.un.path stores the file path
        const file_path = std.mem.sliceTo(&(self.addr.un.path), 0);

        std.posix.unlink(file_path) catch |err| {
            // We cannot return an error in a defered function, so we'll just log it.
            std.log.err("Receiver.deinit: failed to unlink socket file: {s} received", .{@errorName(err)});
        };
    }

    const TIMEOUT_NONBLOCKING = 0;
    const TIMEOUT_INFINITE = -1;
    /// Returns the number of bytes read.
    /// Special values: TIMEOUT_NONBLOCKING, TIMEOUT_INFINITE
    pub fn read(
        self: Receiver,
        buffer: *Buffer,
        timeout_ms: i32,
    ) !u32 {
        assert(buffer.len == BUFFER_SIZE); // Precondition

        // Resource: https://www.openmymind.net/TCP-Server-In-Zig-Part-5a-Poll/
        // const because Zig allows mutation of a const aggregate field through C ABI calls (i.e. posix.poll)
        // /\ according to ChatGPT...
        const pollfd: std.posix.pollfd = .{
            .fd = self.sender.sockfd,
            .events = std.posix.POLL.IN | std.posix.POLL.HUP | std.posix.POLL.ERR | std.posix.POLL.NVAL,
            .revents = 0,
        };

        // Resource: man poll OR https://man7.org/linux/man-pages/man2/poll.2.html
        const number_of_fds_polled = try std.posix.poll(@constCast((&pollfd)[0..1]), timeout_ms);
        assert(number_of_fds_polled <= 1); // Invariant: zero fds will be polled if no updates

        // Switch on the poll events returned.
        return switch (pollfd.revents) {
            0 => 0, // No new data
            std.posix.POLL.IN => blk: { // Yes new data
                // Use recv instead of recvfrom because we don't care about replying to the message.
                // recv will return RecvFromError.MessageTooBig in the case of a buffer overrun.
                const msg_len = try std.posix.recv(self.sender.sockfd, buffer, 0);
                break :blk @intCast(msg_len);
            },
            else => blk: {
                // This branch represents all unexpected poll events.
                // They will be logged and an error will be returned.
                if (pollfd.revents & std.posix.POLL.ERR != 0) {
                    std.log.err("Receiver.read: POLL.ERR received\n", .{});
                }
                if (pollfd.revents & std.posix.POLL.HUP != 0) {
                    std.log.err("Receiver.read: POLL.HUP received\n", .{});
                }
                if (pollfd.revents & std.posix.POLL.NVAL != 0) {
                    std.log.err("Receiver.read: POLL.NVAL received\n", .{});
                }
                break :blk ReceiverError.UnexpectedPollEvent;
            },
        };
    }
};

test "DatagramSocket/send and receive" {
    const file_path = "/tmp/receiving_datagram_socket.sock";

    // Create receiver socket.
    const receiver = try Receiver.init(file_path);
    defer receiver.deinit();

    // Create sender socket.
    const sender = try Sender.init();
    defer sender.deinit();

    // Create a buffer of random data to send.
    // We could comptime this, but we want it random every run.
    var sender_buffer: Buffer = undefined;
    for (&sender_buffer) |*byte| {
        byte.* = std.crypto.random.int(u8);
    }

    // Send message and verify number of bytes sent.
    const sent_bytes = try sender.sendto(&sender_buffer, try std.net.Address.initUnix(file_path));
    try std.testing.expectEqual(sender_buffer.len, sent_bytes);

    // Receive message and verify number of bytes received.
    var receiver_buffer: Buffer = undefined;
    const received_bytes = try receiver.read(&receiver_buffer, Receiver.TIMEOUT_NONBLOCKING);
    try std.testing.expectEqual(sender_buffer.len, received_bytes);

    // Verify the buffer contents
    try std.testing.expectEqualSlices(u8, sender_buffer[0..], receiver_buffer[0..]);
}

test "Receiver/read without send" {
    const file_path = "/tmp/receiving_datagram_socket.sock";

    // Create receiver socket.
    const receiver = try Receiver.init(file_path);
    defer receiver.deinit();

    // Try to read and verify no bytes received.
    var receiver_buffer: Buffer = undefined;
    const received_bytes = try receiver.read(&receiver_buffer, Receiver.TIMEOUT_NONBLOCKING);
    try std.testing.expectEqual(0, received_bytes);
}

test "Receiver/max file path length" {
    // Find target-specific max path length
    const max_path_len = comptime blk: {
        const sock_addr = std.posix.sockaddr.un{
            .family = std.posix.AF.UNIX,
            .path = undefined,
        };
        break :blk sock_addr.path.len - 1; // -1 for null terminator
    };

    // Create a file paths by padding with 'x'
    const base_file_path = "/tmp/receiving_datagram_socket.sock-";
    const max_len_fp = base_file_path ++ "x" ** (max_path_len - base_file_path.len);
    const too_long_fp = base_file_path ++ "x" ** (max_path_len - base_file_path.len + 1);

    // Max length
    const receiver = try Receiver.init(max_len_fp);
    receiver.deinit();

    // Too long
    try std.testing.expectError(error.NameTooLong, Receiver.init(too_long_fp));
}
